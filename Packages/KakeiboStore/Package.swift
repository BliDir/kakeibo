// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KakeiboStore",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KakeiboStore", targets: ["KakeiboStore"]),
    ],
    dependencies: [
        .package(path: "../KakeiboCore"),
    ],
    targets: [
        .target(name: "KakeiboStore", dependencies: ["KakeiboCore"]),
        .testTarget(name: "KakeiboStoreTests", dependencies: ["KakeiboStore"]),
    ]
)
