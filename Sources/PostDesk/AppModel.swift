import AppKit
import Observation
import PostDeskKit

enum Page: String, CaseIterable, Identifiable {
    case replies, posts
    var id: String { rawValue }

    var title: String {
        switch self {
        case .replies: "Replies"
        case .posts: "Posts"
        }
    }

    var symbol: String {
        switch self {
        case .replies: "bubble.left.and.bubble.right"
        case .posts: "square.and.pencil"
        }
    }
}

/// The app's state and every action the menus and buttons call.
@Observable
final class AppModel {
    var state: DeskState
    var persona: Persona {
        didSet { savePersona() }
    }
    var page: Page? = .replies
    var selectedReply: ReplyDraft.ID?
    var selectedPost: PostDraft.ID?
    var showsDone = false
    var showsPasteSheet = false
    /// What is running now, shown in the toolbar. Nil when idle.
    var progress: String?
    var errorMessage: String?

    private let store: DeskStore
    private var work: Task<Void, Never>?
    private static let personaKey = "persona"

    init() {
        store = DeskStore(url: Self.storeURL())
        state = store.load()
        persona = Self.loadPersona()
    }

    /// The saved settings from Settings > Account, Writing and Sources.
    static func loadPersona() -> Persona {
        guard let data = UserDefaults.standard.data(forKey: personaKey),
              let saved = try? JSONDecoder().decode(Persona.self, from: data) else { return .astLabs }
        return saved
    }

    /// ~/Library/Application Support/PostDesk/desk.json, or APP_STORE for tests.
    static func storeURL() -> URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"] { return URL(fileURLWithPath: path) }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("PostDesk/desk.json")
    }

    var isBusy: Bool { progress != nil }

    // MARK: - Lists

    var visibleReplies: [ReplyDraft] {
        state.replies
            .filter { showsDone || $0.status == .open }
            .sorted { ($0.leadScore, $0.createdAt) > ($1.leadScore, $1.createdAt) }
    }

    var visiblePosts: [PostDraft] {
        state.posts
            .filter { showsDone || $0.status == .open }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var openReplyCount: Int { state.replies.filter { $0.status == .open }.count }
    var openPostCount: Int { state.posts.filter { $0.status == .open }.count }

    // MARK: - Inbox

    /// Adds pasted posts to the inbox. Returns how many were new.
    @discardableResult
    func paste(_ text: String) -> Int {
        let added = state.addToInbox(InboxParser.parse(text))
        save()
        return added
    }

    func fetchFromX() {
        let bearer = Keychain.read(Keychain.xBearer)
        guard !bearer.isEmpty else {
            errorMessage = "Add an X API bearer token in Settings > Keys to fetch posts, or paste posts instead."
            return
        }
        let queries = persona.searchQueries.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !queries.isEmpty else {
            errorMessage = "Add a search in Settings > Sources first."
            return
        }
        run("Searching X…") { model in
            let search = XSearch(bearer: bearer)
            var found: [SourcePost] = []
            for query in queries {
                found += try await search.recent(query)
            }
            let added = model.state.addToInbox(found)
            model.save()
            if added == 0 { model.errorMessage = "X returned no new posts for your searches." }
        }
    }

    // MARK: - Replies

    func draftReplies() {
        guard !state.inbox.isEmpty else {
            errorMessage = "The inbox is empty. Paste posts from X first (Command-Shift-V)."
            return
        }
        let drafter = makeDrafter()
        let limit = max(persona.dailyMax, 1)
        run("Drafting replies…") { model in
            var drafted = 0
            while let post = model.state.inbox.first, drafted < limit {
                try Task.checkCancellation()
                if ReplyDrafter.keywordMatch(post, keywords: model.persona.keywords) {
                    model.progress = "Drafting reply \(drafted + 1) of \(min(limit, model.state.inbox.count + drafted))…"
                    switch try await drafter.draft(post) {
                    case .draft(let draft): model.state.replies.append(draft)
                    case .skipped(let skipped): model.state.skipped.append(skipped)
                    }
                    drafted += 1
                } else {
                    model.state.skipped.append(SkippedPost(post: post, reason: "None of your keywords are in it."))
                }
                model.state.inbox.removeFirst()
                model.state.seen.insert(post.url)
                model.save()
            }
            model.page = .replies
        }
    }

    /// Asks Claude for a different reply to the same post.
    func redraftReply(_ id: ReplyDraft.ID) {
        guard let old = reply(id) else { return }
        let drafter = makeDrafter()
        run("Redrafting the reply…") { model in
            let outcome = try await drafter.draft(old.post, note: ReplyDrafter.redraftNote(replacing: old.reply))
            guard case .draft(let new) = outcome, let index = model.state.replies.firstIndex(where: { $0.id == id }) else {
                model.errorMessage = "Claude didn't write another reply for this post."
                return
            }
            model.state.replies[index].reply = new.reply
            model.state.replies[index].reason = new.reason
            model.state.replies[index].mentionsProduct = new.mentionsProduct
            model.save()
        }
    }

    /// Drafts a reply to a post Claude skipped, because you want to answer it anyway.
    func draftAnyway(_ skipped: SkippedPost) {
        let drafter = makeDrafter()
        run("Drafting a reply…") { model in
            let outcome = try await drafter.draft(skipped.post, note: ReplyDrafter.insistNote)
            guard case .draft(let draft) = outcome else {
                model.errorMessage = "Claude still didn't write a reply for this post. You can copy it and answer by hand."
                return
            }
            model.state.skipped.removeAll { $0.id == skipped.id }
            model.state.replies.append(draft)
            model.selectedReply = draft.id
            model.save()
        }
    }

    func forgetSkipped() {
        state.skipped.removeAll()
        save()
    }

    var recentSkipped: [SkippedPost] { Array(state.skipped.suffix(30).reversed()) }

    private func makeDrafter() -> ReplyDrafter {
        ReplyDrafter(client: ClaudeClient(apiKey: Keychain.read(Keychain.anthropic), model: persona.model), persona: persona)
    }

    private func makeWriter() -> PostWriter {
        PostWriter(client: ClaudeClient(apiKey: Keychain.read(Keychain.anthropic), model: persona.model), persona: persona)
    }

    func reply(_ id: ReplyDraft.ID) -> ReplyDraft? {
        state.replies.first { $0.id == id }
    }

    func setReplyText(_ id: ReplyDraft.ID, _ text: String) {
        guard let index = state.replies.firstIndex(where: { $0.id == id }) else { return }
        state.replies[index].reply = text
        save()
    }

    func setReplyStatus(_ id: ReplyDraft.ID, _ status: DraftStatus) {
        guard let index = state.replies.firstIndex(where: { $0.id == id }) else { return }
        state.replies[index].status = status
        save()
    }

    // MARK: - Posts

    func draftWeek() {
        let paths = persona.repoPaths
        let days = max(persona.commitDays, 1)
        guard !paths.isEmpty else {
            errorMessage = "Add the folders of your git repositories in Settings > Sources, so posts come from real commits."
            return
        }
        let writer = makeWriter()
        run("Reading this week's commits…") { model in
            var commits: [Commit] = []
            for path in paths {
                commits += try await GitLog.recentCommits(in: path, days: days)
            }
            guard !commits.isEmpty else {
                model.errorMessage = "There are no commits from the last \(days) days in your repositories."
                return
            }
            model.progress = "Writing posts from \(commits.count) commits…"
            let drafts = try await writer.write(commits: commits)
            if drafts.isEmpty { model.errorMessage = "Claude didn't write any posts. Try again." }
            model.state.posts += drafts
            model.save()
            model.page = .posts
        }
    }

    /// Asks Claude for a new version of a post with the same facts.
    func rewritePost(_ id: PostDraft.ID) {
        guard let old = post(id) else { return }
        let writer = makeWriter()
        run("Rewriting the post…") { model in
            guard let new = try await writer.rewrite(old), let index = model.state.posts.firstIndex(where: { $0.id == id }) else {
                model.errorMessage = "Claude didn't write a new version of this post."
                return
            }
            model.state.posts[index].text = new.text
            model.state.posts[index].needsMedia = new.needsMedia
            model.save()
        }
    }

    func post(_ id: PostDraft.ID) -> PostDraft? {
        state.posts.first { $0.id == id }
    }

    func setPostText(_ id: PostDraft.ID, _ text: String) {
        guard let index = state.posts.firstIndex(where: { $0.id == id }) else { return }
        state.posts[index].text = text
        save()
    }

    func setPostNeedsMedia(_ id: PostDraft.ID, _ needsMedia: Bool) {
        guard let index = state.posts.firstIndex(where: { $0.id == id }) else { return }
        state.posts[index].needsMedia = needsMedia
        save()
    }

    func setPostStatus(_ id: PostDraft.ID, _ status: DraftStatus) {
        guard let index = state.posts.firstIndex(where: { $0.id == id }) else { return }
        state.posts[index].status = status
        save()
    }

    // MARK: - Selection (menu bar actions)

    var hasSelection: Bool {
        switch page {
        case .replies: selectedReply.flatMap(reply) != nil
        case .posts: selectedPost.flatMap(post) != nil
        case nil: false
        }
    }

    func openSelectedOnX() {
        switch page {
        case .replies: if let draft = selectedReply.flatMap(reply) { open(draft.replyLink ?? URL(string: draft.post.url)) }
        case .posts: if let draft = selectedPost.flatMap(post) { open(draft.composeLink) }
        case nil: break
        }
    }

    func copySelected() {
        switch page {
        case .replies: if let draft = selectedReply.flatMap(reply) { copy(draft.reply) }
        case .posts: if let draft = selectedPost.flatMap(post) { copy(draft.text) }
        case nil: break
        }
    }

    func redraftSelected() {
        switch page {
        case .replies: if let id = selectedReply { redraftReply(id) }
        case .posts: if let id = selectedPost { rewritePost(id) }
        case nil: break
        }
    }

    func markSelected(_ status: DraftStatus) {
        switch page {
        case .replies: if let id = selectedReply { setReplyStatus(id, status) }
        case .posts: if let id = selectedPost { setPostStatus(id, status) }
        case nil: break
        }
    }

    // MARK: - Helpers

    func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func cancel() {
        work?.cancel()
    }

    private func run(_ label: String, _ body: @escaping @MainActor (AppModel) async throws -> Void) {
        guard work == nil else { return }
        progress = label
        work = Task {
            do {
                try await body(self)
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                errorMessage = error.localizedDescription
            }
            progress = nil
            work = nil
        }
    }

    func save() {
        do {
            try store.save(state)
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func savePersona() {
        if let data = try? JSONEncoder().encode(persona) {
            UserDefaults.standard.set(data, forKey: Self.personaKey)
        }
    }
}
