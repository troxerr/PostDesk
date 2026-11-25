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

    public init(name: String, handle: String, bio: String, products: [Product], keywords: [String],
                searchQueries: [String], repoPaths: [String], model: String = ClaudeClient.defaultModel,
                dailyMax: Int = 10) {
        self.name = name
        self.handle = handle
        self.bio = bio
        self.products = products
        self.keywords = keywords
        self.searchQueries = searchQueries
        self.repoPaths = repoPaths
        self.model = model
        self.dailyMax = dailyMax
    }

    public static let astLabs = Persona(
        name: "Austin",
        handle: "@AST_Labs",
        bio: "an indie Mac and Windows developer who builds tools that read Twitch and YouTube chat",
        products: [
            Product(name: "ClipSpike", pitch: "watches Twitch chat while you stream and saves the moments chat reacts to as 9:16 vertical clips; Windows app, 3 free clips a week, $39 once"),
            Product(name: "StreamSpike", pitch: "Mac app in development that finds chat spikes in a Twitch or YouTube VOD and shows what the streamer said at that moment"),
        ],
        keywords: ["clip", "clipping", "highlight", "vod", "twitch", "stream", "chat", "shorts", "tiktok", "ffmpeg", "whisper"],
        searchQueries: ["twitch clips", "vod highlights"],
        repoPaths: []
    )
}
