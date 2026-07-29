// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PasteDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PasteCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PasteDeck",
            dependencies: ["PasteCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // CommandLineTools 環境には XCTest / swift-testing が同梱されないため、
        // テストは依存ゼロの実行ターゲットとして `swift run PasteCoreTestRunner` で実行する
        .executableTarget(
            name: "PasteCoreTestRunner",
            dependencies: ["PasteCore"],
            path: "Tests/PasteCoreRunner",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
