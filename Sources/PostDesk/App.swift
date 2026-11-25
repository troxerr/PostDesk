import AppKit
import SwiftUI

// PostDesk
//   PostDesk                    the app
//   APP_STORE=<file> PostDesk   use another desk file (tests, experiments)

@main
struct PostDeskApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("PostDesk", id: "main") {
            ContentView(model: model)
                .themed()
                .noInitialFocus()
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 1040, height: 720)
        .windowToolbarStyle(.unified)
        .commands { DeskCommands(model: model) }

        Settings {
            SettingsView(model: model)
                .themed()
                .noInitialFocus()
        }
    }
}

struct DeskCommands: Commands {
    let model: AppModel

    var body: some Commands {
        SidebarCommands()
        CommandGroup(replacing: .newItem) {
            Button("Paste Posts…") { model.showsPasteSheet = true }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Fetch Posts from X") { model.fetchFromX() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(model.isBusy)
        }
        CommandGroup(before: .sidebar) {
            ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, page in
                Button(page.title) { model.page = page }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
            Toggle("Show Posted and Dismissed", isOn: Binding(get: { model.showsDone }, set: { model.showsDone = $0 }))
                .keyboardShortcut("d", modifiers: [.command, .option])
            Divider()
        }
        CommandMenu("Desk") {
            Button("Draft Replies") { model.draftReplies() }
                .keyboardShortcut("r")
                .disabled(model.isBusy)
            Button("Draft This Week's Posts") { model.draftWeek() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(model.isBusy)
            Button("Stop") { model.cancel() }
                .keyboardShortcut(".")
                .disabled(!model.isBusy)
            Divider()
            Button("Open on X") { model.openSelectedOnX() }
                .keyboardShortcut("o")
                .disabled(!model.hasSelection)
            Button("Copy Draft") { model.copySelected() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!model.hasSelection)
            Button("Mark as Posted") { model.markSelected(.posted) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.hasSelection)
            Button("Dismiss") { model.markSelected(.dismissed) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!model.hasSelection)
            Button("Restore") { model.markSelected(.open) }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(!model.hasSelection)
        }
    }
}
