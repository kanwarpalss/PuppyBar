// swift-tools-version:5.9
import PackageDescription

// Note: tests are a plain executable, not an XCTest target, because XCTest ships with
// Xcode and this machine has Command Line Tools only. `swift run PuppyBarTests` exits
// non-zero on failure, so it still works as a gate.
let package = Package(
    name: "PuppyBar",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic: parsing, formatting, models. No AppKit -> testable anywhere.
        .target(name: "PuppyBarCore"),
        // The menu bar app itself.
        .executableTarget(name: "PuppyBar", dependencies: ["PuppyBarCore"]),
        // The test suite.
        .executableTarget(name: "PuppyBarTests", dependencies: ["PuppyBarCore"]),
    ]
)
