import CompanionClient
import CompanionClientUI
import CompanionDiscovery
import CompanionDomain
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionObservation
import CompanionPresentation
import CompanionWire
import Foundation

enum HarnessFixtures {
    static let hostID = UUID(uuidString: "018f5000-0000-7000-8000-000000000001")!

    static let pairedHost: ClientDurablePairedHostV0 = {
        // Canonical public metadata only. The two public keys are copied from
        // the repository's public conformance fixture; there are no private
        // keys or signing capabilities in this harness.
        let canonicalRecord = #"{"approvalKey":{"protection":"whenUnlockedThisDeviceOnlyUserPresence","publicKey":"BHzyexiNA09-ilI4AwS1GsPAiWnid_IbNaYLSPxHZpl4B3dVENuO0EApPZrGn3Qw27p9reY86YIpngS3nSJ4c9E","reference":"018f6000-0000-7000-8000-000000000002","role":"approval"},"authorizationEpoch":1,"clientID":"018f2000-0000-7000-8000-000000000001","deviceID":"018f7000-0000-7000-8000-000000000001","deviceState":"activeMonitorOnly","endpoints":[{"kind":"bonjour","port":47474,"value":"studio._maccompanion._tcp.local."},{"kind":"ipv4","port":47474,"value":"192.168.50.10"},{"kind":"dns","port":47474,"value":"studio.example.test"},{"kind":"ipv4","port":47474,"value":"203.0.113.10"}],"grantRevision":1,"hostFingerprint":"808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f","hostID":"018f5000-0000-7000-8000-000000000001","pairingID":"018f4000-0000-7000-8000-000000000001","policyRevision":1,"schemaVersion":1,"sessionKey":{"protection":"afterFirstUnlockThisDeviceOnly","publicKey":"BGsX0fLhLEJH-Lzm5WOkQPJ3A32BLeszoPShOUXYmMKWT-NC4v4af5uO5-tKfA-eFivOM1drMV7Oy7ZAaDe_UfU","reference":"018f6000-0000-7000-8000-000000000001","role":"session"}}"#
        return try! ClientPairedHostStorageCodecV0.decode(
            Data(canonicalRecord.utf8)
        )
    }()

    static let bootstrapPlan = ClientConfiguredRouteBootstrapPlanV1(
        pairedHost: pairedHost
    )

    static let initialRouteSnapshot: ClientConfiguredRouteCatalogSnapshotV1 = {
        let local = try! EndpointCandidate(
            kind: .bonjour,
            value: "studio._maccompanion._tcp.local.",
            port: 47_474
        )
        let privateDNS = try! EndpointCandidate(
            kind: .dns,
            value: "studio.example.test",
            port: 47_474
        )
        let records = [
            try! ClientConfiguredRouteRecordV1(
                configuredRouteID: WireBytes16(Data(repeating: 1, count: 16)),
                endpoint: local,
                provenance: .localDiscovery
            ),
            try! ClientConfiguredRouteRecordV1(
                configuredRouteID: WireBytes16(Data(repeating: 2, count: 16)),
                endpoint: privateDNS,
                provenance: .privateDNS
            ),
        ]
        return try! ClientConfiguredRouteCatalogSnapshotV1(
            hostID: hostID,
            revision: 1,
            catalog: ClientConfiguredRouteCatalogV1(records: records)
        )
    }()

    static let approvedActionCatalog: GrantedCapabilityCatalogV1 = {
        let parameters = try! CapabilitySchemaV1.object(properties: [
            CapabilitySchemaPropertyV1(
                name: "muted",
                required: true,
                schema: .boolean()
            ),
        ])
        let descriptor = try! CapabilityDiscoveryDescriptorV1(
            CapabilityDescriptorV1(
                capabilityID: "maccompanion.system.setAudioMuted",
                schemaVersion: 1,
                providerID: "maccompanion.native.audio",
                providerVersion: "1.0.0",
                providerGeneration: UUID(
                    uuidString: "018f8300-0000-7000-8000-000000000001"
                )!,
                executionRevision: UUID(
                    uuidString: "018f8400-0000-7000-8000-000000000001"
                )!,
                englishTitle: "Set audio mute",
                englishSummary: "Set the default audio output to muted or unmuted.",
                parameterSchema: parameters,
                resultSchema: parameters,
                effects: CapabilityEffectFacts(
                    dataAccess: .none,
                    changesLocalState: .reversible,
                    mayDisruptUser: false,
                    invokesExternalService: false,
                    usesCredentials: false,
                    destructive: false,
                    requiresForegroundSession: false,
                    allowedWhileLocked: false,
                    cancellation: .notApplicable
                )
            )
        )
        return GrantedCapabilityCatalogV1(
            registryGeneration: WireUUID(UUID(
                uuidString: "018f8500-0000-7000-8000-000000000001"
            )!),
            grantRevision: 1,
            policyRevision: 1,
            capabilities: [descriptor]
        )
    }()

    static let observeProjection: ClientObserveWorkspaceProjectionV0 = {
        let system = try! SystemOverview(
            osName: "macOS",
            osVersion: "26.0",
            osBuild: "25A100",
            uptimeSeconds: 86_400,
            cpuUtilizationBasisPoints: 1_250,
            memoryTotalBytes: 16_000_000_000,
            memoryUsedBytes: 8_000_000_000,
            storageTotalBytes: 1_000_000_000_000,
            storageAvailableBytes: 400_000_000_000,
            powerSource: .ac,
            batteryLevelPercent: 80
        )
        let status = ClientObservedStatusV0(
            snapshot: try! StatusSnapshotBody(
                hostID: WireUUID(hostID),
                generation: WireUUID(UUID(
                    uuidString: "018fa900-0000-7000-8000-000000000001"
                )!),
                revision: 3,
                observedAtUnixMilliseconds: 1_725_000_000_000,
                validForMilliseconds: 5_000,
                hostState: .userSessionActive,
                system: system
            ),
            freshness: try! ObservationFreshness(
                observedAtUnixMilliseconds: 1_725_000_000_000,
                responseSentAtUnixMilliseconds: 1_725_000_000_100,
                requestStartedAtMonotonicMilliseconds: 1_000,
                receivedAtMonotonicMilliseconds: 1_100,
                validForMilliseconds: 5_000
            )
        )
        let event = try! AuditSelfEventWireV1(
            sequence: 2,
            eventID: WireUUID(UUID(
                uuidString: "018fa900-0000-7000-8000-000000000002"
            )!),
            observedAtUnixMilliseconds: 1_725_000_000_000,
            scope: .selfDevice,
            actor: .agent,
            code: .operationCompleted,
            capabilityID: "maccompanion.system.setAudioMuted",
            outcome: .succeeded
        )
        let page = try! AuditListResponseBodyV1(
            events: [event],
            nextBeforeSequence: nil,
            oldestVisibleSequence: 1,
            newestVisibleSequence: 2,
            gaps: AuditGapWireV1(
                prunedThroughSequence: 1,
                droppedEventCount: 1
            )
        )
        return try! ClientObserveWorkspaceProjectionV0(
            macName: "Studio Mac",
            observedStatus: status,
            reachability: .reachable,
            monotonicNowMilliseconds: 1_200,
            latestActivityPage: page
        )
    }()

    static func hostSnapshot(
        _ sample: HarnessHostSample
    ) -> InteractiveClientPresentationSnapshot {
        let connection: ConnectionPresentationState
        let session: InteractiveSessionState?
        let classes: Set<SurfaceInteractionClass>
        let surface: InteractiveSurfaceKind?
        let cause: InteractiveRecoveryPresentationCause?

        switch sample {
        case .ready:
            connection = .connected
            session = nil
            classes = []
            surface = nil
            cause = nil
        case .approvalRequired:
            connection = .connected
            session = .approvalRequired
            classes = []
            surface = nil
            cause = nil
        case .controllingApplication:
            connection = .connected
            session = .activeUnlocked
            classes = [.view, .pointer, .keyboard, .text]
            surface = .application
            cause = nil
        case .lockedInteractionUnavailable:
            connection = .connected
            session = .lockedInteractionUnavailable
            classes = []
            surface = nil
            cause = .hostStateAmbiguous
        case .background:
            connection = .background
            session = nil
            classes = []
            surface = nil
            cause = .background
        case .noNetwork:
            connection = .noNetwork
            session = nil
            classes = []
            surface = nil
            cause = .noNetwork
        }

        return try! InteractiveClientPresentationSnapshot.make(
            hostID: hostID,
            locallyConfirmedMacName: try! DeviceDisplayName("Studio Mac"),
            endpointKind: .dns,
            connection: connection,
            sessionState: session,
            interactionClasses: classes,
            activeSurface: surface,
            recoveryCause: cause
        )
    }

    static let surfaceCandidates: [InteractiveSurfaceTargetCandidateV0] = {
        let notes = WireUUID(UUID(uuidString: "018f8000-0000-7000-8000-000000000001")!)
        let browser = WireUUID(UUID(uuidString: "018f8000-0000-7000-8000-000000000002")!)
        return [
            try! InteractiveSurfaceTargetCandidateV0(
                targetToken: notes,
                kind: .application,
                applicationToken: notes,
                applicationName: "Notes",
                windowOrdinal: nil,
                currentWindowAvailable: true
            ),
            try! InteractiveSurfaceTargetCandidateV0(
                targetToken: WireUUID(UUID(uuidString: "018f8100-0000-7000-8000-000000000001")!),
                kind: .window,
                applicationToken: browser,
                applicationName: "Safari",
                windowOrdinal: 1,
                currentWindowAvailable: true
            ),
            try! InteractiveSurfaceTargetCandidateV0(
                targetToken: WireUUID(UUID(uuidString: "018f8100-0000-7000-8000-000000000002")!),
                kind: .window,
                applicationToken: browser,
                applicationName: "Safari",
                windowOrdinal: 2,
                currentWindowAvailable: false
            ),
        ]
    }()
}

enum HarnessHostSample: String, CaseIterable, Identifiable {
    case ready = "Ready"
    case approvalRequired = "Approval"
    case controllingApplication = "Controlling"
    case lockedInteractionUnavailable = "Locked"
    case background = "Background"
    case noNetwork = "No Network"

    var id: String { rawValue }
}
