// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InYourFace",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CommitmentProtection", targets: ["CommitmentProtection"]),
        .executable(name: "InYourFace", targets: ["InYourFace"]),
        .executable(
            name: "MeetingIncomingInternalResetHelper",
            targets: ["MeetingIncomingInternalResetHelper"]
        ),
        .executable(
            name: "MeetingIncomingRelaunchHelper",
            targets: ["MeetingIncomingRelaunchHelper"]
        ),
        .executable(
            name: "MeetingIncomingAppDataResetHelper",
            targets: ["MeetingIncomingAppDataResetHelper"]
        )
    ],
    targets: [
        .target(name: "CommitmentProtection"),
        .target(name: "MeetingIncomingHelperSupport"),
        .executableTarget(name: "InYourFace", dependencies: ["CommitmentProtection"]),
        .executableTarget(
            name: "MeetingIncomingInternalResetHelper",
            dependencies: ["MeetingIncomingHelperSupport"]
        ),
        .executableTarget(
            name: "MeetingIncomingRelaunchHelper",
            dependencies: ["MeetingIncomingHelperSupport"]
        ),
        .executableTarget(
            name: "MeetingIncomingAppDataResetHelper",
            dependencies: ["MeetingIncomingHelperSupport"]
        ),
        .testTarget(name: "CommitmentProtectionTests", dependencies: ["CommitmentProtection"]),
        .testTarget(
            name: "InYourFaceTests",
            dependencies: ["InYourFace", "CommitmentProtection"]
        ),
        .testTarget(
            name: "MeetingIncomingHelperSupportTests",
            dependencies: ["MeetingIncomingHelperSupport"]
        )
    ]
)
