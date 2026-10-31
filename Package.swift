// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LangCursor",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "LangCursorCore"),
        .executableTarget(name: "LangCursor", dependencies: ["LangCursorCore"]),
        .testTarget(name: "LangCursorCoreTests", dependencies: ["LangCursorCore"]),
    ]
)
