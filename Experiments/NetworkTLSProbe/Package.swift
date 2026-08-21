// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NetworkTLSProbe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "network-tls-probe", targets: ["NetworkTLSProbe"]),
    ],
    dependencies: [
        .package(path: "../../Packages/MacCompanionKit"),
    ],
    targets: [
        .executableTarget(
            name: "NetworkTLSProbe",
            dependencies: [
                .product(name: "CompanionTransport", package: "MacCompanionKit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
