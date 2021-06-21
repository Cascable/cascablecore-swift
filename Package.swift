// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CascableCoreSwift",
    platforms: [.macOS(.v10_15), .iOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "CascableCoreSwift",
            targets: ["CascableCoreSwift"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(name: "CascableCore", url: "git@github.com:Cascable/cascablecore-distribution", .exact("10.0.1"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "CascableCoreSwift",
            dependencies: ["CascableCore"]),
        .testTarget(
            name: "CascableCoreSwiftTests",
            dependencies: ["CascableCoreSwift"]),
    ]
)
