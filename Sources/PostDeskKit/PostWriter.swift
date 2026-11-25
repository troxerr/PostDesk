import Foundation

public struct Commit: Codable, Hashable, Sendable {
    public var repo: String
    public var hash: String
    public var date: String
    public var subject: String

    public init(repo: String, hash: String, date: String, subject: String) {
        self.repo = repo
        self.hash = hash
        self.date = date
        self.subject = subject
    }
}

/// Writes the week's original posts from real commits, so every claim has a source.
public struct PostWriter: Sendable {
    public var client: ClaudeClient
    public var persona: Persona

    public init(client: ClaudeClient, persona: Persona) {
        self.client = client
        self.persona = persona
    }

    public func write(commits: [Commit], count: Int? = nil) async throws -> [PostDraft] {
        let data = try await client.structured(system: systemPrompt, user: userPrompt(commits: commits, count: count ?? persona.postsPerWeek),
                                               schema: Self.schema, effort: "medium", maxTokens: 16000)
        return try Self.drafts(from: data)
    }

    /// Writes one new version of a post with the same facts.
    public func rewrite(_ draft: PostDraft) async throws -> PostDraft? {
        let user = """
        Write 1 post. It replaces this draft, with the same facts and a different angle or opening:

        \(draft.text)

        It was based on: \(draft.basedOn)
        """
        let data = try await client.structured(system: systemPrompt, user: user, schema: Self.schema,
                                               effort: "medium", maxTokens: 8000)
        return try Self.drafts(from: data).first
    }

    static func drafts(from data: Data?) throws -> [PostDraft] {
        guard let data else { return [] }
        let result = try JSONDecoder().decode(Result.self, from: data)
        return result.posts.compactMap { post in
            let text = post.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : PostDraft(text: text, basedOn: post.basedOn, needsMedia: post.needsMedia)
        }
    }

    public var systemPrompt: String {
        let products = persona.products.map { "- \($0.name): \($0.pitch)" }.joined(separator: "\n")
        return """
        You write original posts on X for \(persona.name) (\(persona.handle)), \(persona.bio).
        The account builds in public for streamers and clippers.

        Their products:
        \(products)

        Rules:
        - Every claim comes from the commits you are given. Never invent numbers, users, sales or dates.
          If a post needs a number you don't have, write it as [number] so a person fills it in.
        - Under 280 characters each. First person, plain words, one idea per post.
        - No links in the post (X shows those to fewer people), at most one hashtag, no emoji spam,
          no em dashes, no asking for likes, follows or reposts.
        - Mix the kinds of post: what shipped, how something works, a problem you hit, a small lesson.
        - Set needs_media to true when the post only works with a clip or screenshot.
        - based_on names the commits the post comes from.
        \(persona.styleRules)
        """
    }

    func userPrompt(commits: [Commit], count: Int) -> String {
        let lines = commits.map { "\($0.date) \($0.repo) \($0.hash): \($0.subject)" }.joined(separator: "\n")
        return "Write \(count) posts for the coming week from these commits:\n\n\(lines)"
    }

    struct Result: Decodable {
        struct Post: Decodable {
            var text: String
            var needsMedia: Bool
            var basedOn: String

            enum CodingKeys: String, CodingKey {
                case text
                case needsMedia = "needs_media"
                case basedOn = "based_on"
            }
        }
        var posts: [Post]
    }

    static let schema = """
    {"type":"object","additionalProperties":false,"required":["posts"],
     "properties":{"posts":{"type":"array","items":{"type":"object","additionalProperties":false,
       "required":["text","needs_media","based_on"],
       "properties":{"text":{"type":"string"},"needs_media":{"type":"boolean"},"based_on":{"type":"string"}}}}}}
    """
}
