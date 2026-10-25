// swift-tools-version:6.2
// Copied into a temporary directory by tools/tests/run-static-tests.sh together
// with browser/Reynard/Client/Utilities/BoundedZipArchive.swift and main.swift.
import PackageDescription

let package = Package(
    name: "BoundedZipArchiveTests",
    dependencies: [
        // Same exact version as browser/Reynard.xcodeproj.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
    ],
    targets: [
        .executableTarget(
            name: "BoundedZipArchiveTests",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")],
            // Match the app target: Swift 5 mode with MainActor default isolation.
            swiftSettings: [.defaultIsolation(MainActor.self), .swiftLanguageMode(.v5)]
        )
    ]
)
