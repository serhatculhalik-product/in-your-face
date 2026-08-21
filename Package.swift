// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InYourFace",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CommitmentProtection", targets: ["CommitmentProtection"]),
        .executable(name: "InYourFace", targets: ["InYourFace"])
    ],
    targets: [
        .target(name: "CommitmentProtection"),
        .executableTarget(name: "InYourFace", dependencies: ["CommitmentProtection"]),
        .testTarget(name: "CommitmentProtectionTests", dependencies: ["CommitmentProtection"]),
        .testTarget(name: "InYourFaceTests", dependencies: ["InYourFace", "CommitmentProtection"])
    ]
)
