// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SweetDeck",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "sweetdeck", targets: ["SweetDeckCLI"]),
        .library(name: "SweetDeckDomain", targets: ["SweetDeckDomain"]),
        .library(name: "SweetDeckInfra", targets: ["SweetDeckInfra"]),
        .library(name: "SweetDeckXcode", targets: ["SweetDeckXcode"]),
        .library(name: "SweetDeckUseCases", targets: ["SweetDeckUseCases"]),
        .library(name: "SweetDeckProjectEdit", targets: ["SweetDeckProjectEdit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/tuist/XcodeProj.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "SweetDeckCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "SweetDeckDomain",
                "SweetDeckInfra",
                "SweetDeckXcode",
                "SweetDeckUseCases",
                "SweetDeckProjectEdit",
            ]
        ),
        .target(name: "SweetDeckDomain"),
        .target(
            name: "SweetDeckInfra",
            dependencies: ["SweetDeckDomain"]
        ),
        .target(
            name: "SweetDeckXcode",
            dependencies: ["SweetDeckDomain", "SweetDeckInfra"]
        ),
        .target(
            name: "SweetDeckUseCases",
            dependencies: ["SweetDeckDomain", "SweetDeckInfra", "SweetDeckXcode", "SweetDeckProjectEdit"]
        ),
        .target(
            name: "SweetDeckProjectEdit",
            dependencies: ["SweetDeckDomain", "SweetDeckInfra", .product(name: "XcodeProj", package: "XcodeProj")]
        ),
        .testTarget(
            name: "SweetDeckTests",
            dependencies: ["SweetDeckDomain", "SweetDeckInfra", "SweetDeckXcode", "SweetDeckUseCases", "SweetDeckProjectEdit"]
        ),
    ]
)
