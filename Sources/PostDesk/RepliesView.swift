import PostDeskKit
import SwiftUI

struct RepliesView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.visibleReplies.isEmpty && model.state.skipped.isEmpty {
                ContentUnavailableView {
                    Label(model.hasKey ? "No Reply Drafts" : "Add Your Claude Key", systemImage: model.hasKey ? "bubble.left.and.bubble.right" : "key")
                } description: {
                    Text(!model.hasKey
                         ? "PostDesk needs your Anthropic API key to write drafts. It's kept in your Mac's keychain."
                         : model.state.inbox.isEmpty
                         ? "Copy a post's link from X (Share > Copy link), then press Command-Shift-V. Claude drafts a reply, and you post it yourself."
                         : "\(model.state.inbox.count) posts are waiting in the inbox.")
                } actions: {
                    if !model.hasKey {
                        SettingsLink { Text("Open Settings…") }
                    }
                    Button("Paste Link and Draft") { model.pasteFromClipboard() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy || !model.hasKey)
                    Button("Paste Posts…") { model.showsPasteSheet = true }
                    if !model.state.inbox.isEmpty {
                        Button("Draft Replies") { model.draftReplies() }
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
                Button("Paste and Draft", systemImage: "doc.on.clipboard") { model.pasteFromClipboard() }
                    .help("Draft a reply to the post link or posts on your clipboard (Command-Shift-V)")
                    .disabled(model.isBusy)
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
            DraftEditor(text: Binding(get: { draft.reply }, set: { model.setReplyText(draft.id, $0) }), minHeight: 72)
            HStack(spacing: Space.sm) {
                Text("\(draft.reply.count)/\(ReplyDrafter.maxReplyLength)")
                    .monospacedDigit()
                    .foregroundStyle(draft.reply.count > ReplyDrafter.maxReplyLength ? Color.red : .secondary)
                Text(draft.reason).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if draft.status == .open {
                    Button("Dismiss") { model.setReplyStatus(draft.id, .dismissed) }
                    Button("Mark Posted") { model.setReplyStatus(draft.id, .posted) }
                        .help("For when you posted it another way")
                } else {
                    Button("Restore") { model.setReplyStatus(draft.id, .open) }
                }
                Button("Redraft", systemImage: "arrow.clockwise") { model.redraftReply(draft.id) }
                    .help("Ask Claude for a different reply (Command-Shift-R)")
                    .disabled(model.isBusy)
                Button("Copy") { model.copy(draft.reply) }
                Button("Reply on X") { model.sendReplyToX(draft.id) }
                    .primaryWhen(model.selectedReply == draft.id)
                    .help("Opens X's reply box with this text and files the draft as posted. You press Post. Restore brings it back.")
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

/// A text box that shows the whole draft. TextField in a List row stays one line high.
struct DraftEditor: View {
    @Binding var text: String
    var minHeight: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(Space.xs)
            .frame(minHeight: minHeight)
            .background(.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator, lineWidth: 1))
    }
}

extension View {
    /// The blue button on the selected card only, so a list of cards has one primary action.
    @ViewBuilder
    func primaryWhen(_ selected: Bool) -> some View {
        if selected { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
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
