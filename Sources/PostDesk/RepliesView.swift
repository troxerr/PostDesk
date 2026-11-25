import PostDeskKit
import SwiftUI

struct RepliesView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.visibleReplies.isEmpty && model.state.skipped.isEmpty {
                ContentUnavailableView {
                    Label("No Reply Drafts", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text(model.state.inbox.isEmpty
                         ? "Paste posts from X, or fetch them with your X API token. Claude drafts replies, and you post the ones you like yourself."
                         : "\(model.state.inbox.count) posts are waiting in the inbox.")
                } actions: {
                    Button("Paste Posts…") { model.showsPasteSheet = true }
                    if !model.state.inbox.isEmpty {
                        Button("Draft Replies") { model.draftReplies() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy)
                    }
                }
            } else {
                List(selection: $model.selectedReply) {
                    Section {
                        ForEach(model.visibleReplies) { draft in
                            ReplyRow(model: model, draft: draft)
                                .tag(draft.id)
                        }
                    } footer: {
                        if model.visibleReplies.isEmpty {
                            Text("No drafts to post. Paste more posts, or draft one of the skipped posts below.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !model.state.skipped.isEmpty {
                        Section {
                            DisclosureGroup("Skipped (\(model.state.skipped.count))") {
                                ForEach(model.recentSkipped) { skipped in
                                    SkippedRow(model: model, skipped: skipped)
                                }
                                Button("Forget Skipped Posts") { model.forgetSkipped() }
                                    .buttonStyle(.link)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Replies")
        .navigationSubtitle(model.state.inbox.isEmpty ? "Nothing is posted for you" : "\(model.state.inbox.count) in the inbox")
        .toolbar {
            ToolbarItemGroup {
                Button("Paste Posts", systemImage: "doc.on.clipboard") { model.showsPasteSheet = true }
                    .help("Paste posts copied from X (Command-Shift-V)")
                Button("Fetch from X", systemImage: "arrow.down.circle") { model.fetchFromX() }
                    .help("Search X with the official API (Command-Shift-F)")
                    .disabled(model.isBusy)
                Button("Draft Replies", systemImage: "sparkles") { model.draftReplies() }
                    .help("Draft replies to the posts in the inbox (Command-R)")
                    .disabled(model.isBusy || model.state.inbox.isEmpty)
            }
        }
    }
}

struct ReplyRow: View {
    let model: AppModel
    let draft: ReplyDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Text(draft.post.author.isEmpty ? "Post" : draft.post.author).font(.headline)
                Text("Lead \(draft.leadScore)/10").foregroundStyle(.secondary)
                if draft.mentionsProduct {
                    Label("Mentions a product", systemImage: "tag").foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(status: draft.status)
            }
            Text(draft.post.text)
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .textSelection(.enabled)
            TextField("Reply", text: Binding(get: { draft.reply }, set: { model.setReplyText(draft.id, $0) }), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
            HStack(spacing: Space.sm) {
                Text("\(draft.reply.count)/\(ReplyDrafter.maxReplyLength)")
                    .monospacedDigit()
                    .foregroundStyle(draft.reply.count > ReplyDrafter.maxReplyLength ? Color.red : .secondary)
                Text(draft.reason).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if draft.status == .open {
                    Button("Dismiss") { model.setReplyStatus(draft.id, .dismissed) }
                    Button("Mark Posted") { model.setReplyStatus(draft.id, .posted) }
                } else {
                    Button("Restore") { model.setReplyStatus(draft.id, .open) }
                }
                Button("Redraft", systemImage: "arrow.clockwise") { model.redraftReply(draft.id) }
                    .help("Ask Claude for a different reply (Command-Shift-R)")
                    .disabled(model.isBusy)
                Button("Copy") { model.copy(draft.reply) }
                Button("Reply on X") { model.open(draft.replyLink ?? URL(string: draft.post.url)) }
                    .buttonStyle(.borderedProminent)
                    .help("Opens X's reply box with this text. You press Post.")
            }
            .font(.callout)
        }
        .padding(.vertical, Space.sm)
    }
}

/// A post Claude passed on, with why, and a way to answer it anyway.
struct SkippedRow: View {
    let model: AppModel
    let skipped: SkippedPost

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(skipped.post.author.isEmpty ? "Post" : skipped.post.author).font(.callout.weight(.medium))
                Text(skipped.post.text).foregroundStyle(.secondary).lineLimit(2)
                Text(skipped.reason).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") { model.open(URL(string: skipped.post.url)) }
            Button("Draft Anyway") { model.draftAnyway(skipped) }
                .disabled(model.isBusy)
        }
        .font(.callout)
        .padding(.vertical, Space.xs)
    }
}

struct StatusBadge: View {
    let status: DraftStatus

    var body: some View {
        switch status {
        case .open: EmptyView()
        case .posted: Label("Posted", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case .dismissed: Label("Dismissed", systemImage: "xmark.circle").foregroundStyle(.secondary)
        }
    }
}
