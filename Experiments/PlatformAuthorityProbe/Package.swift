// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PlatformAuthorityProbe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "platform-authority-probe", targets: ["PlatformAuthorityProbe"]),
    ],
    dependencies: [
        .package(path: "../../Packages/MacCompanionKit"),
    ],
    targets: [
        .target(
            name: "PlatformAuthorityProbeCore",
            dependencies: [
                .product(
                    name: "CompanionHostPlatform",
                    package: "MacCompanionKit"
                ),
            ]
        ),
        .executableTarget(
            name: "PlatformAuthorityProbe",
            dependencies: ["PlatformAuthorityProbeCore"]
        ),
        .testTarget(
            name: "PlatformAuthorityProbeCoreTests",
            dependencies: ["PlatformAuthorityProbeCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
