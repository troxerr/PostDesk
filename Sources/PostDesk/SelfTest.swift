import Foundation
import PostDeskKit

/// `APP_STORE=/tmp/postdesk-self.json PostDesk --selftest`
/// Runs the real pipeline with your key and settings: drafts replies to four
/// sample posts, redrafts one, writes posts from your repositories' commits,
/// and prints everything as Markdown. Nothing is posted anywhere.
///   ANTHROPIC_API_KEY=...   use this key instead of the keychain's
///   SELFTEST_REPOS=a:b      read commits from these folders instead of Settings > Sources
/// Exit 0 when every check passed.
enum SelfTest {
    static let samples = """
    https://x.com/sample_streamer/status/1860000000000000001
    by @sample_streamer
    Spent 3 hours last night scrubbing my Twitch VOD for clips and found maybe 4 good ones. There has to be a faster way.
    ---
    https://x.com/sample_dev/status/1860000000000000002
    by @sample_dev
    Anyone have a clean FFmpeg recipe for turning 16:9 gameplay into 9:16 without cropping out the action?
    ---
    https://x.com/sample_clipper/status/1860000000000000003
    by @sample_clipper
    Chat went insane when he hit the clutch and I missed it because I was refilling my drink. Clipping streams is a full time job.
    ---
    https://x.com/sample_food/status/1860000000000000004
    by @sample_food
    Best stream snacks? Thinking chips but open to ideas
    """

    private static var failures: [String] = []
    private static var notes: [String] = []

    static func run() async -> Int32 {
        let env = ProcessInfo.processInfo.environment
        guard let store = env["APP_STORE"], store.hasPrefix("/tmp/") || store.hasPrefix("/private/tmp/") else {
            print("Set APP_STORE to a file in /tmp, so the self-test never touches your real desk.")
            return 2
        }
        let key = env["ANTHROPIC_API_KEY"] ?? Keychain.read(Keychain.anthropic)
        guard !key.isEmpty else {
            print("No Anthropic key: add one in Settings > Keys, or set ANTHROPIC_API_KEY.")
            return 2
        }
        let persona = AppModel.loadPersona()
        let client = ClaudeClient(apiKey: key, model: persona.model)
        print("# PostDesk self-test\n")
        print("Model \(client.model), tone \(persona.tone.title), \(persona.keywords.count) keywords, \(persona.repoPaths.count) repositories.\n")

        await replies(persona: persona, client: client)
        await posts(persona: persona, client: client, repos: env["SELFTEST_REPOS"]?.split(separator: ":").map(String.init))
        storeRoundTrip(URL(fileURLWithPath: store))

        print("\n## Result\n")
        notes.forEach { print("- note: \($0)") }
        failures.forEach { print("- FAIL: \($0)") }
        print(failures.isEmpty ? "PASS" : "FAIL (\(failures.count))")
        return failures.isEmpty ? 0 : 1
    }

    private static func replies(persona: Persona, client: ClaudeClient) async {
        print("## Replies\n")
        let drafter = ReplyDrafter(client: client, persona: persona)
        let posts = InboxParser.parse(samples)
        check(posts.count == 4, "the sample inbox parses into 4 posts")
        var firstDraft: ReplyDraft?
        for post in posts {
            print("### \(post.author)\n\n> \(post.text)\n")
            guard ReplyDrafter.keywordMatch(post, keywords: persona.keywords) else {
                print("Skipped before Claude: no keyword.\n")
                continue
            }
            let start = Date()
            do {
                switch try await drafter.draft(post) {
                case .draft(let draft):
                    firstDraft = firstDraft ?? draft
                    print("**Lead \(draft.leadScore)/10**, \(draft.reply.count) chars\(draft.mentionsProduct ? ", mentions a product" : ""), \(seconds(since: start))\n")
                    print(draft.reply + "\n")
                    print("_\(draft.reason)_\n")
                    check(draft.reply.count <= ReplyDrafter.maxReplyLength, "reply to \(post.author) fits in \(ReplyDrafter.maxReplyLength) characters")
                    check(endsWhole(draft.reply), "reply to \(post.author) ends on a whole sentence")
                    check(draft.reply.components(separatedBy: "ClipSpike").count + draft.reply.components(separatedBy: "StreamSpike").count <= 3,
                          "reply to \(post.author) names at most one product")
                    check(draft.replyLink != nil, "reply to \(post.author) has an X reply link")
                    check(!draft.reply.contains("—"), "reply to \(post.author) has no em dash")
                    check(!draft.reply.contains("http"), "reply to \(post.author) has no link")
                    if post.author == "@sample_food" { failures.append("Claude drafted a reply to the off-topic snack post instead of skipping it") }
                case .skipped(let skipped):
                    print("Skipped by Claude (\(seconds(since: start))): \(skipped.reason)\n")
                    if post.author != "@sample_food" { notes.append("Claude skipped \(post.author), a post the app is meant for.") }
                }
            } catch {
                failures.append("drafting a reply to \(post.author): \(error.localizedDescription)")
            }
        }
        guard let firstDraft else {
            failures.append("no replies were drafted")
            return
        }
        do {
            if case .draft(let again) = try await drafter.draft(firstDraft.post, note: ReplyDrafter.redraftNote(replacing: firstDraft.reply)) {
                print("### Redraft of the first reply\n\n\(again.reply)\n")
                check(again.reply != firstDraft.reply, "a redraft gives a different reply")
                check(endsWhole(again.reply), "the redraft ends on a whole sentence")
            } else {
                failures.append("the redraft was skipped")
            }
        } catch {
            failures.append("redrafting: \(error.localizedDescription)")
        }
    }

    private static func posts(persona: Persona, client: ClaudeClient, repos: [String]?) async {
        print("## Posts\n")
        let paths = repos ?? persona.repoPaths
        guard !paths.isEmpty else {
            notes.append("No repositories in Settings > Sources, so weekly posts weren't tested. Set SELFTEST_REPOS to try them.")
            return
        }
        do {
            var commits: [Commit] = []
            for path in paths {
                commits += try await GitLog.recentCommits(in: path, days: max(persona.commitDays, 1))
            }
            print("\(commits.count) commits from the last \(persona.commitDays) days.\n")
            guard !commits.isEmpty else {
                notes.append("No recent commits, so weekly posts weren't tested.")
                return
            }
            let start = Date()
            let drafts = try await PostWriter(client: client, persona: persona).write(commits: commits)
            print("Written in \(seconds(since: start)).\n")
            check(!drafts.isEmpty && drafts.count <= persona.postsPerWeek, "the writer returns 1 to \(persona.postsPerWeek) posts (got \(drafts.count))")
            check(Set(drafts.map(\.text)).count == drafts.count, "no two posts are the same")
            for draft in drafts where draft.text.contains(/(^|\s)#[A-Za-z]/) {
                notes.append("A post has a hashtag although the prompt says none: \(draft.text.prefix(60))…")
            }
            for (index, draft) in drafts.enumerated() {
                print("### \(index + 1). \(draft.isReady ? "Ready" : "Needs you")\n\n\(draft.text)\n")
                print("_Based on: \(draft.basedOn)_\n")
                draft.problems.forEach { print("- \($0)") }
                if !draft.problems.isEmpty { print("") }
            }
        } catch {
            failures.append("writing posts: \(error.localizedDescription)")
        }
    }

    private static func storeRoundTrip(_ url: URL) {
        var state = DeskState()
        state.addToInbox(InboxParser.parse(samples))
        let store = DeskStore(url: url)
        do {
            try store.save(state)
            check(store.load() == state, "the desk file saves and loads")
        } catch {
            failures.append("saving the desk file: \(error.localizedDescription)")
        }
    }

    private static func endsWhole(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return ".!?)\"'".contains(last)
    }

    private static func check(_ ok: Bool, _ what: String) {
        if !ok { failures.append(what) }
    }

    private static func seconds(since start: Date) -> String {
        String(format: "%.1f s", Date().timeIntervalSince(start))
    }
}
