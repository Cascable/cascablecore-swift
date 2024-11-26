// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CascableCoreSwift",
    platforms: [.macOS(.v10_15), .iOS(.v13), .macCatalyst(.v15), .visionOS("1.1")],
    products: [.library(name: "CascableCoreSwift", targets: ["CascableCoreSwift"])],
    dependencies: [
        .package(name: "CascableCore", url: "https://github.com/Cascable/cascablecore-distribution", .exact("15.0.0"))
    ],
    targets: [
        .target(name: "CascableCoreSwift", dependencies: ["CascableCore"]),
        .testTarget(name: "CascableCoreSwiftTests", dependencies: ["CascableCoreSwift"])
    ]
)
