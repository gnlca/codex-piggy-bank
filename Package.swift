// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokensPiggyBank",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TokensPiggyBankCore", path: "CodexPiggyBank", exclude: ["App", "Views", "Resources"]),
        .testTarget(name: "TokensPiggyBankTests", dependencies: ["TokensPiggyBankCore"], path: "Tests"),
    ]
)
