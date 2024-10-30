// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let name = "Provider"
let package = Package(
    name: name,
    defaultLocalization: "en",
    platforms: [.iOS(.v16)],
    products: [.library(name: name, targets: [name])],
    dependencies: [
        .package(
            url: "https://github.com/Lickability/Networking",
            .upToNextMajor(from: "3.0.0")
        ),
        .package(
            url: "https://github.com/Lickability/Persister",
            .upToNextMajor(from: "2.0.0")
        )
    ],
    targets: [.target(name: name, dependencies: ["Networking", "Persister"], resources: [.process("Resources")])]
)
