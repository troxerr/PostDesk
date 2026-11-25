import Foundation

/// Decides whether a post deserves a reply and drafts one. It only writes
/// text: there is no code anywhere in PostDesk that posts, likes, follows,
/// sends DMs, or scripts the X website.
public struct ReplyDrafter: Sendable {
    public static let maxReplyLength = 270

    public enum Outcome: Sendable, Equatable {
        case draft(ReplyDraft)
        case skipped(SkippedPost)
    }

    public var client: ClaudeClient
    public var persona: Persona

    public init(client: ClaudeClient, persona: Persona) {
        self.client = client
        self.persona = persona
    }

    public static func keywordMatch(_ post: SourcePost, keywords: [String]) -> Bool {
        let words = keywords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return words.isEmpty || words.contains { post.text.localizedCaseInsensitiveContains($0) }
    }

    /// `note` is an extra request from the account owner for this one post,
    /// like a redraft (`Self.redraftNote`) or a reply they insist on (`Self.insistNote`).
    public func draft(_ post: SourcePost, note: String? = nil) async throws -> Outcome {
        var user = "Post by \(post.author.isEmpty ? "unknown" : post.author) (\(post.url)):\n\n\(post.text)"
        if let note, !note.isEmpty { user += "\n\nNote from \(persona.name): \(note)" }
        var data = try await client.structured(system: systemPrompt, user: user, schema: Self.schema, effort: "low")
        // A draft over the limit, or one that reads like a chatbot, is sent back once so you get the fixed
        // version: shortened in whole sentences, or with the habit named and removed.
        if let first = data, let result = try? JSONDecoder().decode(Result.self, from: first), result.relevant {
            let reply = Self.withoutSpilledJSON(result.reply)
            var fixes: [String] = []
            if reply.count > Self.maxReplyLength {
                fixes.append("It was \(reply.count) characters, over the limit. Rewrite it under \(Self.maxReplyLength - 20) characters, in complete sentences.")
            }
            let tells = Tells.find(in: reply)
            if !tells.isEmpty { fixes.append(Tells.note(for: tells)) }
            if !fixes.isEmpty {
                let again = user + "\n\nYour draft:\n\(reply)\n\n" + fixes.joined(separator: " ")
                if let retry = try await client.structured(system: systemPrompt, user: again, schema: Self.schema, effort: "low") {
                    data = retry
                }
            }
        }
        let minLead = note == Self.insistNote ? 1 : persona.minLead
        return try Self.outcome(from: data, post: post, minLead: minLead)
    }

    public static func redraftNote(replacing old: String) -> String {
        "Write a different reply from this earlier draft, with another angle or detail: \(old)"
    }

    public static let insistNote = "I want to reply to this one. Set relevant to true and write the most useful reply you can, without mentioning the products unless it truly fits."

    static func outcome(from data: Data?, post: SourcePost, minLead: Int = 1) throws -> Outcome {
        guard let data else { return .skipped(SkippedPost(post: post, reason: "Claude declined to answer this one.")) }
        let result = try JSONDecoder().decode(Result.self, from: data)
        let reply = trimmed(result.reply)
        guard result.relevant, !reply.isEmpty else { return .skipped(SkippedPost(post: post, reason: result.reason)) }
        guard result.leadScore >= minLead else {
            return .skipped(SkippedPost(post: post, reason: "Lead \(result.leadScore)/10, under your minimum of \(minLead). \(result.reason)"))
        }
        return .draft(ReplyDraft(post: post, leadScore: min(max(result.leadScore, 1), 10), reason: result.reason,
                                 mentionsProduct: result.mentionsProduct, reply: reply))
    }

    /// Now and then the model spills the next JSON field into the reply text,
    /// like `…in.","relevant":true}`. Cut from the spilled field on.
    static func withoutSpilledJSON(_ reply: String) -> String {
        var reply = reply
        if let spill = reply.firstRange(of: /"\s*,\s*"(relevant|lead_score|reason|mentions_product|reply)"\s*:/) {
            reply = String(reply[..<spill.lowerBound])
        }
        // …or the closing quote and brace of the object itself: `…there."}`
        if let end = reply.firstRange(of: /"\s*\}\s*$/) {
            reply = String(reply[..<end.lowerBound])
        }
        // …or markup copied from an embedded post, like `<br>` or `</br>`.
        reply = reply.replacing(/<\/?[A-Za-z][^>]*>/, with: "")
        return reply
    }

    static func trimmed(_ reply: String) -> String {
        let reply = withoutSpilledJSON(reply).trimmingCharacters(in: .whitespacesAndNewlines)
        guard reply.count > maxReplyLength else { return reply }
        let cut = String(reply.prefix(maxReplyLength))
        // End on a whole sentence when one ends past the halfway point.
        if let end = cut.lastIndex(where: { ".!?".contains($0) }), cut.distance(from: cut.startIndex, to: end) > maxReplyLength / 2 {
            return String(cut[...end])
        }
        guard let space = cut.lastIndex(of: " ") else { return cut }
        return String(cut[..<space])
    }

    public var systemPrompt: String {
        let products = persona.products.map { "- \($0.name): \($0.pitch)" }.joined(separator: "\n")
        return """
        You draft replies on X for \(persona.name) (\(persona.handle)), \(persona.bio).
        They read every draft and post it by hand, or throw it away.

        Their products:
        \(products)

        Decide whether this post is worth a reply from them, then draft one.

        Rules for the reply:
        - Add something specific the author can use: a fix, a number, a short how-to, or a real question.
        - Most replies should not mention the products. Mention one only when it directly solves what the
          post is about, and then say plainly that they built it ("I built ClipSpike for this").
          Never pose as a neutral user or customer.
        - Name at most one product: the one whose description above fits the post. Describe it only with
          what its description says, never with another product's features. If it is in development, say so.
        - Under \(Self.maxReplyLength) characters. First person, plain words. No hashtags, no emoji, no links,
          no em dashes, no flattery openers, no asking for likes, follows or reposts.
        - If the post is off-topic, hostile, sensitive, or a reply would feel like an ad, set relevant to
          false and leave reply empty. Off-topic means it has nothing to do with streaming, clipping, video
          tools, or building software for creators, even if it mentions a stream in passing.
        \(persona.styleRules)

        lead_score: 1-10, how likely this author is to need the products (streamer or clipper with a
        clipping problem scores high; a general tech post scores low).
        """
    }

    struct Result: Decodable {
        var relevant: Bool
        var leadScore: Int
        var reason: String
        var mentionsProduct: Bool
        var reply: String

        enum CodingKeys: String, CodingKey {
            case relevant, reason, reply
            case leadScore = "lead_score"
            case mentionsProduct = "mentions_product"
        }
    }

    static let schema = """
    {"type":"object","additionalProperties":false,
     "required":["relevant","lead_score","reason","mentions_product","reply"],
     "properties":{"relevant":{"type":"boolean"},"lead_score":{"type":"integer"},"reason":{"type":"string"},
                   "mentions_product":{"type":"boolean"},"reply":{"type":"string"}}}
    """
}
