import CompanionAgent
import CompanionDomain
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionIPC
import CompanionSecurity
import CryptoKit
import Foundation
import Testing

private let initialHostID = UUID(
    uuidString: "019c1000-0000-7000-8000-000000000001"
)!
private let initialClientID = UUID(
    uuidString: "019c2000-0000-7000-8000-000000000001"
)!
private let initialDeviceID = UUID(
    uuidString: "019c2100-0000-7000-8000-000000000001"
)!
private let initialRequestID = UUID(
    uuidString: "019c6500-0000-7000-8000-000000000001"
)!
private let initialApprovalID = UUID(
    uuidString: "019c6600-0000-7000-8000-000000000001"
)!
private let initialDisplayID = UUID(
    uuidString: "019c6700-0000-7000-8000-000000000001"
)!
private let initialSessionID = UUID(
    uuidString: "019c6000-0000-7000-8000-000000000001"
)!
private let initialSurfaceID = UUID(
    uuidString: "019c6100-0000-7000-8000-000000000001"
)!
private let initialMenuGeneration = UUID(
    uuidString: "019c3000-0000-7000-8000-000000000001"
)!
private let initialConnectionID = Data((0x00..<0x10).map(UInt8.init))
private let initialFingerprint = Data((0x80..<0xa0).map(UInt8.init))
private let initialChallenge = Data((0x30..<0x50).map(UInt8.init))

private func initialApprovalKey() throws -> P256.Signing.PrivateKey {
    var scalar = Data(repeating: 0, count: 32)
    scalar[31] = 7
    return try P256.Signing.PrivateKey(rawRepresentation: scalar)
}

private func initialBootstrap() throws -> InteractiveSessionBootstrap {
    let approvalKey = try initialApprovalKey()
    let authority = try InteractiveApprovalAuthority(
        hostID: initialHostID,
        hostFingerprint: initialFingerprint,
        clientID: initialClientID,
        primaryConnectionID: initialConnectionID,
        requestID: initialRequestID,
        approvalID: initialApprovalID,
        serverChallenge: initialChallenge,
        authorizationEpoch: 4,
        grantRevision: 5,
        policyRevision: 6,
        selectedDisplayID: initialDisplayID,
        initialSurface: .desktop,
        effects: [.view, .pointer],
        issuedAtUnixMilliseconds: 1_724_000_000_000,
        expiresAtUnixMilliseconds: 1_724_000_060_000,
        approvalPublicKeyX963: approvalKey.publicKey.x963Representation,
        issuedAtMonotonicMilliseconds: 1_000,
        expiresAtMonotonicMilliseconds: 61_000
    )
    let signingInput = try CompanionSecurityV0
        .interactiveApprovalSigningInput(
            hostID: initialHostID,
            hostFingerprint: initialFingerprint,
            clientID: initialClientID,
            primaryConnectionID: initialConnectionID,
            requestID: initialRequestID,
            approvalID: initialApprovalID,
            serverChallenge: initialChallenge,
            authorizationEpoch: 4,
            grantRevision: 5,
            policyRevision: 6,
            selectedDisplayID: initialDisplayID,
            initialSurface: .desktop,
            effects: [.view, .pointer],
            issuedAtUnixMilliseconds: 1_724_000_000_000,
            expiresAtUnixMilliseconds: 1_724_000_060_000,
            selectedMajor: 0,
            selectedMinor: 1
        )
    var bootstrapAuthority = InteractiveSessionBootstrapAuthority(
        approvalAuthority: authority
    )
    return try bootstrapAuthority.verifyAndCreate(
        rawApprovalSignature: approvalKey.signature(
            for: signingInput
        ).rawRepresentation,
        current: InteractiveApprovalCurrentState(
            clientID: initialClientID,
            primaryConnectionID: initialConnectionID,
            authorizationEpoch: 4,
            grantRevision: 5,
            policyRevision: 6,
            approvalPublicKeyX963:
                approvalKey.publicKey.x963Representation
        ),
        materials: InteractiveSessionBootstrapMaterials(
            interactiveSessionID: initialSessionID,
            inputChannelID: UUID(),
            inputCredential: Data(repeating: 1, count: 32),
            mediaChannelID: UUID(),
            mediaCredential: Data(repeating: 2, count: 32)
        ),
        wallNowUnixMilliseconds: 1_724_000_010_000,
        monotonicNowMilliseconds: 2_000
    )
}

private func initialRequirement() throws
    -> InteractiveSessionRuntimeRequirementV0 {
    let approvalKey = try initialApprovalKey()
    return InteractiveSessionRuntimeRequirementV0(
        command: try InteractiveSessionCommandContextV0(
            deviceID: initialDeviceID,
            clientID: initialClientID,
            deviceState: .activeGranted,
            authorizationEpoch: .init(rawValue: 4),
            grantRevision: .init(rawValue: 5),
            policyRevision: .init(rawValue: 6),
            primaryConnectionID: initialConnectionID,
            hostID: initialHostID,
            hostFingerprint: initialFingerprint,
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 1_724_000_010_000,
            monotonicNowMilliseconds: 2_000
        ),
        admission: try InteractiveSessionAdmissionSnapshotV0(
            deviceID: initialDeviceID,
            clientID: initialClientID,
            deviceState: .activeGranted,
            authorizationEpoch: .init(rawValue: 4),
            grantRevision: .init(rawValue: 5),
            policyRevision: .init(rawValue: 6),
            approvalPublicKeyX963:
                approvalKey.publicKey.x963Representation,
            grants: CapabilityGrantSet([
                InteractiveControlCapabilityV0.identifier,
            ]),
            deviceDisplayName: DeviceDisplayName("Jenny’s iPhone"),
            visibleMenuAppAvailable: true,
            visibleMenuAppGeneration: initialMenuGeneration,
            visibleMenuAppRevision: 9,
            selectedDisplayID: initialDisplayID
        )
    )
}

@Test func inertInteractiveRuntimeRejectsInstallAndTerminatesIdempotently()
    async throws
{
    let services = AgentInteractivePlatformServicesV1.inertUnavailable()
    await #expect(
        throws: AgentInertInteractivePlatformErrorV1.unavailable
    ) {
        try await services.runtime.install(
            initialBootstrap(),
            requirement: initialRequirement()
        )
    }
    await services.runtime.terminate(
        interactiveSessionID: initialSessionID,
        primaryConnectionID: initialConnectionID,
        reason: .localSuspension
    )
    await services.runtime.terminate(
        interactiveSessionID: initialSessionID,
        primaryConnectionID: initialConnectionID,
        reason: .localSuspension
    )
}

private func initialDesktop(
    classes: Set<SurfaceInteractionClass> = [.view, .pointer],
    expiresAtMilliseconds: Int64 = 20_000
) throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: initialSessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: initialSurfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: 1),
        coordinateSpaceRevision: .init(rawValue: 1),
        encodedWidth: 1_280,
        encodedHeight: 720,
        logicalWidthPoints: 1_280,
        logicalHeightPoints: 720,
        interactionClasses: classes,
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 2_000,
        expiresAtMonotonicMilliseconds: expiresAtMilliseconds
    )
}

private func initialReceipt(
    _ preparation: InteractiveInitialRuntimePreparationV1,
    generation: UUID = initialMenuGeneration,
    revision: UInt64 = 9
) throws -> InteractiveRuntimeInstallReceiptV0 {
    try InteractiveRuntimeInstallReceiptV0(
        correlationID: preparation.command.commandID,
        leaseID: preparation.command.lease.leaseID,
        interactiveSessionID:
            preparation.command.lease.interactiveSessionID,
        selectedDisplayID: preparation.command.lease.selectedDisplayID,
        menuAppGeneration: generation,
        menuAppRevision: revision,
        readyInteractionClasses:
            Set(preparation.command.lease.allowedInteractionClasses),
        indicatorVisible: true
    )
}

@Test func initialRuntimePreparationBindsApprovedEffectsAndTransfersOnce() throws {
    var authority = try InteractiveInitialRuntimeCommandAuthorityV1(
        bootstrap: initialBootstrap(),
        requirement: initialRequirement(),
        desktop: initialDesktop()
    )
    let commandID = UUID()
    let leaseID = UUID()
    let prepared = try authority.prepare(
        commandID: commandID,
        leaseID: leaseID,
        nowMonotonicNanoseconds: 2_000_000_000
    )
    let replay = try authority.prepare(
        commandID: commandID,
        leaseID: leaseID,
        nowMonotonicNanoseconds: 2_000_000_000
    )

    #expect(replay == prepared)
    #expect(prepared.command.lease.hostID == initialHostID)
    #expect(prepared.command.lease.deviceID == initialDeviceID)
    #expect(prepared.command.lease.selectedDisplayID == initialDisplayID)
    #expect(prepared.command.lease.allowedInteractionClasses == [.pointer, .view])
    #expect(prepared.command.lease.renewalCounter == 0)
    #expect(prepared.command.lease.expiresAtMonotonicNanoseconds
        == 12_000_000_000)

    let receipt = try initialReceipt(prepared, revision: 10)
    try authority.accept(
        receipt,
        nowMonotonicNanoseconds: 2_100_000_000
    )
    try authority.accept(
        receipt,
        nowMonotonicNanoseconds: 2_100_000_000
    )
    let installed = try authority.takeInstalledBootstrap()
    #expect(installed.session.state == .activeUnlocked)
    #expect(installed.approvedInteractionClasses == [.view, .pointer])
    #expect(authority.state == .transferred)
    #expect(throws: InteractiveInitialRuntimeCommandErrorV1.invalidState(
        .transferred
    )) {
        _ = try authority.takeInstalledBootstrap()
    }
}

@Test func initialRuntimePreparationUsesEarliestDescriptorDeadline() throws {
    var authority = try InteractiveInitialRuntimeCommandAuthorityV1(
        bootstrap: initialBootstrap(),
        requirement: initialRequirement(),
        desktop: initialDesktop(expiresAtMilliseconds: 5_000)
    )
    let prepared = try authority.prepare(
        commandID: UUID(),
        leaseID: UUID(),
        nowMonotonicNanoseconds: 2_000_000_000
    )
    #expect(prepared.command.lease.expiresAtMonotonicNanoseconds
        == 5_000_000_000)
}

@Test func initialRuntimeReceiptFromAnotherMenuGenerationRequiresTeardown() throws {
    var authority = try InteractiveInitialRuntimeCommandAuthorityV1(
        bootstrap: initialBootstrap(),
        requirement: initialRequirement(),
        desktop: initialDesktop()
    )
    let prepared = try authority.prepare(
        commandID: UUID(),
        leaseID: UUID(),
        nowMonotonicNanoseconds: 2_000_000_000
    )
    #expect(throws: InteractiveInitialRuntimeCommandErrorV1.receiptRejected) {
        try authority.accept(
            initialReceipt(prepared, generation: UUID()),
            nowMonotonicNanoseconds: 2_100_000_000
        )
    }
    #expect(authority.state == .teardownRequired)
    #expect(throws: InteractiveInitialRuntimeCommandErrorV1.invalidState(
        .teardownRequired
    )) {
        _ = try authority.takeInstalledBootstrap()
    }
}

@Test func initialRuntimePreparationRejectsDescriptorAuthorityWidening() throws {
    #expect(throws: InteractiveInitialRuntimeCommandErrorV1.invalidBinding) {
        _ = try InteractiveInitialRuntimeCommandAuthorityV1(
            bootstrap: initialBootstrap(),
            requirement: initialRequirement(),
            desktop: initialDesktop(
                classes: [.view, .pointer, .keyboard]
            )
        )
    }
}
