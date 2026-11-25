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

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Paste Posts").font(.headline)
            Text("Put each post's link on its own line, then an optional \"by @handle\" line, then the text. Separate posts with a line of ---.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.body.monospaced())
                .focused($focused)
                .frame(minHeight: 240)
            HStack {
                Text("\(InboxParser.parse(text).count) posts").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add to Inbox") {
                    model.paste(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(InboxParser.parse(text).isEmpty)
            }
        }
        .padding(Space.margin)
        .frame(width: 560)
        .onAppear {
            focused = true
            // Posts already copied from X fill the sheet, ready to add.
            if let copied = NSPasteboard.general.string(forType: .string), !InboxParser.parse(copied).isEmpty {
                text = copied
            }
        }
    }
}
