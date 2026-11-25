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
}
