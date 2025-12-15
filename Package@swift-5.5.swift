// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "CascableCoreSwift",
    platforms: [.macOS(.v11), .iOS(.v14), .macCatalyst(.v15)],
    products: [.library(name: "CascableCoreSwift", targets: ["CascableCoreSwift"])],
    dependencies: [
        .package(name: "CascableCore", url: "https://github.com/Cascable/cascablecore-distribution", from: "17.0.0")
    ],
    targets: [
        .target(name: "CascableCoreSwift", dependencies: ["CascableCore"]),
        .testTarget(name: "CascableCoreSwiftTests", dependencies: ["CascableCoreSwift"])
    ]
)
