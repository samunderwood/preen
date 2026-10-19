// swift-tools-version:6.2
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "PreenCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PreenCore", targets: ["PreenCore"]),
    ],
    targets: [
        .target(
            name: "PreenCore",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "PreenCoreTests",
            dependencies: ["PreenCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
