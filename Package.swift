// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let name = "Provider"
let package = Package(
    name: name,
    defaultLocalization: "en",
    platforms: [.iOS(.v13)],
    products: [.library(name: name, targets: [name])],
    dependencies: [
        .package(
            url: "https://github.com/Lickability/Networking",
            .branch("feature/error-information")
        ),
        .package(
            url: "https://github.com/Lickability/Persister",
            .upToNextMajor(from: "1.0.0")
        )
    ],
    targets: [.target(name: name, dependencies: ["Networking", "Persister"], resources: [.process("Resources")])]
)
