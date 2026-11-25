import Foundation

/// The checks a post must pass before it is marked ready. A post that fails
/// stays a draft and lists what a person still has to do.
public enum PostSafety {
    public static let maxLength = 280
    /// X counts every link as 23 characters.
    static let linkLength = 23

    public static func problems(in text: String, needsMedia: Bool) -> [String] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var problems: [String] = []
        if text.isEmpty { problems.append("The post is empty.") }
        if hasPlaceholder(text) { problems.append("Has a placeholder to fill in.") }
        if weightedLength(text) > maxLength { problems.append("Longer than \(maxLength) characters.") }
        if needsMedia { problems.append("Needs a video or image attached.") }
        if text.contains(/https?:\/\//) {
            problems.append("Has a link. X shows posts with links to fewer people, so put the link in a reply.")
        }
        if text.contains(/(^|\s)#[A-Za-z]\w*/) { problems.append("Has a hashtag. Take it out: X doesn't need them.") }
        return problems
    }

    public static func hasPlaceholder(_ text: String) -> Bool {
        text.contains(/\[[^\]\n]+\]/) || text.contains("{{") || text.contains("TODO") || text.contains("TK ")
    }

    public static func weightedLength(_ text: String) -> Int {
        let links = text.matches(of: /https?:\/\/\S+/)
        let linkChars = links.reduce(0) { $0 + $1.output.count }
        return text.count - linkChars + links.count * linkLength
    }
}
