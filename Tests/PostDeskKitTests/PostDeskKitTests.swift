import Foundation
import Testing
@testable import PostDeskKit

/// Answers every request with one canned response and remembers the request.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    let status: Int
    let body: String
    private(set) var requests: [URLRequest] = []

    init(status: Int = 200, body: String) {
        self.status = status
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

/// A Messages API response whose text block is `json`.
func messageBody(_ json: String, stop: String = "end_turn") -> String {
    let body: [String: Any] = [
        "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": json]],
        "stop_reason": stop,
    ]
    return String(decoding: try! JSONSerialization.data(withJSONObject: body), as: UTF8.self)
}

let samplePost = SourcePost(url: "https://x.com/someone/status/1800000000000000001", author: "@someone",
                            text: "Spent 3 hours scrubbing my twitch VOD for clips. There has to be a better way.")

@Suite("Inbox")
struct InboxTests {
    @Test func parsesBlocks() {
        let text = """
        https://x.com/a/status/1
        by @a
        First post
        on two lines
        ---
        https://x.com/b/status/2
        Second post
        ---
        not a link
        ignored
        ---
        https://x.com/a/status/1
        by @a
        First post again
        """
        let posts = InboxParser.parse(text)
        #expect(posts.count == 2)
        #expect(posts[0].author == "@a")
        #expect(posts[0].text == "First post\non two lines")
        #expect(posts[1].author == "")
        #expect(posts[1].postID == "2")
    }

    @Test func inboxSkipsSeenAndWaiting() {
        var state = DeskState()
        state.seen = ["https://x.com/a/status/1"]
        let added = state.addToInbox([SourcePost(url: "https://x.com/a/status/1", text: "x"),
                                      SourcePost(url: "https://x.com/b/status/2", text: "y")])
        #expect(added == 1)
        #expect(state.addToInbox([SourcePost(url: "https://x.com/b/status/2", text: "y")]) == 0)
    }

    @Test func storeRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("postdesk-test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DeskStore(url: url)
        var state = DeskState()
        state.addToInbox([samplePost])
        state.posts.append(PostDraft(text: "Shipped it", basedOn: "abc", needsMedia: false))
        try store.save(state)
        #expect(store.load().inbox == state.inbox)
        #expect(store.load().posts.first?.text == "Shipped it")
    }
}

@Suite("Links")
struct LinkTests {
    @Test func replyIntentKeepsPlusSigns() throws {
        let url = try #require(XLinks.replyIntent(to: "123", text: "C++ & FFmpeg: 2+2"))
        #expect(url.absoluteString.hasPrefix("https://x.com/intent/post?"))
        #expect(url.absoluteString.contains("in_reply_to=123"))
        #expect(url.absoluteString.contains("%2B%2B"))
        let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "text" }?.value
        #expect(text == "C++ & FFmpeg: 2+2")
    }

    @Test func postIDs() {
        #expect(XLinks.postID(in: "https://x.com/a/status/42?s=20") == "42")
        #expect(XLinks.postID(in: "https://twitter.com/a/statuses/7") == "7")
        #expect(XLinks.postID(in: "https://x.com/a") == nil)
    }
}

@Suite("Post safety")
struct SafetyTests {
    @Test func cleanPostIsReady() {
        #expect(PostSafety.problems(in: "Fixed the crash that lost a live run's chat. It now saves every 30 seconds.", needsMedia: false).isEmpty)
    }

    @Test func catchesWhatNeedsAPerson() {
        #expect(PostSafety.hasPlaceholder("We hit [number] clips this week"))
        #expect(PostSafety.hasPlaceholder("TODO add stats"))
        #expect(!PostSafety.hasPlaceholder("Plain post"))
        #expect(PostSafety.problems(in: "Demo", needsMedia: true).count == 1)
        #expect(PostSafety.problems(in: String(repeating: "a", count: 281), needsMedia: false).count == 1)
        #expect(PostSafety.problems(in: "Try it https://clipspike.com", needsMedia: false).count == 1)
        #expect(PostSafety.problems(in: "#a #b", needsMedia: false).count == 1)
        #expect(PostSafety.problems(in: "  ", needsMedia: false).contains("The post is empty."))
    }

    @Test func linksCountAs23() {
        #expect(PostSafety.weightedLength("hi https://example.com/a/very/long/path/that/goes/on") == 3 + 23)
    }
}

@Suite("Claude")
struct ClaudeTests {
    @Test func requestShape() throws {
        let client = ClaudeClient(apiKey: "k", transport: FakeTransport(body: "{}"))
        let request = try client.makeRequest(system: "s", user: "u", schema: ReplyDrafter.schema, effort: "low", maxTokens: 100)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "k")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(body["model"] as? String == "claude-opus-5-5")
        let output = try #require(body["output_config"] as? [String: Any])
        #expect(output["effort"] as? String == "low")
        #expect((output["format"] as? [String: Any])?["type"] as? String == "json_schema")
    }

    @Test func missingKeyFails() async {
        let client = ClaudeClient(apiKey: "", transport: FakeTransport(body: "{}"))
        await #expect(throws: ClaudeError.missingKey) {
            _ = try await client.structured(system: "", user: "", schema: "{}")
        }
    }

    @Test func httpErrorsCarryTheMessage() async {
        let client = ClaudeClient(apiKey: "k", transport: FakeTransport(status: 429, body: #"{"error":{"message":"slow down"}}"#))
        await #expect(throws: ClaudeError.http(429, "slow down")) {
            _ = try await client.structured(system: "", user: "", schema: "{}")
        }
    }

    @Test func schemasAreValidJSON() throws {
        for schema in [ReplyDrafter.schema, PostWriter.schema] {
            #expect(try JSONSerialization.jsonObject(with: Data(schema.utf8)) is [String: Any])
        }
    }
}

@Suite("Replies")
struct ReplyTests {
    @Test func draftsARelevantPost() async throws {
        let json = #"{"relevant":true,"lead_score":12,"reason":"Streamer with a clipping problem","mentions_product":true,"reply":"I built ClipSpike for this. It saves the moments chat reacts to."}"#
        let drafter = ReplyDrafter(client: ClaudeClient(apiKey: "k", transport: FakeTransport(body: messageBody(json))), persona: .astLabs)
        guard case .draft(let draft) = try await drafter.draft(samplePost) else {
            Issue.record("expected a draft")
            return
        }
        #expect(draft.leadScore == 10)
        #expect(draft.mentionsProduct)
        #expect(draft.replyLink?.absoluteString.contains("in_reply_to=1800000000000000001") == true)
    }

    @Test func skipsIrrelevantAndDeclined() async throws {
        let json = #"{"relevant":false,"lead_score":1,"reason":"Off topic","mentions_product":false,"reply":""}"#
        var drafter = ReplyDrafter(client: ClaudeClient(apiKey: "k", transport: FakeTransport(body: messageBody(json))), persona: .astLabs)
        #expect(try await drafter.draft(samplePost) == .skipped(SkippedPost(post: samplePost, reason: "Off topic")))
        drafter.client = ClaudeClient(apiKey: "k", transport: FakeTransport(body: messageBody("{}", stop: "refusal")))
        guard case .skipped = try await drafter.draft(samplePost) else {
            Issue.record("a refusal should skip the post")
            return
        }
    }

    @Test func trimsLongRepliesAtAWord() {
        let long = Array(repeating: "word", count: 100).joined(separator: " ")
        let trimmed = ReplyDrafter.trimmed(long)
        #expect(trimmed.count <= ReplyDrafter.maxReplyLength)
        #expect(trimmed.hasSuffix("word"))
    }

    @Test func keywordFilter() {
        #expect(ReplyDrafter.keywordMatch(samplePost, keywords: ["VOD"]))
        #expect(!ReplyDrafter.keywordMatch(samplePost, keywords: ["golf"]))
        #expect(ReplyDrafter.keywordMatch(samplePost, keywords: []))
    }

    @Test func promptForbidsPosingAsACustomer() {
        let prompt = ReplyDrafter(client: ClaudeClient(apiKey: "k"), persona: .astLabs).systemPrompt
        #expect(prompt.contains("Never pose as a neutral user or customer"))
        #expect(prompt.contains("ClipSpike"))
    }
}

@Suite("Posts")
struct PostTests {
    @Test func writesDraftsFromCommits() async throws {
        let json = #"{"posts":[{"text":"Live runs now save every 30 seconds.","needs_media":false,"based_on":"f0ccefb"},{"text":"Here's a spike [clip]","needs_media":true,"based_on":"79fb996"},{"text":"  ","needs_media":false,"based_on":""}]}"#
        let transport = FakeTransport(body: messageBody(json))
        let writer = PostWriter(client: ClaudeClient(apiKey: "k", transport: transport), persona: .astLabs)
        let commits = [Commit(repo: "StreamSpike", hash: "f0ccefb", date: "2026-11-24", subject: "Long live runs save only what is new")]
        let drafts = try await writer.write(commits: commits)
        #expect(drafts.count == 2)
        #expect(drafts[0].isReady)
        #expect(!drafts[1].isReady)
        let sent = String(decoding: transport.requests[0].httpBody!, as: UTF8.self)
        #expect(sent.contains("f0ccefb"))
    }

    @Test func parsesGitLog() {
        let sep = GitLog.separator
        let output = "f0ccefb\(sep)2026-11-24\(sep)Long live runs save only what is new\n79fb996\(sep)2026-11-23\(sep)Get a notification\n"
        let commits = GitLog.parse(output, repo: "StreamSpike")
        #expect(commits.count == 2)
        #expect(commits[1].subject == "Get a notification")
    }
}

@Suite("X search")
struct XSearchTests {
    @Test func parsesRecentSearch() throws {
        let json = #"{"data":[{"id":"9","text":"need a clipper","author_id":"u1"}],"includes":{"users":[{"id":"u1","username":"streamer"}]}}"#
        let posts = try XSearch.parse(Data(json.utf8))
        #expect(posts == [SourcePost(url: "https://x.com/streamer/status/9", author: "@streamer", text: "need a clipper")])
        #expect(try XSearch.parse(Data("{}".utf8)).isEmpty)
    }
}

@Suite("No automation")
struct NoAutomationTests {
    /// PostDesk drafts text. Nothing in it may post, like, follow, DM, or drive a browser.
    @Test func sourceHasNoPostingCode() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty)
        let banned = ["/2/tweets\"", "api.x.com/2/tweets\"", "/likes", "/following", "/dm_conversations",
                      "WKWebView", "evaluateJavaScript", "AppleScript", "NSAppleScript", "httpMethod = \"DELETE\""]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for word in banned {
                #expect(!text.contains(word), "\(file.lastPathComponent) contains \(word)")
            }
        }
    }
}

@Suite("Customization")
struct CustomizationTests {
    @Test func oldSettingsDecodeWithDefaults() throws {
        let old = #"{"name":"Austin","handle":"@AST_Labs","bio":"dev","products":[],"keywords":["clip"],"searchQueries":[],"repoPaths":["/tmp/x"],"model":"claude-opus-5-5","dailyMax":4}"#
        let persona = try JSONDecoder().decode(Persona.self, from: Data(old.utf8))
        #expect(persona.dailyMax == 4)
        #expect(persona.repoPaths == ["/tmp/x"])
        #expect(persona.tone == .friendly)
        #expect(persona.postsPerWeek == 5)
        #expect(persona.commitDays == 7)
    }

    @Test func toneAndRulesReachBothPrompts() {
        var persona = Persona.astLabs
        persona.tone = .technical
        persona.extraInstructions = "Never mention prices."
        let reply = ReplyDrafter(client: ClaudeClient(apiKey: "k"), persona: persona).systemPrompt
        let post = PostWriter(client: ClaudeClient(apiKey: "k"), persona: persona).systemPrompt
        for prompt in [reply, post] {
            #expect(prompt.contains("precise and specific"))
            #expect(prompt.contains("Never mention prices."))
        }
        persona.extraInstructions = "  "
        #expect(!persona.styleRules.contains("own rules"))
    }

    @Test func postsPerWeekSetsTheCount() async throws {
        var persona = Persona.astLabs
        persona.postsPerWeek = 3
        let transport = FakeTransport(body: messageBody(#"{"posts":[]}"#))
        _ = try await PostWriter(client: ClaudeClient(apiKey: "k", transport: transport), persona: persona)
            .write(commits: [Commit(repo: "r", hash: "h", date: "d", subject: "s")])
        #expect(String(decoding: transport.requests[0].httpBody!, as: UTF8.self).contains("Write 3 posts"))
    }
}

@Suite("Redraft")
struct RedraftTests {
    @Test func noteReachesClaude() async throws {
        let json = #"{"relevant":true,"lead_score":5,"reason":"ok","mentions_product":false,"reply":"Another angle."}"#
        let transport = FakeTransport(body: messageBody(json))
        let drafter = ReplyDrafter(client: ClaudeClient(apiKey: "k", transport: transport), persona: .astLabs)
        _ = try await drafter.draft(samplePost, note: ReplyDrafter.redraftNote(replacing: "First try."))
        let sent = String(decoding: transport.requests[0].httpBody!, as: UTF8.self)
        #expect(sent.contains("First try."))
        #expect(sent.contains("Note from Austin"))
    }

    @Test func rewriteKeepsTheFacts() async throws {
        let json = #"{"posts":[{"text":"New angle on the same fix.","needs_media":false,"based_on":"f0ccefb"}]}"#
        let transport = FakeTransport(body: messageBody(json))
        let writer = PostWriter(client: ClaudeClient(apiKey: "k", transport: transport), persona: .astLabs)
        let old = PostDraft(text: "Old text about the fix.", basedOn: "f0ccefb", needsMedia: false)
        let new = try await writer.rewrite(old)
        #expect(new?.text == "New angle on the same fix.")
        let sent = String(decoding: transport.requests[0].httpBody!, as: UTF8.self)
        #expect(sent.contains("Old text about the fix."))
    }
}

@Suite("Draft quality")
struct QualityTests {
    @Test func lowLeadsAreSkippedUnlessInsisted() async throws {
        let json = #"{"relevant":true,"lead_score":2,"reason":"Snack question","mentions_product":false,"reply":"Try grapes."}"#
        let drafter = ReplyDrafter(client: ClaudeClient(apiKey: "k", transport: FakeTransport(body: messageBody(json))), persona: .astLabs)
        guard case .skipped(let skipped) = try await drafter.draft(samplePost) else {
            Issue.record("a lead of 2 should be skipped at the default minimum of 3")
            return
        }
        #expect(skipped.reason.hasPrefix("Lead 2/10"))
        guard case .draft = try await drafter.draft(samplePost, note: ReplyDrafter.insistNote) else {
            Issue.record("Draft Anyway should ignore the minimum")
            return
        }
    }

    @Test func longRepliesAreSentBackOnce() async throws {
        let long = Array(repeating: "This sentence is long enough.", count: 20).joined(separator: " ")
        let json = #"{"relevant":true,"lead_score":7,"reason":"ok","mentions_product":false,"reply":"\#(long)"}"#
        let transport = FakeTransport(body: messageBody(json))
        let drafter = ReplyDrafter(client: ClaudeClient(apiKey: "k", transport: transport), persona: .astLabs)
        guard case .draft(let draft) = try await drafter.draft(samplePost) else {
            Issue.record("expected a draft")
            return
        }
        #expect(transport.requests.count == 2)
        #expect(String(decoding: transport.requests[1].httpBody!, as: UTF8.self).contains("over the limit"))
        // The fake answers long again, so the fallback trim ends on a whole sentence.
        #expect(draft.reply.count <= ReplyDrafter.maxReplyLength)
        #expect(draft.reply.hasSuffix("."))
    }

    @Test func anyHashtagNeedsAPerson() {
        #expect(PostSafety.problems(in: "Shipped the icon #buildinpublic", needsMedia: false).count == 1)
        #expect(PostSafety.problems(in: "Fixed issue #42 in the parser", needsMedia: false).isEmpty)
    }

    @Test func promptsKeepProductsApart() {
        let reply = ReplyDrafter(client: ClaudeClient(apiKey: "k"), persona: .astLabs).systemPrompt
        #expect(reply.contains("Name at most one product"))
        let post = PostWriter(client: ClaudeClient(apiKey: "k"), persona: .astLabs).systemPrompt
        #expect(post.contains("no hashtags"))
        #expect(post.contains("A new feature is new, not a fix"))
    }
}

@Suite("Pitch upgrade")
struct PitchUpgradeTests {
    @Test func oldDefaultPitchesAreSharpened() throws {
        let old = #"{"products":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"StreamSpike","pitch":"Mac app in development that finds chat spikes in a Twitch or YouTube VOD and shows what the streamer said at that moment"},{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Mine","pitch":"my own words"}]}"#
        let persona = try JSONDecoder().decode(Persona.self, from: Data(old.utf8))
        #expect(persona.products[0].pitch.contains("it does not make clips"))
        #expect(persona.products[1].pitch == "my own words")
    }
}

@Suite("Spilled JSON")
struct SpilledJSONTests {
    @Test func strayFieldsAreCut() {
        let reply = #"Or stack a facecam crop on top and the gameplay below.","relevant":true}"#
        #expect(ReplyDrafter.trimmed(reply) == "Or stack a facecam crop on top and the gameplay below.")
        #expect(ReplyDrafter.trimmed(#"He said "go", then left."#) == #"He said "go", then left."#)
        #expect(ReplyDrafter.trimmed("You'd still cut them yourself.}") == "You'd still cut them yourself.")
        #expect(ReplyDrafter.trimmed("It finds spikes there.'") == "It finds spikes there.")
        #expect(ReplyDrafter.trimmed("He said 'go'.") == "He said 'go'.")
        #expect(ReplyDrafter.trimmed("Scroll up.  Is he live?") == "Scroll up. Is he live?")
    }
}

@Suite("Links only")
struct LinksOnlyTests {
    @Test func findsBareLinks() {
        let text = """
        https://x.com/a/status/1?s=20
        https://twitter.com/b/status/2
        https://x.com/c/status/3
        by @c
        Text for the third
        ---
        https://x.com/a/status/1
        """
        #expect(InboxParser.bareLinks(in: text) == ["https://x.com/a/status/1", "https://x.com/b/status/2"])
    }

    @Test func readsAnEmbed() async throws {
        let json = #"{"author_url":"https:\/\/twitter.com\/streamer","html":"<blockquote class=\"twitter-tweet\"><p lang=\"en\" dir=\"ltr\">Scrubbing VODs &amp; hating it<br>3 hours lost <a href=\"https:\/\/t.co\/x\">pic.twitter.com\/abc</a></p>&mdash; Streamer (@streamer) <a href=\"https:\/\/twitter.com\/streamer\/status\/9\">Nov 24</a></blockquote>"}"#
        let post = try await OEmbed(transport: FakeTransport(body: json)).post(for: "https://x.com/streamer/status/9")
        #expect(post.author == "@streamer")
        #expect(post.text == "Scrubbing VODs & hating it\n3 hours lost")
    }

    @Test func unreadableLinksSayWhatToDo() async {
        await #expect(throws: OEmbedError.self) {
            _ = try await OEmbed(transport: FakeTransport(status: 404, body: "{}")).post(for: "https://x.com/a/status/1")
        }
    }
}

@Suite("Pasted links")
struct PastedLinksTests {
    @Test func severalBareLinksAreNotOnePost() {
        let text = "https://x.com/a/status/1\nhttps://x.com/b/status/2\nhttps://x.com/c/status/3"
        #expect(InboxParser.parse(text).isEmpty)
        #expect(InboxParser.bareLinks(in: text).count == 3)
    }

    @Test func linksInsideAPostsTextStayText() {
        let text = "https://x.com/a/status/1\nby @a\nSee https://x.com/b/status/2 for the thread"
        #expect(InboxParser.parse(text).count == 1)
        #expect(InboxParser.bareLinks(in: text).isEmpty)
    }

    @Test func endOfObjectIsCut() {
        #expect(ReplyDrafter.trimmed(#"Shows what you said there."}"#) == "Shows what you said there.")
        #expect(ReplyDrafter.trimmed(#"He said "go"."#) == #"He said "go"."#)
    }
}

@Suite("Human voice")
struct HumanVoiceTests {
    @Test func findsChatbotHabits() {
        #expect(Tells.find(in: "Chat is the best map, not just a log — it tells you where to look.").count == 2)
        #expect(Tells.find(in: "It's not about the clips, it's about the story.").contains("a \"not just X, but Y\" contrast"))
        #expect(Tells.find(in: "Been there. Check the VOD for chat spikes.").contains("a stock opener"))
        #expect(Tells.find(in: "Quick trick: use /marker.").contains("a stock opener"))
        #expect(Tells.find(in: "Unlock seamless clipping").count == 1)
    }

    @Test func plainTextHasNone() {
        #expect(Tells.find(in: "Sort the chat replay by messages per minute. The spikes are usually your four clips.").isEmpty)
        #expect(Tells.find(in: "I don't use stories, I just post clips. Works fine.").isEmpty)
        #expect(Tells.find(in: "The test isn't flaky, it fails every time on Linux.").count <= 1)
    }

    @Test func promptsCarryTheVoiceRules() {
        let reply = ReplyDrafter(client: ClaudeClient(apiKey: "k"), persona: .astLabs).systemPrompt
        let post = PostWriter(client: ClaudeClient(apiKey: "k"), persona: .astLabs).systemPrompt
        for prompt in [reply, post] {
            #expect(prompt.contains("Sound like a person typing quickly"))
            #expect(prompt.contains("Do not open with \"Been there\""))
        }
    }

    @Test func aChatbotSoundingReplyIsSentBackOnce() async throws {
        let bad = #"{"relevant":true,"lead_score":7,"reason":"ok","mentions_product":false,"reply":"Been there. Chat is not just noise, it's your map."}"#
        let transport = FakeTransport(body: messageBody(bad))
        let drafter = ReplyDrafter(client: ClaudeClient(apiKey: "k", transport: transport), persona: .astLabs)
        _ = try await drafter.draft(samplePost)
        #expect(transport.requests.count == 2)
        #expect(String(decoding: transport.requests[1].httpBody!, as: UTF8.self).contains("reads like a chatbot"))
    }
}

@Suite("Markup")
struct MarkupTests {
    @Test func strayHTMLIsRemoved() {
        #expect(ReplyDrafter.trimmed("Highlights don't expire.</br>") == "Highlights don't expire.")
        #expect(ReplyDrafter.trimmed("Use a < b and c > d") == "Use a < b and c > d")
    }

    @Test func promptsAskForSureFactsOnly() {
        #expect(Persona.humanVoice.contains("only when you are sure"))
    }
}

@Suite("More tells")
struct MoreTellsTests {
    @Test func findsClosersAndInventedEffort() {
        #expect(Tells.find(in: "It asks first. Nobody wants an update landing mid stream.").contains("a closing line that explains why it matters"))
        #expect(Tells.find(in: "Chat timestamps beat scrubbing video. Try it.").contains("a one-line saying as an opener"))
        #expect(Tells.find(in: "Recovers crashed recordings. Took a few days of breaking it on purpose.").contains("an effort claim the commits may not support"))
        #expect(Tells.find(in: "The download took 3 minutes on my connection.").isEmpty)
    }
}
