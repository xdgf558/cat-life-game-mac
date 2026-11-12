// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CatGameCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CatGameCore", targets: ["CatGameCore"])],
    targets: [
        .target(name: "CatGameCore"),
        .testTarget(name: "CatGameCoreTests", dependencies: ["CatGameCore"])
    ]
)
