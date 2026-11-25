import Foundation

/// Reads posts you copied from X. Blocks are separated by a line of `---`.
/// Each block is the post URL, an optional `by @handle` line, then the post text.
/// This is the same format as the project's inbox.txt.
public enum InboxParser {
    public static func parse(_ text: String) -> [SourcePost] {
        var posts: [SourcePost] = []
        var block: [String] = []
        func flush() {
            defer { block = [] }
            var lines = block.map { $0.trimmingCharacters(in: .whitespaces) }
            while let first = lines.first, first.isEmpty { lines.removeFirst() }
            guard let url = lines.first, url.hasPrefix("http") else { return }
            lines.removeFirst()
            var author = ""
            if let first = lines.first, first.lowercased().hasPrefix("by @") {
                author = String(first.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                lines.removeFirst()
            }
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { posts.append(SourcePost(url: url, author: author, text: body)) }
        }
        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces) == "---" { flush() } else { block.append(line) }
        }
        flush()
        // The same post pasted twice counts once.
        var seen = Set<String>()
        return posts.filter { seen.insert($0.url).inserted }
    }

    /// Post links in `text` that came without their text, written as https://x.com/handle/status/id.
    /// Links that start a pasted block with text are left out: `parse` already has those.
    public static func bareLinks(in text: String) -> [String] {
        let withText = Set(parse(text).map { canonical($0.url) })
        var seen = Set<String>()
        return text.matches(of: /https?:\/\/(?:www\.|mobile\.)?(?:x|twitter)\.com\/\w+\/status(?:es)?\/\d+/)
            .map { canonical(String($0.output)) }
            .filter { !withText.contains($0) && seen.insert($0).inserted }
    }

    static func canonical(_ url: String) -> String {
        guard let match = url.firstMatch(of: /(?:x|twitter)\.com\/(\w+)\/status(?:es)?\/(\d+)/) else { return url }
        return "https://x.com/\(match.1)/status/\(match.2)"
    }
}
