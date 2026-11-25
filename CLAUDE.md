# PostDesk

PostDesk: a native macOS 14+ app in SwiftUI for growing an X account (@AST_Labs) without ban risk.
It drafts replies to posts you give it and writes the week's original posts from your real
commits. You review every draft and post it yourself through X's own composer. It runs on this
Mac only, with one local JSON file and no server.

## What it must never do

No code that posts, likes, follows, quote-posts, sends DMs, or scripts the X website or a browser.
X suspends accounts for those ([automation rules](https://help.x.com/en/rules-and-policies/x-automation)).
Drafts leave the app only as an `x.com/intent/post` link that opens X's composer prefilled, or the clipboard.
`NoAutomationTests` fails the build's tests if banned calls show up in `Sources/`.

## How it works

- `OEmbed` reads a post from just its link, through X's public embed endpoint (no account, no scraping).
  `AppModel.addPosts` takes pasted text, links, or drops, and can draft right away. Opening a draft on X files it
  as posted (Restore undoes it). A menu bar extra drafts from the clipboard without opening the window.
- `PostDeskKit/InboxParser` reads pasted posts (link, optional `by @handle`, text, blocks split by `---`).
  `XSearch` is the optional read-only X API v2 recent search with the user's bearer token.
- `ReplyDrafter` sends one post at a time to Claude (`ClaudeClient`, raw HTTP Messages API with a JSON
  schema, `fallbacks: "default"`), and returns a draft with a 1 to 10 lead score, or a skip with the reason.
- `PostWriter` writes 5 posts from `GitLog` (last 7 days of commits in the chosen repos).
  `PostSafety` lists what a person must still do: placeholders, media, length, links, hashtags.
- `DeskStore` keeps the inbox, drafts, skips, and every seen URL in `~/Library/Application Support/PostDesk/desk.json`
  (`APP_STORE=<file>` overrides it). The persona (name, products, keywords, repos) is in UserDefaults.
  API keys are in the keychain (`Keychain.swift`), never in files.
- `AppModel` runs every action; `ContentView` has the Replies and Posts pages. Redraft and Draft Anyway pass a
  one-off note to `ReplyDrafter.draft(_:note:)`; Rewrite is `PostWriter.rewrite`. `Reminder` is the daily notification.
- Customization: Settings > Writing (`Tone`, your own rules, posts per week, commit window), all part of
  `Persona` and added to both prompts by `Persona.styleRules`; Settings > Appearance (light, dark, or automatic,
  and the accent color, `UI/Theme.swift`).
- Buffer scheduling is not in the app. The project's cloud routine owns the Buffer queue, so the app
  never adds to it and nothing is scheduled twice.

## Layout

- `Sources/PostDesk/` the app. `Sources/PostDeskKit/` logic with no SwiftUI. Tests in `Tests/PostDeskKitTests/`.
- `Package.swift` a Swift package. There is no Xcode project. `build.sh` builds, signs, and installs `/Applications/PostDesk.app` (or `~/Applications`).
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh` (needs Xcode 26 actool).

## Build and check

- Build and install: `./build.sh` (`--open` restarts the app). Fix every warning.
- Unit tests: `swift test --scratch-path ~/Library/Developer/PostDesk/test-build`. They run offline with a fake transport.
- Never test against the real desk file: set `APP_STORE=/tmp/postdesk-test.json`.
- Live check with the real key: `APP_STORE=/tmp/postdesk-self.json /Applications/PostDesk.app/Contents/MacOS/PostDesk --selftest`
  (`SelfTest.swift`). It prints the drafts as Markdown and exits 0 when every check passes. Read the drafts, not only the result.

## Design rules

Same as StreamSpike: Apple's controls and system styles, `.tint`, `Palette.accent`, `Palette.accentText` for the accent (`.themed()` on every scene), spacing from `Space`
(`UI/Space.swift`, 4 pt grid), `.noInitialFocus()` on windows and sheets, `.fitsContent()` on Settings tabs,
`ContentUnavailableView` for empty states, `Label` with SF Symbols, and every action in the menu bar with a shortcut.

## Git

- Commit after each working change, with a message that says what the user can now do.
