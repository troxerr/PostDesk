import Foundation

/// Habits that make a draft read like a chatbot wrote it. Drafts that have one
/// are sent back to Claude once, with the habit named, before you see them.
/// Based on the signs listed in Wikipedia's "Signs of AI writing".
public enum Tells {
    /// Short names of what was found, for a note back to Claude. Empty means none.
    public static func find(in text: String) -> [String] {
        var found: [String] = []
        func add(_ name: String, if hit: Bool) { if hit, !found.contains(name) { found.append(name) } }

        add("an em or en dash", if: text.contains("—") || text.contains("–") || text.contains(" -- "))
        add("a \"not just X, but Y\" contrast", if:
            text.contains(/\bnot (just|only|merely)\b/.ignoresCase())
            || text.contains(/\b(isn't|wasn't|aren't|it's not|that's not|this isn't)\b[^.?!\n]{1,50}[,;] (it's|but|it is)\b/.ignoresCase())
            || text.contains(/\bnot [^.?!\n,]{1,40}, but\b/.ignoresCase()))
        add("a stock opener", if:
            text.contains(/^\W*(been there|quick (trick|win|tip|fix|hack)|honestly|here'?s the thing|great question|good question|love this|the real|look,|let'?s dive|ah,|oof)\b/.ignoresCase()))
        add("a word chatbots overuse", if:
            text.contains(/\b(delve|game-?changer|leverage|unlock|elevate|seamless(ly)?|robust|tapestry|testament|pivotal|crucial|landscape|streamline|supercharge|dive into|at the end of the day|let that sink in|take it to the next level)\b/.ignoresCase()))
        add("a closing line that repeats the point", if:
            text.contains(/\b(that'?s the real (win|magic|power)|and that'?s (the point|it|what matters)|that'?s a game)/.ignoresCase()))
        add("a closing line that explains why it matters", if:
            text.contains(/\b(nobody wants|no one wants|shouldn't have to|worth (reporting|noting|remembering)|that'?s what matters|and that matters)\b/.ignoresCase()))
        add("a one-line saying as an opener", if:
            text.contains(/^[A-Z][A-Za-z' ]{3,40} (beats?|wins over|is the best) [A-Za-z' ]{3,30}\./))
        add("an effort claim the commits may not support", if:
            text.contains(/\btook (me )?(a few|several|a couple( of)?|\d+|weeks|days)\b[^.]{0,25}\b(days|weeks|months|hours|nights)\b/.ignoresCase()))
        add("an effort claim the commits may not support", if:
            text.contains(/\b(spent|put in) (part of |a (lot|bit) of |some )?(this|the) (week|weekend|day|month)\b/.ignoresCase()))
        add("emoji", if: text.unicodeScalars.contains { $0.properties.isEmojiPresentation })
        return found
    }

    /// The note sent back to Claude.
    public static func note(for tells: [String]) -> String {
        "This reads like a chatbot wrote it: it has " + tells.joined(separator: ", ")
            + ". Rewrite it the way a person types on their phone: plain, specific, no staging."
    }
}
