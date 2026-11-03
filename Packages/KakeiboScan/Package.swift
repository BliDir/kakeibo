// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KakeiboScan",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KakeiboScan", targets: ["KakeiboScan"]),
    ],
    dependencies: [
        .package(path: "../KakeiboCore"),
    ],
    targets: [
        .target(name: "KakeiboScan", dependencies: ["KakeiboCore"]),
        .testTarget(name: "KakeiboScanTests", dependencies: ["KakeiboScan"]),
    ]
)
