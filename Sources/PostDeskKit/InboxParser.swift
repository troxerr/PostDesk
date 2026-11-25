import Foundation

/// Reads posts you copied from X. Blocks are separated by a line of `---`.
/// Each block is the post URL, an optional `by @handle` line, then the post text.
/// This is the same format as the project's inbox.txt.
public enum InboxParser {
    /// One block of pasted text: links that came without text, and a post when the block has text.
    struct Block {
        var bare: [String] = []
        var post: SourcePost?
    }

    public static func parse(_ text: String) -> [SourcePost] {
        var seen = Set<String>()
        // The same post pasted twice counts once.
        return blocks(in: text).compactMap(\.post).filter { seen.insert($0.url).inserted }
    }

    /// Post links in `text` that came without their text, written as https://x.com/handle/status/id.
    /// Links inside a post's own text are not included.
    public static func bareLinks(in text: String) -> [String] {
        let withText = Set(parse(text).map { canonical($0.url) })
        var seen = Set<String>()
        return blocks(in: text).flatMap(\.bare).map(canonical)
            .filter { !withText.contains($0) && seen.insert($0).inserted }
    }

    /// Blocks are separated by a line of `---`. A block starts with one or more link lines. With
    /// text after them (an optional `by @handle` line, then the post), the last link is that post's
    /// and the ones before it are bare. Without text, every link is bare.
    static func blocks(in text: String) -> [Block] {
        var result: [Block] = []
        var lines: [String] = []
        func flush() {
            defer { lines = [] }
            var rest = lines.map { $0.trimmingCharacters(in: .whitespaces) }
            while let first = rest.first, first.isEmpty { rest.removeFirst() }
            var links: [String] = []
            while let first = rest.first, first.hasPrefix("http"), !first.contains(" ") {
                links.append(first)
                rest.removeFirst()
                while let blank = rest.first, blank.isEmpty, !links.isEmpty, rest.count > 1 { rest.removeFirst() }
            }
            guard !links.isEmpty else { return }
            var author = ""
            if let first = rest.first, first.lowercased().hasPrefix("by @") {
                author = String(first.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                rest.removeFirst()
            }
            let body = rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            var block = Block()
            if body.isEmpty {
                block.bare = links.filter(isPostLink)
            } else {
                block.bare = links.dropLast().filter(isPostLink)
                block.post = SourcePost(url: links.last!, author: author, text: body)
            }
            result.append(block)
        }
        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces) == "---" { flush() } else { lines.append(line) }
        }
        flush()
        return result
    }

    static func isPostLink(_ url: String) -> Bool {
        url.contains(/(?:x|twitter)\.com\/\w+\/status(?:es)?\/\d+/)
    }

    static func canonical(_ url: String) -> String {
        guard let match = url.firstMatch(of: /(?:x|twitter)\.com\/(\w+)\/status(?:es)?\/(\d+)/) else { return url }
        return "https://x.com/\(match.1)/status/\(match.2)"
    }
}
