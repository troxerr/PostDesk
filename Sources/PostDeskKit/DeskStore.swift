import Foundation

/// Everything PostDesk keeps, in one JSON file.
public struct DeskState: Codable, Sendable, Equatable {
    /// Pasted or fetched posts not yet read by Claude.
    public var inbox: [SourcePost] = []
    public var replies: [ReplyDraft] = []
    public var skipped: [SkippedPost] = []
    public var posts: [PostDraft] = []
    /// Every post URL already read, so nothing is drafted twice.
    public var seen: Set<String> = []

    public init() {}

    /// Adds posts that are new: not seen before and not already waiting. Returns how many were added.
    @discardableResult
    public mutating func addToInbox(_ new: [SourcePost]) -> Int {
        let waiting = Set(inbox.map(\.url))
        let fresh = new.filter { !seen.contains($0.url) && !waiting.contains($0.url) }
        inbox += fresh
        return fresh.count
    }
}

public struct DeskStore: Sendable {
    public var url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> DeskState {
        guard let data = try? Data(contentsOf: url) else { return DeskState() }
        return (try? Self.decoder.decode(DeskState.self, from: data)) ?? DeskState()
    }

    public func save(_ state: DeskState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(state).write(to: url, options: .atomic)
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
