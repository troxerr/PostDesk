import AppKit
import PostDeskKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case account, sources, keys
    var id: String { rawValue }
}

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            AccountSettings(persona: $model.persona)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(SettingsTab.account)
            SourceSettings(persona: $model.persona)
                .tabItem { Label("Sources", systemImage: "folder") }
                .tag(SettingsTab.sources)
            KeySettings(persona: $model.persona)
                .tabItem { Label("Keys", systemImage: "key") }
                .tag(SettingsTab.keys)
        }
        .frame(width: 560)
    }
}

/// Who the drafts speak for.
struct AccountSettings: View {
    @Binding var persona: Persona

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $persona.name)
                TextField("Handle", text: $persona.handle)
                TextField("About you", text: $persona.bio, axis: .vertical)
                    .lineLimit(2...4)
            } footer: {
                Text("Claude writes as you, in the first person.").foregroundStyle(.secondary)
            }
            Section("Products") {
                ForEach($persona.products) { $product in
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            TextField("Name", text: $product.name)
                            TextField("What it does, who it's for, the price", text: $product.pitch, axis: .vertical)
                                .lineLimit(1...4)
                        }
                        Button("Remove", systemImage: "minus.circle") {
                            persona.products.removeAll { $0.id == product.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add Product") { persona.products.append(Product(name: "", pitch: "")) }
            }
        }
        .formStyle(.grouped)
        .fitsContent()
    }
}

/// Where facts and posts come from.
struct SourceSettings: View {
    @Binding var persona: Persona

    var body: some View {
        Form {
            Section {
                ForEach(persona.repoPaths, id: \.self) { path in
                    HStack {
                        Label((path as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { persona.repoPaths.removeAll { $0 == path } }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add Repository…") { addRepository() }
            } header: {
                Text("Repositories")
            } footer: {
                Text("The week's posts are written from the last 7 days of commits in these folders.").foregroundStyle(.secondary)
            }
            Section {
                TextField("Keywords", text: list($persona.keywords, separator: ", "), axis: .vertical)
                    .lineLimit(1...3)
            } header: {
                Text("Keywords")
            } footer: {
                Text("Separated by commas. Only posts with one of these words are sent to Claude. Leave empty to read every post.")
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("Searches", text: list($persona.searchQueries, separator: "\n"), axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("X searches")
            } footer: {
                Text("One per line. Used by Fetch from X, through the official X API with your bearer token.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fitsContent()
    }

    private func addRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !persona.repoPaths.contains(url.path) {
            persona.repoPaths.append(url.path)
        }
    }

    /// Edits a list of strings as one block of text.
    private func list(_ values: Binding<[String]>, separator: String) -> Binding<String> {
        Binding {
            values.wrappedValue.joined(separator: separator)
        } set: { text in
            let parts = separator == "\n" ? text.components(separatedBy: .newlines) : text.components(separatedBy: ",")
            values.wrappedValue = parts.map { $0.trimmingCharacters(in: .whitespaces) }
                .enumerated()
                // Keep a trailing empty item while typing, so the separator isn't eaten.
                .filter { !$0.element.isEmpty || $0.offset == parts.count - 1 }
                .map(\.element)
        }
    }
}

/// API keys, kept in the keychain.
struct KeySettings: View {
    @Binding var persona: Persona
    @State private var anthropic = Keychain.read(Keychain.anthropic)
    @State private var bearer = Keychain.read(Keychain.xBearer)

    var body: some View {
        Form {
            Section {
                SecureField("Anthropic API key", text: $anthropic)
                    .onChange(of: anthropic) { _, value in Keychain.write(value, account: Keychain.anthropic) }
                TextField("Model", text: $persona.model, prompt: Text(ClaudeClient.defaultModel))
                Stepper("Up to \(persona.dailyMax) replies per run", value: $persona.dailyMax, in: 1...50)
            } header: {
                Text("Claude")
            } footer: {
                Text("Each reply costs about a cent or two. Get a key at console.anthropic.com.").foregroundStyle(.secondary)
            }
            Section {
                SecureField("X API bearer token", text: $bearer)
                    .onChange(of: bearer) { _, value in Keychain.write(value, account: Keychain.xBearer) }
            } header: {
                Text("X (optional)")
            } footer: {
                Text("Only for Fetch from X, which needs a paid X API plan. Pasting posts works without it. PostDesk never posts, likes, follows, or sends messages for you.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fitsContent()
    }
}
