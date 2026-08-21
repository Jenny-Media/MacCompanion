// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NetworkDiscoveryProbe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "network-discovery-probe", targets: ["NetworkDiscoveryProbe"]),
    ],
    dependencies: [
        .package(path: "../../Packages/MacCompanionKit"),
    ],
    targets: [
        .executableTarget(
            name: "NetworkDiscoveryProbe",
            dependencies: [
                .product(name: "CompanionDiscovery", package: "MacCompanionKit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
