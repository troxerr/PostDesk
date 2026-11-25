import AppKit
import PostDeskKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.page) {
                Section("Desk") {
                    ForEach(Page.allCases) { page in
                        Label(page.title, systemImage: page.symbol)
                            .badge(page == .replies ? model.openReplyCount : model.openPostCount)
                            .tag(page)
                    }
                }
                if !model.state.inbox.isEmpty {
                    Section("Inbox") {
                        Label("\(model.state.inbox.count) waiting", systemImage: "tray")
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch model.page {
            case .posts: PostsView(model: model)
            default: RepliesView(model: model)
            }
        }
        .toolbar {
            if let progress = model.progress {
                ToolbarItem(placement: .status) {
                    HStack(spacing: Space.sm) {
                        ProgressView().controlSize(.small)
                        Text(progress).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $model.showsPasteSheet) {
            PasteSheet(model: model)
        }
        // Drop a link or selected text from the browser onto the window.
        .dropDestination(for: String.self) { items, _ in
            model.addPosts(from: items.joined(separator: "\n---\n"), draft: true)
            return true
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addPosts(from: urls.map(\.absoluteString).joined(separator: "\n"), draft: true)
            return true
        }
        .alert("PostDesk", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// Where you paste posts copied from X. Its only job is typing, so the field takes focus.
struct PasteSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var count: Int { InboxParser.parse(text).count + InboxParser.bareLinks(in: text).count }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Paste Posts").font(.headline)
            Text("Paste post links, one per line, and PostDesk reads them from X. Or paste a link with the post's text under it, and a line of --- between posts.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.body.monospaced())
                .focused($focused)
                .frame(minHeight: 240)
            HStack {
                Text(count == 1 ? "1 post" : "\(count) posts").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add to Inbox") {
                    model.addPosts(from: text, draft: false)
                    dismiss()
                }
                .disabled(count == 0)
                Button("Add and Draft") {
                    model.addPosts(from: text, draft: true)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(count == 0)
            }
        }
        .padding(Space.margin)
        .frame(width: 560)
        .onAppear {
            focused = true
            // Posts already copied from X fill the sheet, ready to add.
            if let copied = NSPasteboard.general.string(forType: .string),
               !InboxParser.parse(copied).isEmpty || !InboxParser.bareLinks(in: copied).isEmpty {
                text = copied
            }
        }
    }
}
