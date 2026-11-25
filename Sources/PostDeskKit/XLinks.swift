import Foundation

/// Links that open X's own composer with the text filled in. You still press Post.
public enum XLinks {
    public static func postID(in url: String) -> String? {
        guard let match = url.firstMatch(of: /\/status(?:es)?\/(\d+)/) else { return nil }
        return String(match.1)
    }

    public static func replyIntent(to postID: String, text: String) -> URL? {
        intent([URLQueryItem(name: "in_reply_to", value: postID), URLQueryItem(name: "text", value: text)])
    }

    public static func composeIntent(text: String) -> URL? {
        intent([URLQueryItem(name: "text", value: text)])
    }

    private static func intent(_ items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: "https://x.com/intent/post")!
        components.queryItems = items
        // URLComponents leaves "+" alone, and X would read it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}
