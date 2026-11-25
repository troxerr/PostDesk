import Foundation

/// A post on X that someone might reply to. It comes from text you pasted
/// or from the official X API search, never from scripting the X website.
public struct SourcePost: Codable, Hashable, Sendable, Identifiable {
    public var url: String
    public var author: String
    public var text: String

    public var id: String { url }
    public var postID: String? { XLinks.postID(in: url) }

    public init(url: String, author: String = "", text: String) {
        self.url = url
        self.author = author
        self.text = text
    }
}

public enum DraftStatus: String, Codable, Sendable {
    case open, posted, dismissed
}

/// A suggested reply. You edit it and post it yourself on X.
public struct ReplyDraft: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var post: SourcePost
    public var leadScore: Int
    public var reason: String
    public var mentionsProduct: Bool
    public var reply: String
    public var status: DraftStatus
    public var createdAt: Date

    public init(id: UUID = UUID(), post: SourcePost, leadScore: Int, reason: String,
                mentionsProduct: Bool, reply: String, status: DraftStatus = .open, createdAt: Date = .now) {
        self.id = id
        self.post = post
        self.leadScore = leadScore
        self.reason = reason
        self.mentionsProduct = mentionsProduct
        self.reply = reply
        self.status = status
        self.createdAt = createdAt
    }

    public var replyLink: URL? {
        post.postID.flatMap { XLinks.replyIntent(to: $0, text: reply) }
    }
}

/// A post that was read but not worth a reply, and why.
public struct SkippedPost: Codable, Hashable, Sendable, Identifiable {
    public var post: SourcePost
    public var reason: String
    public var id: String { post.url }

    public init(post: SourcePost, reason: String) {
        self.post = post
        self.reason = reason
    }
}

/// An original post for @-handle, written from real commits.
public struct PostDraft: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    /// The commits or facts the post is based on.
    public var basedOn: String
    public var needsMedia: Bool
    public var status: DraftStatus
    public var createdAt: Date

    public init(id: UUID = UUID(), text: String, basedOn: String, needsMedia: Bool,
                status: DraftStatus = .open, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.basedOn = basedOn
        self.needsMedia = needsMedia
        self.status = status
        self.createdAt = createdAt
    }

    /// What still needs a person before this can go out. Empty means ready.
    public var problems: [String] { PostSafety.problems(in: text, needsMedia: needsMedia) }
    public var isReady: Bool { problems.isEmpty }
    public var composeLink: URL? { XLinks.composeIntent(text: text) }
}

public struct Product: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var pitch: String

    public init(id: UUID = UUID(), name: String, pitch: String) {
        self.id = id
        self.name = name
        self.pitch = pitch
    }
}

public enum Tone: String, Codable, CaseIterable, Sendable, Identifiable {
    case friendly, direct, technical, playful
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .friendly: "Friendly"
        case .direct: "Direct"
        case .technical: "Technical"
        case .playful: "Playful"
        }
    }

    var instruction: String {
        switch self {
        case .friendly: "warm and helpful, like a fellow creator who has been there."
        case .direct: "short and to the point. Lead with the answer, no warm-up."
        case .technical: "precise and specific. Name the tool, the setting, or the number."
        case .playful: "light and a little funny, but still useful. Never mocking."
        }
    }
}

/// Who the drafts speak for, and where the facts come from.
public struct Persona: Codable, Hashable, Sendable {
    public var name: String
    public var handle: String
    public var bio: String
    public var products: [Product]
    /// A post must contain one of these to be sent to Claude. Empty means every post.
    public var keywords: [String]
    /// Official X API recent-search queries (needs a bearer token).
    public var searchQueries: [String]
    /// Local git repositories whose commits the weekly posts are written from.
    public var repoPaths: [String]
    public var model: String
    public var dailyMax: Int
    /// How the drafts sound.
    public var tone: Tone
    /// Anything else Claude should follow, in your words ("never mention prices").
    public var extraInstructions: String
    public var postsPerWeek: Int
    /// How many days of commits the weekly posts read.
    public var commitDays: Int
    /// Replies to posts that score below this lead are skipped.
    public var minLead: Int

    public init(name: String, handle: String, bio: String, products: [Product], keywords: [String],
                searchQueries: [String], repoPaths: [String], model: String = ClaudeClient.defaultModel,
                dailyMax: Int = 10, tone: Tone = .friendly, extraInstructions: String = "",
                postsPerWeek: Int = 5, commitDays: Int = 7, minLead: Int = 3) {
        self.name = name
        self.handle = handle
        self.bio = bio
        self.products = products
        self.keywords = keywords
        self.searchQueries = searchQueries
        self.repoPaths = repoPaths
        self.model = model
        self.dailyMax = dailyMax
        self.tone = tone
        self.extraInstructions = extraInstructions
        self.postsPerWeek = postsPerWeek
        self.commitDays = commitDays
        self.minLead = minLead
    }

    /// Settings saved by an older version are missing the newer keys: fill those with defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = Persona.astLabs
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? base.name
        handle = try c.decodeIfPresent(String.self, forKey: .handle) ?? base.handle
        bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? base.bio
        products = (try c.decodeIfPresent([Product].self, forKey: .products) ?? base.products).map(Self.upgradedPitch)
        keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? base.keywords
        searchQueries = try c.decodeIfPresent([String].self, forKey: .searchQueries) ?? base.searchQueries
        repoPaths = try c.decodeIfPresent([String].self, forKey: .repoPaths) ?? base.repoPaths
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? base.model
        dailyMax = try c.decodeIfPresent(Int.self, forKey: .dailyMax) ?? base.dailyMax
        tone = try c.decodeIfPresent(Tone.self, forKey: .tone) ?? base.tone
        extraInstructions = try c.decodeIfPresent(String.self, forKey: .extraInstructions) ?? base.extraInstructions
        postsPerWeek = try c.decodeIfPresent(Int.self, forKey: .postsPerWeek) ?? base.postsPerWeek
        commitDays = try c.decodeIfPresent(Int.self, forKey: .commitDays) ?? base.commitDays
        minLead = try c.decodeIfPresent(Int.self, forKey: .minLead) ?? base.minLead
    }

    /// The first version's built-in pitches let Claude mix the two products up.
    /// A pitch still word for word the old default gets the sharper one; edited pitches stay.
    static let oldPitches = [
        "watches Twitch chat while you stream and saves the moments chat reacts to as 9:16 vertical clips; Windows app, 3 free clips a week, $39 once",
        "Mac app in development that finds chat spikes in a Twitch or YouTube VOD and shows what the streamer said at that moment",
    ]

    static func upgradedPitch(_ product: Product) -> Product {
        guard oldPitches.contains(product.pitch),
              let new = Persona.astLabs.products.first(where: { $0.name == product.name }) else { return product }
        var product = product
        product.pitch = new.pitch
        return product
    }

    /// What separates a person's post from a chatbot's, for every prompt. Tells.find checks the same list.
    static let humanVoice = """
    - Sound like a person typing quickly, not a chatbot. Contractions, plain words, one specific detail
      (a number, a tool, a setting, something that actually happened) instead of general advice.
    - Vary how replies start. Do not open with "Been there", "Quick trick", "Quick win", "Honestly", "Great question"
      or any greeting. Start with the useful part. Do not end with a question unless you really want the answer.
    - No "not just X, but Y" or "it's not X, it's Y" contrasts. No "the real X". No dashes of any kind, no emoji,
      no hashtags. Never explain why something matters or sum up the point after making it.
    - Don't use words like leverage, unlock, elevate, seamless, robust, pivotal, crucial, landscape, delve.
    - Don't start with a one-line saying ("Chat timestamps beat scrubbing video.") and don't end with a line that
      explains why it matters ("Nobody wants an update landing mid stream."). Say the thing and stop.
    - Don't say what a product can't do ("it won't cut clips", "you'd still cut them yourself") unless the post asks
      for something it doesn't do. Describe what it does and stop. Never repeat a stock disclaimer. One product mention per reply is plenty.
    - Say what a feature does in the words of its commit (a streamer you monitor, not "a stream you're watching").
      Say "now" at most once, and skip "instead of" contrasts.
    - Never add effort, backstory, or feelings the facts don't contain ("took me a few days", "I was so frustrated").
    - Don't list things in threes. Short sentences are fine. A fragment is fine. Uneven is human.
    - Never sound more excited or more certain than the facts allow. State a fact about a platform (limits, menu
      names, retention periods, pricing, features) only when you are sure of it. If you are not, say what to check
      or ask a question instead. Never invent numbers.
    """

    /// The tone and your own rules, as lines for a system prompt.
    public var styleRules: String {
        var lines = [Self.humanVoice, "- Tone: \(tone.instruction)"]
        let extra = extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { lines.append("- The account owner's own rules, which win over the rest: \(extra)") }
        return lines.joined(separator: "\n")
    }

    public static let astLabs = Persona(
        name: "Austin",
        handle: "@AST_Labs",
        bio: "an indie Mac and Windows developer who builds tools that read Twitch and YouTube chat",
        products: [
            Product(name: "ClipSpike", pitch: "Windows app for live streams: watches Twitch chat while you stream and saves the moments chat reacts to as 9:16 vertical clips; 3 free clips a week, $39 once"),
            Product(name: "StreamSpike", pitch: "Mac app, still in development, for past streams: finds where chat spiked in a finished Twitch or YouTube VOD and shows what the streamer said at that moment; it does not make clips"),
        ],
        keywords: ["clip", "clipping", "highlight", "vod", "twitch", "stream", "chat", "shorts", "tiktok", "ffmpeg", "whisper"],
        searchQueries: ["twitch clips", "vod highlights"],
        repoPaths: []
    )
}
