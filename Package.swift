// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PostDesk",
    platforms: [.macOS(.v14)],
    targets: [
        // Drafting, parsing, and safety rules with no SwiftUI, so tests run without the app.
        .target(name: "PostDeskKit"),
        .executableTarget(
            name: "PostDesk",
            dependencies: ["PostDeskKit"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "PostDeskKitTests", dependencies: ["PostDeskKit"]),
    ]
)
