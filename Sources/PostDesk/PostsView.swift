import PostDeskKit
import SwiftUI

struct PostsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.visiblePosts.isEmpty {
                ContentUnavailableView {
                    Label("No Post Drafts", systemImage: "square.and.pencil")
                } description: {
                    Text(!model.hasKey
                         ? "Add your Anthropic API key in Settings > Keys first."
                         : model.persona.repoPaths.isEmpty
                         ? "Add your git repositories in Settings > Sources. PostDesk writes the week's posts from your real commits."
                         : "Draft this week's posts from your recent commits.")
                } actions: {
                    if model.persona.repoPaths.isEmpty || !model.hasKey {
                        SettingsLink { Text("Open Settings…") }
                    } else {
                        Button("Draft This Week's Posts") { model.draftWeek() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy)
                    }
                }
            } else {
                List(selection: $model.selectedPost) {
                    ForEach(model.visiblePosts) { draft in
                        PostRow(model: model, draft: draft)
                            .tag(draft.id)
                    }
                }
            }
        }
        .navigationTitle("Posts")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                Button("Draft This Week's Posts", systemImage: "sparkles") { model.draftWeek() }
                    .help("Write this week's posts from your recent commits (Command-Shift-D)")
                    .disabled(model.isBusy)
            }
        }
    }

    private var subtitle: String {
        let open = model.state.posts.filter { $0.status == .open }
        let ready = open.filter(\.isReady).count
        return open.isEmpty ? "Written from your commits" : "\(ready) of \(open.count) ready to post"
    }
}

struct PostRow: View {
    let model: AppModel
    let draft: PostDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                if draft.isReady {
                    Label("Ready", systemImage: "checkmark.seal").foregroundStyle(Palette.accentText)
                } else {
                    Label("Needs you", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                Text(draft.basedOn).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                StatusBadge(status: draft.status)
            }
            DraftEditor(text: Binding(get: { draft.text }, set: { model.setPostText(draft.id, $0) }), minHeight: 96)
            ForEach(draft.problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            HStack(spacing: Space.sm) {
                Text("\(PostSafety.weightedLength(draft.text))/\(PostSafety.maxLength)")
                    .monospacedDigit()
                    .foregroundStyle(PostSafety.weightedLength(draft.text) > PostSafety.maxLength ? Color.red : .secondary)
                Toggle("Needs media", isOn: Binding(get: { draft.needsMedia }, set: { model.setPostNeedsMedia(draft.id, $0) }))
                    .toggleStyle(.checkbox)
                    .help("Turn off once you've attached the clip or screenshot on X.")
                Spacer()
                if draft.status == .open {
                    Button("Dismiss") { model.setPostStatus(draft.id, .dismissed) }
                    Button("Mark Posted") { model.setPostStatus(draft.id, .posted) }
                } else {
                    Button("Restore") { model.setPostStatus(draft.id, .open) }
                }
                Button("Rewrite", systemImage: "arrow.clockwise") { model.rewritePost(draft.id) }
                    .help("Ask Claude for a new version with the same facts (Command-Shift-R)")
                    .disabled(model.isBusy)
                Button("Copy") { model.copy(draft.text) }
                Button("Post on X") { model.sendPostToX(draft.id) }
                    .buttonStyle(.borderedProminent)
                    .help("Opens X's composer with this text and files the draft as posted. You attach media and press Post. Restore brings it back.")
            }
            .font(.callout)
        }
        .padding(.vertical, Space.sm)
    }
}
