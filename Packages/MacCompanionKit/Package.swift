// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacCompanionKit",
    // Package compile floors match the availability contracts already used by
    // the platform adapters and value-driven views. Shipping app targets keep
    // the higher macOS/iOS 26 product baseline recorded in the release plan.
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "CompanionDomain", targets: ["CompanionDomain"]),
        .library(name: "CompanionWire", targets: ["CompanionWire"]),
        .library(name: "CompanionSecurity", targets: ["CompanionSecurity"]),
        .library(name: "CompanionIPC", targets: ["CompanionIPC"]),
        .library(name: "CompanionCLI", targets: ["CompanionCLI"]),
        .library(name: "CompanionAgent", targets: ["CompanionAgent"]),
        // Host administration graph: macOS-only even though this aggregate
        // package also advertises iOS for its explicitly cross-built client graph.
        .library(name: "CompanionAgentPlatform", targets: ["CompanionAgentPlatform"]),
        .library(
            name: "CompanionLocalXPCPlatform",
            targets: ["CompanionLocalXPCPlatform"]
        ),
        .library(name: "CompanionHost", targets: ["CompanionHost"]),
        .library(name: "CompanionHostWire", targets: ["CompanionHostWire"]),
        .library(name: "CompanionHostSession", targets: ["CompanionHostSession"]),
        .library(name: "CompanionNetworkPlatform", targets: ["CompanionNetworkPlatform"]),
        .library(
            name: "CompanionAgentNetworkPlatform",
            targets: ["CompanionAgentNetworkPlatform"]
        ),
        .library(
            name: "CompanionAgentProductPlatform",
            targets: ["CompanionAgentProductPlatform"]
        ),
        .library(
            name: "CompanionAgentApplicationPlatform",
            targets: ["CompanionAgentApplicationPlatform"]
        ),
        .library(
            name: "CompanionClientNetworkPlatform",
            targets: ["CompanionClientNetworkPlatform"]
        ),
        .library(name: "CompanionPersistence", targets: ["CompanionPersistence"]),
        .library(name: "CompanionHostPersistence", targets: ["CompanionHostPersistence"]),
        .library(name: "CompanionTransport", targets: ["CompanionTransport"]),
        .library(name: "CompanionPairing", targets: ["CompanionPairing"]),
        .library(name: "CompanionAuthentication", targets: ["CompanionAuthentication"]),
        .library(name: "CompanionOperations", targets: ["CompanionOperations"]),
        .library(name: "CompanionNativeProviders", targets: ["CompanionNativeProviders"]),
        .library(name: "CompanionDiscovery", targets: ["CompanionDiscovery"]),
        .library(name: "CompanionLifecycle", targets: ["CompanionLifecycle"]),
        .library(name: "CompanionObservation", targets: ["CompanionObservation"]),
        .library(name: "CompanionPresentation", targets: ["CompanionPresentation"]),
        .library(name: "CompanionClient", targets: ["CompanionClient"]),
        .library(name: "CompanionClientApp", targets: ["CompanionClientApp"]),
        .library(name: "CompanionClientPlatform", targets: ["CompanionClientPlatform"]),
        .library(name: "CompanionClientUI", targets: ["CompanionClientUI"]),
        .library(name: "CompanionMacApp", targets: ["CompanionMacApp"]),
        .library(
            name: "CompanionMacApplicationPlatform",
            targets: ["CompanionMacApplicationPlatform"]
        ),
        .library(name: "CompanionMacUI", targets: ["CompanionMacUI"]),
        .library(name: "CompanionInteractiveShared", targets: ["CompanionInteractiveShared"]),
        .library(name: "CompanionInteractiveWire", targets: ["CompanionInteractiveWire"]),
        .library(name: "CompanionInteractiveHost", targets: ["CompanionInteractiveHost"]),
        .library(name: "CompanionInteractiveClient", targets: ["CompanionInteractiveClient"]),
        .library(name: "CompanionInteractiveRuntime", targets: ["CompanionInteractiveRuntime"]),
        .library(name: "CompanionHostPlatform", targets: ["CompanionHostPlatform"]),
    ],
    targets: [
        .target(name: "CompanionDomain"),
        .target(
            name: "CompanionWire",
            dependencies: ["CompanionDiscovery", "CompanionDomain"]
        ),
        .target(name: "CompanionDiscovery"),
        .target(name: "CompanionLifecycle"),
        .target(
            name: "CompanionObservation",
            dependencies: ["CompanionDomain"]
        ),
        .target(
            name: "CompanionPresentation",
            dependencies: [
                "CompanionClient", "CompanionDiscovery", "CompanionDomain",
                "CompanionIPC", "CompanionInteractiveShared", "CompanionInteractiveWire",
                "CompanionObservation",
                "CompanionTransport", "CompanionWire",
            ]
        ),
        .target(
            name: "CompanionClient",
            dependencies: [
                "CompanionDiscovery", "CompanionDomain", "CompanionObservation",
                "CompanionSecurity", "CompanionTransport", "CompanionWire",
            ]
        ),
        .target(
            name: "CompanionClientApp",
            dependencies: [
                "CompanionClient", "CompanionDiscovery", "CompanionPresentation",
                "CompanionTransport", "CompanionWire",
            ]
        ),
        .target(
            name: "CompanionClientPlatform",
            dependencies: [
                "CompanionClient", "CompanionClientApp",
                "CompanionClientNetworkPlatform",
                "CompanionDiscovery",
                "CompanionInteractiveClient",
                "CompanionInteractiveShared", "CompanionInteractiveWire",
                "CompanionPresentation", "CompanionSecurity",
                "CompanionWire",
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation", .when(platforms: [.iOS])),
                .linkedFramework("LocalAuthentication", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("CoreMedia", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("CoreVideo", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("Network", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("Security", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedFramework("VideoToolbox", .when(platforms: [.macOS, .iOS])),
            ]
        ),
        .target(
            name: "CompanionClientUI",
            dependencies: [
                "CompanionClient", "CompanionClientNetworkPlatform",
                "CompanionClientPlatform", "CompanionDomain",
                "CompanionInteractiveClient",
                "CompanionInteractiveShared", "CompanionInteractiveWire",
                "CompanionObservation", "CompanionPresentation",
                "CompanionTransport", "CompanionWire",
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation", .when(platforms: [.iOS])),
                .linkedFramework("SwiftUI", .when(platforms: [.iOS])),
                .linkedFramework("Vision", .when(platforms: [.iOS])),
                .linkedFramework("VisionKit", .when(platforms: [.iOS])),
            ]
        ),
        .target(
            name: "CompanionMacApp",
            dependencies: [
                "CompanionIPC", "CompanionLifecycle", "CompanionPresentation",
            ]
        ),
        .target(
            name: "CompanionMacApplicationPlatform",
            dependencies: [
                "CompanionAgent", "CompanionAgentPlatform", "CompanionIPC",
                "CompanionInteractiveRuntime",
                "CompanionLocalXPCPlatform", "CompanionMacApp",
                "CompanionPresentation",
            ],
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("CoreGraphics", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "CompanionMacUI",
            dependencies: [
                "CompanionDomain", "CompanionIPC", "CompanionLifecycle", "CompanionMacApp", "CompanionPersistence",
                "CompanionPresentation", "CompanionWire",
            ],
            linkerSettings: [
                .linkedFramework("CoreImage", .when(platforms: [.macOS])),
                .linkedFramework("SwiftUI", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "CompanionInteractiveShared",
            dependencies: ["CompanionDomain"]
        ),
        .target(
            name: "CompanionInteractiveWire",
            dependencies: ["CompanionDomain", "CompanionInteractiveShared", "CompanionSecurity", "CompanionWire"]
        ),
        .target(
            name: "CompanionInteractiveHost",
            dependencies: [
                "CompanionDomain", "CompanionInteractiveShared",
                "CompanionInteractiveWire", "CompanionPersistence",
                "CompanionSecurity", "CompanionWire",
            ]
        ),
        .target(
            name: "CompanionInteractiveClient",
            dependencies: [
                "CompanionClient", "CompanionDomain", "CompanionInteractiveShared",
                "CompanionInteractiveWire", "CompanionTransport",
                "CompanionWire",
            ]
        ),
        .target(
            name: "CompanionInteractiveRuntime",
            dependencies: [
                "CompanionDomain", "CompanionIPC",
                "CompanionInteractiveShared", "CompanionInteractiveWire",
            ]
        ),
        .target(
            name: "CompanionHostPlatform",
            dependencies: [
                "CompanionDomain", "CompanionIPC",
                "CompanionInteractiveHost", "CompanionInteractiveShared",
                "CompanionInteractiveRuntime", "CompanionInteractiveWire", "CompanionPersistence",
                "CompanionSecurity",
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics", .when(platforms: [.macOS])),
                .linkedFramework("CoreMedia", .when(platforms: [.macOS])),
                .linkedFramework("CoreVideo", .when(platforms: [.macOS])),
                .linkedFramework("ScreenCaptureKit", .when(platforms: [.macOS])),
                .linkedFramework("Security", .when(platforms: [.macOS])),
                .linkedFramework("VideoToolbox", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "CompanionSecurity",
            dependencies: ["CompanionDomain"]
        ),
        .target(
            name: "CompanionIPC",
            dependencies: [
                "CompanionDomain", "CompanionInteractiveShared",
                "CompanionLifecycle", "CompanionPersistence", "CompanionWire",
            ]
        ),
        .target(
            name: "CompanionCLI",
            dependencies: ["CompanionIPC"]
        ),
        .target(
            name: "CompanionAgent",
            dependencies: [
                "CompanionAuthentication", "CompanionDiscovery", "CompanionDomain", "CompanionHost", "CompanionHostPersistence", "CompanionHostSession", "CompanionHostWire", "CompanionIPC", "CompanionInteractiveHost",
                "CompanionInteractiveShared", "CompanionInteractiveWire", "CompanionPersistence",
                "CompanionLifecycle", "CompanionOperations", "CompanionPairing", "CompanionTransport", "CompanionWire",
            ]
        ),
        .target(
            name: "CompanionAgentPlatform",
            dependencies: [
                "CompanionAgent", "CompanionIPC", "CompanionLifecycle", "CompanionLocalXPCPlatform",
                "CompanionMacApp", "CompanionPersistence", "CompanionWire",
            ],
            linkerSettings: [
                .linkedFramework("ServiceManagement", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "CompanionLocalXPCPlatformC",
            publicHeadersPath: "include"
        ),
        .target(
            name: "CompanionLocalXPCPlatform",
            dependencies: [
                "CompanionIPC",
                .target(
                    name: "CompanionLocalXPCPlatformC",
                    condition: .when(platforms: [.macOS])
                ),
            ]
        ),
        .target(
            name: "CompanionHost",
            dependencies: ["CompanionDomain"],
            linkerSettings: [
                .linkedFramework("IOKit", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "CompanionHostWire",
            dependencies: [
                "CompanionAuthentication", "CompanionHost",
                "CompanionPersistence", "CompanionWire",
            ]
        ),
        .target(
            name: "CompanionHostSession",
            dependencies: [
                "CompanionAuthentication", "CompanionDomain", "CompanionHost",
                "CompanionHostWire", "CompanionInteractiveHost",
                "CompanionOperations", "CompanionPersistence",
                "CompanionTransport", "CompanionWire",
            ]
        ),
        .target(
            name: "CompanionNetworkPlatform",
            dependencies: [
                "CompanionDiscovery", "CompanionDomain", "CompanionHostPlatform",
                "CompanionHostSession", "CompanionSecurity",
                "CompanionTransport", "CompanionWire",
            ],
            linkerSettings: [
                .linkedFramework("Security", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "CompanionAgentNetworkPlatform",
            dependencies: [
                "CompanionAgent", "CompanionDiscovery",
                "CompanionHostPlatform", "CompanionHostSession",
                "CompanionIPC",
                "CompanionLifecycle", "CompanionNetworkPlatform",
                "CompanionNativeProviders",
                "CompanionOperations", "CompanionSecurity",
                "CompanionWire",
            ]
        ),
        .target(
            name: "CompanionAgentProductPlatform",
            dependencies: [
                "CompanionAgent", "CompanionAgentNetworkPlatform",
                "CompanionAgentPlatform", "CompanionDomain",
                "CompanionHostPlatform",
                "CompanionDiscovery", "CompanionIPC",
                "CompanionLifecycle",
                "CompanionLocalXPCPlatform",
                "CompanionNetworkPlatform",
                "CompanionSecurity", "CompanionWire",
            ],
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("CoreGraphics", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "CompanionAgentApplicationPlatform",
            dependencies: [
                "CompanionAgent", "CompanionAgentNetworkPlatform",
                "CompanionAgentPlatform", "CompanionAgentProductPlatform",
                "CompanionHost", "CompanionHostPlatform",
                "CompanionLocalXPCPlatform",
            ]
        ),
        .target(
            name: "CompanionClientNetworkPlatform",
            dependencies: [
                "CompanionClient", "CompanionClientApp", "CompanionDiscovery",
                "CompanionInteractiveClient", "CompanionInteractiveWire",
                "CompanionPresentation", "CompanionSecurity",
                "CompanionTransport", "CompanionWire",
            ],
            linkerSettings: [
                .linkedFramework("Security", .when(platforms: [.macOS, .iOS])),
            ]
        ),
        .target(
            name: "CompanionPersistence",
            dependencies: ["CompanionDomain"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "CompanionHostPersistence",
            dependencies: ["CompanionHost", "CompanionPersistence"]
        ),
        .target(
            name: "CompanionTransport",
            dependencies: ["CompanionDiscovery", "CompanionSecurity", "CompanionWire"]
        ),
        .target(
            name: "CompanionPairing",
            dependencies: ["CompanionDomain", "CompanionSecurity", "CompanionPersistence"]
        ),
        .target(
            name: "CompanionAuthentication",
            dependencies: ["CompanionDomain", "CompanionSecurity", "CompanionPersistence"]
        ),
        .target(
            name: "CompanionOperations",
            dependencies: ["CompanionAuthentication", "CompanionDomain", "CompanionPersistence", "CompanionSecurity", "CompanionWire"]
        ),
        .target(
            name: "CompanionNativeProviders",
            dependencies: ["CompanionDomain", "CompanionOperations", "CompanionWire"],
            linkerSettings: [
                .linkedFramework("CoreAudio", .when(platforms: [.macOS])),
                .linkedFramework("IOKit", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "CompanionTestSupport",
            dependencies: ["CompanionDomain"]
        ),
        .testTarget(
            name: "CompanionDomainTests",
            dependencies: ["CompanionDomain", "CompanionTestSupport"]
        ),
        .testTarget(
            name: "CompanionWireTests",
            dependencies: ["CompanionDiscovery", "CompanionWire", "CompanionTestSupport"]
        ),
        .testTarget(
            name: "CompanionDiscoveryTests",
            dependencies: ["CompanionDiscovery"]
        ),
        .testTarget(
            name: "CompanionLifecycleTests",
            dependencies: ["CompanionLifecycle"]
        ),
        .testTarget(
            name: "CompanionObservationTests",
            dependencies: ["CompanionDomain", "CompanionObservation"]
        ),
        .testTarget(
            name: "CompanionPresentationTests",
            dependencies: [
                "CompanionClient", "CompanionDiscovery", "CompanionDomain",
                "CompanionIPC", "CompanionInteractiveShared", "CompanionInteractiveWire",
                "CompanionObservation", "CompanionPresentation",
                "CompanionSecurity", "CompanionTransport", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionClientAppTests",
            dependencies: [
                "CompanionClient", "CompanionClientApp", "CompanionDiscovery",
                "CompanionDomain", "CompanionPresentation", "CompanionSecurity",
                "CompanionTransport", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionClientTests",
            dependencies: [
                "CompanionClient", "CompanionDiscovery", "CompanionDomain",
                "CompanionSecurity", "CompanionTestSupport",
                "CompanionTransport", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionClientUITests",
            dependencies: [
                "CompanionClient", "CompanionClientNetworkPlatform",
                "CompanionClientUI", "CompanionDiscovery",
                "CompanionDomain", "CompanionInteractiveClient",
                "CompanionInteractiveShared",
                "CompanionInteractiveWire", "CompanionPresentation",
                "CompanionTransport", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionMacAppTests",
            dependencies: [
                "CompanionDiscovery", "CompanionIPC", "CompanionLifecycle", "CompanionMacApp",
                "CompanionPresentation", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionMacApplicationPlatformTests",
            dependencies: [
                "CompanionAgent", "CompanionAgentPlatform", "CompanionIPC",
                "CompanionInteractiveRuntime",
                "CompanionLocalXPCPlatform", "CompanionMacApp",
                "CompanionMacApplicationPlatform",
            ]
        ),
        .testTarget(
            name: "CompanionMacUITests",
            dependencies: [
                "CompanionDomain", "CompanionInteractiveShared", "CompanionIPC",
                "CompanionMacApp", "CompanionMacUI", "CompanionPersistence",
                "CompanionPresentation", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionClientPlatformTests",
            dependencies: [
                "CompanionClient", "CompanionClientPlatform",
                "CompanionSecurity",
            ]
        ),
        .testTarget(
            name: "CompanionInteractiveSharedTests",
            dependencies: ["CompanionDomain", "CompanionInteractiveShared", "CompanionTestSupport"]
        ),
        .testTarget(
            name: "CompanionInteractiveWireTests",
            dependencies: ["CompanionInteractiveShared", "CompanionInteractiveWire", "CompanionTestSupport"]
        ),
        .testTarget(
            name: "CompanionInteractiveHostTests",
            dependencies: ["CompanionInteractiveHost", "CompanionInteractiveShared", "CompanionInteractiveWire", "CompanionPersistence", "CompanionSecurity", "CompanionWire"]
        ),
        .testTarget(
            name: "CompanionInteractiveClientTests",
            dependencies: [
                "CompanionClient", "CompanionDiscovery", "CompanionDomain",
                "CompanionInteractiveClient",
                "CompanionInteractiveShared", "CompanionInteractiveWire",
                "CompanionSecurity", "CompanionTransport", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionInteractiveRuntimeTests",
            dependencies: [
                "CompanionDomain", "CompanionIPC",
                "CompanionInteractiveRuntime", "CompanionInteractiveShared",
                "CompanionInteractiveWire", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionHostPlatformTests",
            dependencies: [
                "CompanionDomain", "CompanionHostPlatform", "CompanionIPC",
                "CompanionInteractiveHost", "CompanionInteractiveShared",
                "CompanionInteractiveRuntime", "CompanionInteractiveWire", "CompanionPersistence",
                "CompanionSecurity",
            ]
        ),
        .testTarget(
            name: "CompanionSecurityTests",
            dependencies: ["CompanionSecurity", "CompanionTestSupport"]
        ),
        .testTarget(
            name: "CompanionIPCTests",
            dependencies: [
                "CompanionDiscovery", "CompanionDomain", "CompanionIPC", "CompanionInteractiveShared",
                "CompanionPersistence", "CompanionTestSupport", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionCLITests",
            dependencies: [
                "CompanionCLI", "CompanionIPC", "CompanionTestSupport",
            ]
        ),
        .testTarget(
            name: "CompanionAgentTests",
            dependencies: [
                "CompanionAgent", "CompanionAgentNetworkPlatform", "CompanionAuthentication", "CompanionDiscovery", "CompanionDomain", "CompanionHost", "CompanionIPC",
                "CompanionHostSession", "CompanionInteractiveHost", "CompanionInteractiveShared",
                "CompanionInteractiveWire", "CompanionLifecycle", "CompanionPersistence",
                "CompanionNativeProviders", "CompanionNetworkPlatform", "CompanionOperations", "CompanionPairing", "CompanionSecurity", "CompanionTransport", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionAgentPlatformTests",
            dependencies: [
                "CompanionAgent", "CompanionAgentPlatform", "CompanionIPC",
                "CompanionLifecycle", "CompanionLocalXPCPlatform",
                "CompanionMacApp", "CompanionPersistence", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionAgentProductPlatformTests",
            dependencies: [
                "CompanionAgent", "CompanionAgentNetworkPlatform",
                "CompanionAgentPlatform", "CompanionAgentProductPlatform",
                "CompanionDiscovery", "CompanionDomain",
                "CompanionHost", "CompanionHostPlatform",
                "CompanionInteractiveHost", "CompanionInteractiveShared",
                "CompanionIPC", "CompanionLifecycle",
                "CompanionLocalXPCPlatform", "CompanionMacApp",
                "CompanionNetworkPlatform",
                "CompanionOperations", "CompanionPersistence",
                "CompanionSecurity", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionAgentApplicationPlatformTests",
            dependencies: [
                "CompanionAgent", "CompanionAgentApplicationPlatform",
                "CompanionAgentNetworkPlatform", "CompanionAgentPlatform",
                "CompanionAgentProductPlatform",
                "CompanionHostPlatform", "CompanionInteractiveHost",
                "CompanionLifecycle",
                "CompanionMacApp",
            ]
        ),
        .testTarget(
            name: "CompanionLocalXPCPlatformTests",
            dependencies: [
                "CompanionDomain", "CompanionIPC",
                "CompanionLocalXPCPlatform", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionHostTests",
            dependencies: ["CompanionHost"]
        ),
        .testTarget(
            name: "CompanionHostWireTests",
            dependencies: [
                "CompanionAuthentication", "CompanionDomain", "CompanionHost",
                "CompanionHostWire", "CompanionPersistence", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionHostSessionTests",
            dependencies: [
                "CompanionAuthentication", "CompanionDomain", "CompanionHost",
                "CompanionHostSession", "CompanionInteractiveWire",
                "CompanionOperations", "CompanionPersistence", "CompanionSecurity",
                "CompanionTransport", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionClientNetworkPlatformTests",
            dependencies: [
                "CompanionClient", "CompanionClientApp",
                "CompanionClientNetworkPlatform", "CompanionDiscovery",
                "CompanionInteractiveClient", "CompanionInteractiveWire",
                "CompanionPresentation", "CompanionSecurity",
                "CompanionTransport", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionNetworkPlatformTests",
            dependencies: [
                "CompanionAuthentication", "CompanionDomain", "CompanionHost",
                "CompanionHostPlatform", "CompanionHostSession",
                "CompanionNetworkPlatform", "CompanionOperations",
                "CompanionPersistence", "CompanionSecurity",
                "CompanionTestSupport", "CompanionTransport", "CompanionWire",
            ]
        ),
        .testTarget(
            name: "CompanionPersistenceTests",
            dependencies: ["CompanionPersistence"]
        ),
        .testTarget(
            name: "CompanionHostPersistenceTests",
            dependencies: ["CompanionHostPersistence", "CompanionHost", "CompanionPersistence"]
        ),
        .testTarget(
            name: "CompanionTransportTests",
            dependencies: ["CompanionDiscovery", "CompanionTestSupport", "CompanionTransport", "CompanionWire"]
        ),
        .testTarget(
            name: "CompanionPairingTests",
            dependencies: ["CompanionPairing", "CompanionSecurity", "CompanionPersistence"]
        ),
        .testTarget(
            name: "CompanionAuthenticationTests",
            dependencies: ["CompanionAuthentication", "CompanionSecurity", "CompanionPersistence"]
        ),
        .testTarget(
            name: "CompanionOperationsTests",
            dependencies: ["CompanionAuthentication", "CompanionDomain", "CompanionOperations", "CompanionPersistence", "CompanionSecurity", "CompanionTestSupport", "CompanionWire"]
        ),
        .testTarget(
            name: "CompanionNativeProvidersTests",
            dependencies: ["CompanionNativeProviders", "CompanionOperations", "CompanionWire"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
