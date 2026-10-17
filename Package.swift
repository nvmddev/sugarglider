// swift-tools-version:6.2
import PackageDescription

let upcomingFeatures: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Sugarglider",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Sugarglider",
            swiftSettings: upcomingFeatures + [
                .defaultIsolation(MainActor.self),
                .unsafeFlags(["-Osize"], .when(configuration: .release)),
            ]
        ),
        .testTarget(
            name: "SugargliderTests",
            dependencies: ["Sugarglider"],
            swiftSettings: upcomingFeatures
        ),
    ]
)
