import Foundation

/// Reads one public post's text from X's official embed endpoint
/// (publish.twitter.com/oembed), the one websites use to embed a post.
/// Read-only, no account, no scraping of x.com.
public struct OEmbed: Sendable {
    public static let endpoint = "https://publish.twitter.com/oembed"
    public var transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func post(for url: String) async throws -> SourcePost {
        var components = URLComponents(string: Self.endpoint)!
        components.queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "omit_script", value: "true"),
            URLQueryItem(name: "dnt", value: "true"),
        ]
        let request = URLRequest(url: components.url!, timeoutInterval: 20)
        let (data, response) = try await transport.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw OEmbedError.unreadable(url) }
        return try Self.parse(data, url: url)
    }

    public static func parse(_ data: Data, url: String) throws -> SourcePost {
        let body = try JSONDecoder().decode(Body.self, from: data)
        let handle = body.authorURL.flatMap { URL(string: $0)?.lastPathComponent }.map { "@\($0)" } ?? ""
        let text = paragraph(in: body.html)
        guard !text.isEmpty else { throw OEmbedError.unreadable(url) }
        return SourcePost(url: url, author: handle, text: text)
    }

    /// The post's text: the first <p> of the embed, with tags removed and entities decoded.
    static func paragraph(in html: String) -> String {
        guard let match = html.firstMatch(of: /<p[^>]*>(.*?)<\/p>/.dotMatchesNewlines()) else { return "" }
        var text = String(match.1)
        text = text.replacing(/<br\s*\/?>/, with: "\n")
        text = text.replacing(/<a[^>]*>pic\.twitter\.com\/\w+<\/a>/, with: "")
        text = text.replacing(/<[^>]+>/, with: "")
        for (entity, value) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"),
                                ("&nbsp;", " "), ("&mdash;", "—"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct Body: Decodable {
        var html: String
        var authorURL: String?
        enum CodingKeys: String, CodingKey {
            case html
            case authorURL = "author_url"
        }
    }
}

public enum OEmbedError: LocalizedError {
    case unreadable(String)
    public var errorDescription: String? {
        switch self {
        case .unreadable(let url): "Couldn't read \(url). It may be private or deleted. Paste its text under the link instead."
        }
    }
}
