// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "CascableCoreSwift",
    platforms: [.macOS(.v10_15), .iOS(.v13)],
    products: [
        .library(name: "CascableCoreSwift", targets: ["CascableCoreSwift"])
    ],
    dependencies: [
        .package(name: "CascableCore", url: "https://github.com/Cascable/cascablecore-distribution", .exact("12.2.4"))
    ],
    targets: [
        .target(name: "CascableCoreSwift", dependencies: ["CascableCore"]),
        .testTarget(name: "CascableCoreSwiftTests", dependencies: ["CascableCoreSwift"])
    ]
)
