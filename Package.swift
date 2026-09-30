// swift-tools-version: 5.10
//
// QDVC Bibliotheca for macOS — a native SwiftUI reference manager whose
// library is a folder of plain BibTeX, Markdown and YAML files (see
// docs/FILE_FORMAT.md). The format is shared with the Python/GTK edition of
// QDVC Bibliotheca, so both can open the same library, but neither needs the
// other.
//
// Build:   swift build            (or open this folder in Xcode)
// Test:    swift test
// Bundle:  scripts/build-app.sh   (ad-hoc signed .app, no Apple account needed)

import PackageDescription

let package = Package(
    name: "QDVCBibliotheca",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QDVCBibliotheca", targets: ["QDVCBibliotheca"]),
        .library(name: "BibliothecaCore", targets: ["BibliothecaCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        // Pure model layer: no AppKit/SwiftUI imports, unit-testable.
        .target(
            name: "BibliothecaCore",
            dependencies: [.product(name: "Yams", package: "Yams")]
        ),
        // The SwiftUI/AppKit front-end.
        .executableTarget(
            name: "QDVCBibliotheca",
            dependencies: ["BibliothecaCore"]
        ),
        .testTarget(
            name: "BibliothecaCoreTests",
            dependencies: ["BibliothecaCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
