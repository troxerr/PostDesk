import Foundation

/// The official X API v2 recent search. Read-only, with your own bearer
/// token (a paid X API plan). It never touches the X website.
public struct XSearch: Sendable {
    public static let endpoint = "https://api.x.com/2/tweets/search/recent"

    public var bearer: String
    public var transport: any HTTPTransport

    public init(bearer: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.bearer = bearer
        self.transport = transport
    }

    public func recent(_ query: String, max: Int = 10) async throws -> [SourcePost] {
        var components = URLComponents(string: Self.endpoint)!
        components.queryItems = [
            URLQueryItem(name: "query", value: "\(query) -is:retweet -is:reply lang:en"),
            URLQueryItem(name: "max_results", value: String(min(Swift.max(max, 10), 100))),
            URLQueryItem(name: "expansions", value: "author_id"),
            URLQueryItem(name: "user.fields", value: "username"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw XSearchError.http(status) }
        return try Self.parse(data)
    }

    public static func parse(_ data: Data) throws -> [SourcePost] {
        let body = try JSONDecoder().decode(Body.self, from: data)
        let users = Dictionary((body.includes?.users ?? []).map { ($0.id, $0.username) }, uniquingKeysWith: { a, _ in a })
        return (body.data ?? []).map { tweet in
            let handle = tweet.authorID.flatMap { users[$0] } ?? "i"
            return SourcePost(url: "https://x.com/\(handle)/status/\(tweet.id)", author: "@\(handle)", text: tweet.text)
        }
    }

    struct Body: Decodable {
        struct Tweet: Decodable {
            var id: String
            var text: String
            var authorID: String?
            enum CodingKeys: String, CodingKey {
                case id, text
                case authorID = "author_id"
            }
        }
        struct User: Decodable {
            var id: String
            var username: String
        }
        struct Includes: Decodable { var users: [User]? }
        var data: [Tweet]?
        var includes: Includes?
    }
}

public enum XSearchError: LocalizedError {
    case http(Int)
    public var errorDescription: String? {
        switch self {
        case .http(401): "X didn't accept the bearer token. Check it in Settings > Keys."
        case .http(403): "Your X API plan doesn't include recent search."
        case .http(429): "X's rate limit was hit. Try again in 15 minutes."
        case .http(let status): "X returned an error (\(status))."
        }
    }
}
