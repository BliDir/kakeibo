// swift-tools-version: 6.2
import PackageDescription

// Rule: KakeiboCore imports Foundation only. No UIKit, SwiftUI, Vision or SwiftData.
let package = Package(
    name: "KakeiboCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KakeiboCore", targets: ["KakeiboCore"]),
    ],
    targets: [
        .target(name: "KakeiboCore"),
        .testTarget(
            name: "KakeiboCoreTests",
            dependencies: ["KakeiboCore"],
            resources: [.copy("../Fixtures")]
        ),
    ]
)
