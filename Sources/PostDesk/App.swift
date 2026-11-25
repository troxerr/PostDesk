import AppKit
import SwiftUI

// PostDesk
//   PostDesk                    the app
//   APP_STORE=<file> PostDesk   use another desk file (tests, experiments)
//   APP_STORE=/tmp/x.json PostDesk --selftest   draft real replies and posts with your key, print them, quit (SelfTest.swift)

@main
enum Launcher {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            Task { exit(await SelfTest.run()) }
            dispatchMain()
        } else {
            PostDeskApp.main()
        }
    }
}

struct PostDeskApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("PostDesk", id: "main") {
            ContentView(model: model)
                .themed()
                .noInitialFocus()
                .frame(minWidth: 760, minHeight: 520)
                .onAppear { Reminder.shared.schedule() }
        }
        .defaultSize(width: 1040, height: 720)
        .windowToolbarStyle(.unified)
        .commands { DeskCommands(model: model) }

        Settings {
            SettingsView(model: model)
                .themed()
                .noInitialFocus()
        }

        // A menu bar icon: draft from anywhere without opening the window first.
        MenuBarExtra("PostDesk", systemImage: "text.bubble") {
            MenuBarContent(model: model)
        }
    }
}

struct MenuBarContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Draft a Reply from the Clipboard") {
            model.page = .replies
            model.pasteFromClipboard()
            show()
        }
        .disabled(model.isBusy)
        Button("Draft This Week's Posts") {
            model.draftWeek()
            show()
        }
        .disabled(model.isBusy)
        Divider()
        Text("\(model.openReplyCount) replies and \(model.openPostCount) posts to go")
        Button("Open PostDesk") { show() }
        Divider()
        Button("Quit PostDesk") { NSApplication.shared.terminate(nil) }
    }

    private func show() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct DeskCommands: Commands {
    let model: AppModel

    var body: some Commands {
        SidebarCommands()
        CommandGroup(replacing: .newItem) {
            Button("Paste and Draft") { model.pasteFromClipboard() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(model.isBusy)
            Button("Paste Posts…") { model.showsPasteSheet = true }
                .keyboardShortcut("v", modifiers: [.command, .option])
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
            Button("Redraft") { model.redraftSelected() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!model.hasSelection || model.isBusy)
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
