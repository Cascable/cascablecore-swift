// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CascableCoreSwift",
    platforms: [.macOS(.v11), .iOS(.v14), .macCatalyst(.v15), .visionOS("1.1")],
    products: [.library(name: "CascableCoreSwift", targets: ["CascableCoreSwift"])],
    dependencies: [
        .package(url: "https://github.com/Cascable/cascablecore-distribution", from: "16.0.0")
    ],
    targets: [
        .target(name: "CascableCoreSwift", dependencies: [.product(name: "CascableCore", package: "cascablecore-distribution")]),
        .testTarget(name: "CascableCoreSwiftTests", dependencies: ["CascableCoreSwift"])
    ]
)
