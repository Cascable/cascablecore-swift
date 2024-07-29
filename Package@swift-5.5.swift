// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "CascableCoreSwift",
    platforms: [.macOS(.v10_15), .iOS(.v13), .macCatalyst(.v15)],
    products: [.library(name: "CascableCoreSwift", targets: ["CascableCoreSwift"])],
    dependencies: [
        .package(name: "CascableCore", url: "https://github.com/Cascable/cascablecore-distribution", .exact("14.0.2"))
    ],
    targets: [
        .target(name: "CascableCoreSwift", dependencies: ["CascableCore"]),
        .testTarget(name: "CascableCoreSwiftTests", dependencies: ["CascableCoreSwift"])
    ]
)
