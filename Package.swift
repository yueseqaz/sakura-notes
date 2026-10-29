// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SakuraNotes",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SakuraNotes", targets: ["SakuraNotesApp"]),
        .library(name: "SakuraCore", targets: ["SakuraCore"]),
        .library(name: "SakuraStorage", targets: ["SakuraStorage"]),
        .library(name: "SakuraSearch", targets: ["SakuraSearch"]),
        .library(name: "SakuraAI", targets: ["SakuraAI"]),
    ],
    dependencies: [
        // Apple's CommonMark/GFM parser. Used for the document model (outline,
        // tags, tasks, links) and for safe HTML rendering (raw HTML is not
        // passed through by default). BSD-2-Clause / Apache-2.0, MIT-compatible.
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "SakuraCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "SakuraStorage",
            dependencies: ["SakuraCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "SakuraSearch",
            dependencies: ["SakuraCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "SakuraAI",
            dependencies: ["SakuraCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SakuraNotesApp",
            dependencies: ["SakuraCore", "SakuraStorage", "SakuraSearch", "SakuraAI"],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SakuraNotesTests",
            dependencies: ["SakuraCore", "SakuraStorage", "SakuraSearch", "SakuraAI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
