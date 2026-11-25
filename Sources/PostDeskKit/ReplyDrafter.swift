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

    public func draft(_ post: SourcePost) async throws -> Outcome {
        let user = "Post by \(post.author.isEmpty ? "unknown" : post.author) (\(post.url)):\n\n\(post.text)"
        let data = try await client.structured(system: systemPrompt, user: user, schema: Self.schema, effort: "low")
        return try Self.outcome(from: data, post: post)
    }

    static func outcome(from data: Data?, post: SourcePost) throws -> Outcome {
        guard let data else { return .skipped(SkippedPost(post: post, reason: "Claude declined to answer this one.")) }
        let result = try JSONDecoder().decode(Result.self, from: data)
        let reply = trimmed(result.reply)
        guard result.relevant, !reply.isEmpty else { return .skipped(SkippedPost(post: post, reason: result.reason)) }
        return .draft(ReplyDraft(post: post, leadScore: min(max(result.leadScore, 1), 10), reason: result.reason,
                                 mentionsProduct: result.mentionsProduct, reply: reply))
    }

    static func trimmed(_ reply: String) -> String {
        let reply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reply.count > maxReplyLength else { return reply }
        let cut = String(reply.prefix(maxReplyLength))
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
        - Under \(Self.maxReplyLength) characters. First person, plain words. No hashtags, no emoji, no links,
          no em dashes, no flattery openers, no asking for likes, follows or reposts.
        - If the post is off-topic, hostile, sensitive, or a reply would feel like an ad, set relevant to
          false and leave reply empty.
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
