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

private actor RuntimeOwnerAdmissionV1:
    InteractiveSessionAdmissionReadingV0
{
    private var snapshots: [InteractiveSessionAdmissionSnapshotV0?]

    init(_ snapshots: [InteractiveSessionAdmissionSnapshotV0?]) {
        self.snapshots = snapshots
    }

    func snapshot(deviceID _: UUID) async throws
        -> InteractiveSessionAdmissionSnapshotV0? {
        guard !snapshots.isEmpty else { return nil }
        return snapshots.removeFirst()
    }
}

private actor RuntimeOwnerDesktopV1:
    AgentInteractiveInitialDesktopPreparingV1
{
    let descriptor: AdaptiveSurfaceDescriptor
    private var requestsStorage: [AgentInteractiveInitialDesktopRequestV1] = []

    init(descriptor: AdaptiveSurfaceDescriptor) {
        self.descriptor = descriptor
    }

    func prepareInitialDesktop(
        _ request: AgentInteractiveInitialDesktopRequestV1
    ) async throws -> AdaptiveSurfaceDescriptor {
        requestsStorage.append(request)
        return descriptor
    }

    func requests() -> [AgentInteractiveInitialDesktopRequestV1] {
        requestsStorage
    }
}

private actor RuntimeOwnerMenuRouteV1:
    AgentInteractiveMenuRuntimeRoutingV1
{
    let wrongGeneration: Bool
    private var installsStorage: [InteractiveRuntimeInstallCommandV0] = []
    private var renewalsStorage: [InteractiveRuntimeLeaseRenewalV0] = []
    private var revokesStorage: [InteractiveRuntimeRevokeCommandV0] = []

    init(wrongGeneration: Bool = false) {
        self.wrongGeneration = wrongGeneration
    }

    func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        installsStorage.append(command)
        return try InteractiveRuntimeInstallReceiptV0(
            correlationID: command.commandID,
            leaseID: command.lease.leaseID,
            interactiveSessionID: command.lease.interactiveSessionID,
            selectedDisplayID: command.lease.selectedDisplayID,
            menuAppGeneration: wrongGeneration
                ? UUID() : initialMenuGeneration,
            menuAppRevision: 9,
            readyInteractionClasses:
                Set(command.lease.allowedInteractionClasses),
            indicatorVisible: true
        )
    }

    func renewInteractiveLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0
    ) async throws {
        renewalsStorage.append(renewal)
    }

    func revokeInteractiveLease(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        revokesStorage.append(command)
        return try InteractiveRuntimeRevokedReceiptV0(
            correlationID: command.commandID,
            leaseID: command.leaseID,
            interactiveSessionID: command.interactiveSessionID,
            inputReleased: true,
            captureStopped: true,
            lastFrameBlanked: true,
            indicatorCleared: true
        )
    }

    func installs() -> [InteractiveRuntimeInstallCommandV0] {
        installsStorage
    }

    func revokes() -> [InteractiveRuntimeRevokeCommandV0] {
        revokesStorage
    }

    func renewals() -> [InteractiveRuntimeLeaseRenewalV0] {
        renewalsStorage
    }
}

private final class RuntimeOwnerIdentifiersV1: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]

    init(_ values: [UUID]) { self.values = values }

    func next() -> UUID {
        lock.withLock { values.removeFirst() }
    }
}

private final class RuntimeOwnerClockV1: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UInt64]

    init(_ values: [UInt64]) { self.values = values }

    func now() -> UInt64 {
        lock.withLock { values.removeFirst() }
    }
}

@Test func agentRuntimeOwnerRevalidatesInstallsAndRevokesExactly()
    async throws
{
    let requirement = try initialRequirement()
    let admission = RuntimeOwnerAdmissionV1([
        requirement.admission, requirement.admission,
        requirement.admission,
    ])
    let desktop = RuntimeOwnerDesktopV1(descriptor: try initialDesktop())
    let route = RuntimeOwnerMenuRouteV1()
    let commandID = UUID()
    let leaseID = UUID()
    let replacementLeaseID = UUID()
    let renewalCommandID = UUID()
    let revokeID = UUID()
    let identifiers = RuntimeOwnerIdentifiersV1([
        commandID, leaseID, replacementLeaseID, renewalCommandID,
        revokeID,
    ])
    let clock = RuntimeOwnerClockV1([
        2_000_000_000, 2_100_000_000,
    ])
    let owner = AgentInteractiveRuntimeOwnerV1(
        admission: admission,
        desktop: desktop,
        runtime: route,
        monotonicNowNanoseconds: { clock.now() },
        identifier: { identifiers.next() }
    )

    try await owner.install(
        initialBootstrap(),
        requirement: requirement
    )
    let installs = await route.installs()
    #expect(installs.count == 1)
    #expect(installs.first?.commandID == commandID)
    #expect(installs.first?.lease.leaseID == leaseID)
    #expect(await owner.state() == .active(
        interactiveSessionID: initialSessionID,
        leaseID: leaseID
    ))

    _ = try await owner.renewActiveLease(
        nowMonotonicNanoseconds: 5_000_000_000
    )
    let renewals = await route.renewals()
    #expect(renewals.count == 1)
    #expect(renewals.first?.commandID == renewalCommandID)
    #expect(renewals.first?.previousLeaseID == leaseID)
    #expect(renewals.first?.replacement.leaseID == replacementLeaseID)
    #expect(renewals.first?.replacement.renewalCounter == 1)
    #expect(await owner.state() == .active(
        interactiveSessionID: initialSessionID,
        leaseID: replacementLeaseID
    ))

    await owner.terminate(
        interactiveSessionID: initialSessionID,
        primaryConnectionID: initialConnectionID,
        reason: .clientDisconnected
    )
    let revokes = await route.revokes()
    #expect(revokes.count == 1)
    #expect(revokes.first?.commandID == revokeID)
    #expect(revokes.first?.leaseID == replacementLeaseID)
    #expect(revokes.first?.reason == .clientDisconnected)
    #expect(await owner.state() == .idle)
}

@Test func agentRuntimeOwnerRejectsAdmissionChangeBeforeRuntimeSend()
    async throws
{
    let requirement = try initialRequirement()
    let admission = RuntimeOwnerAdmissionV1([
        requirement.admission, nil,
    ])
    let desktop = RuntimeOwnerDesktopV1(descriptor: try initialDesktop())
    let route = RuntimeOwnerMenuRouteV1()
    let clock = RuntimeOwnerClockV1([2_000_000_000])
    let owner = AgentInteractiveRuntimeOwnerV1(
        admission: admission,
        desktop: desktop,
        runtime: route,
        monotonicNowNanoseconds: { clock.now() }
    )

    await #expect(
        throws: AgentInteractiveRuntimeOwnerErrorV1.finalAdmissionChanged
    ) {
        try await owner.install(
            initialBootstrap(),
            requirement: requirement
        )
    }
    #expect(await route.installs().isEmpty)
    #expect(await owner.state() == .idle)
}

@Test func agentRuntimeOwnerCompensatesMismatchedMenuReceipt() async throws {
    let requirement = try initialRequirement()
    let admission = RuntimeOwnerAdmissionV1([
        requirement.admission, requirement.admission,
    ])
    let desktop = RuntimeOwnerDesktopV1(descriptor: try initialDesktop())
    let route = RuntimeOwnerMenuRouteV1(wrongGeneration: true)
    let identifiers = RuntimeOwnerIdentifiersV1([UUID(), UUID(), UUID()])
    let clock = RuntimeOwnerClockV1([
        2_000_000_000, 2_100_000_000,
    ])
    let owner = AgentInteractiveRuntimeOwnerV1(
        admission: admission,
        desktop: desktop,
        runtime: route,
        monotonicNowNanoseconds: { clock.now() },
        identifier: { identifiers.next() }
    )

    await #expect(
        throws: AgentInteractiveRuntimeOwnerErrorV1.runtimeReceiptRejected
    ) {
        try await owner.install(
            initialBootstrap(),
            requirement: requirement
        )
    }
    #expect(await route.revokes().count == 1)
    #expect(await owner.state() == .idle)
}

private enum RenewalSchedulerProbeErrorV1: Error {
    case stop
    case renewalFailed
}

private actor RenewalSchedulerRuntimeV1:
    AgentInteractiveLeaseRenewingRuntimeV1
{
    enum RenewalResult: Sendable {
        case replacement(InteractiveExecutionLease)
        case failure
    }

    private let initialLease: InteractiveExecutionLease
    private let renewalResult: RenewalResult
    private var installCountStorage = 0
    private var renewalSamplesStorage: [UInt64] = []
    private var terminationsStorage: [InteractiveSessionEndReason] = []

    init(
        initialLease: InteractiveExecutionLease,
        renewalResult: RenewalResult
    ) {
        self.initialLease = initialLease
        self.renewalResult = renewalResult
    }

    func install(
        _: InteractiveSessionBootstrap,
        requirement _: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        installCountStorage += 1
    }

    func activeLeaseForScheduling() -> InteractiveExecutionLease? {
        initialLease
    }

    func renewActiveLease(
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveExecutionLease {
        renewalSamplesStorage.append(nowMonotonicNanoseconds)
        switch renewalResult {
        case .replacement(let replacement):
            return replacement
        case .failure:
            throw RenewalSchedulerProbeErrorV1.renewalFailed
        }
    }

    func terminate(
        interactiveSessionID _: UUID,
        primaryConnectionID _: Data,
        reason: InteractiveSessionEndReason
    ) async {
        terminationsStorage.append(reason)
    }

    func installCount() -> Int { installCountStorage }
    func renewalSamples() -> [UInt64] { renewalSamplesStorage }
    func terminations() -> [InteractiveSessionEndReason] {
        terminationsStorage
    }
}

private actor RenewalSchedulerSleeperV1 {
    private let successfulCalls: Int
    private var delaysStorage: [UInt64] = []

    init(successfulCalls: Int) {
        self.successfulCalls = successfulCalls
    }

    func sleep(nanoseconds: UInt64) async throws {
        delaysStorage.append(nanoseconds)
        if delaysStorage.count > successfulCalls {
            throw RenewalSchedulerProbeErrorV1.stop
        }
    }

    func delays() -> [UInt64] { delaysStorage }
}

private func schedulerLease(
    leaseID: UUID = UUID(),
    selectedDisplayID: UUID = initialDisplayID,
    renewalCounter: UInt64,
    issuedAt: UInt64,
    expiresAt: UInt64
) throws -> InteractiveExecutionLease {
    try InteractiveExecutionLease(
        leaseID: leaseID,
        hostID: initialHostID,
        deviceID: initialDeviceID,
        interactiveSessionID: initialSessionID,
        authorizationEpoch: .init(rawValue: 4),
        selectedDisplayID: selectedDisplayID,
        surfaceID: initialSurfaceID,
        surfaceRevision: .init(rawValue: 1),
        coordinateRevision: .init(rawValue: 1),
        allowedInteractionClasses: [.view, .pointer],
        renewalCounter: renewalCounter,
        issuedAtMonotonicNanoseconds: issuedAt,
        expiresAtMonotonicNanoseconds: expiresAt
    )
}

@Test func interactiveLeaseSchedulerRenewsOnceFromReturnedDeadline()
    async throws
{
    let initial = try schedulerLease(
        renewalCounter: 0,
        issuedAt: 2_000_000_000,
        expiresAt: 12_000_000_000
    )
    let replacement = try schedulerLease(
        renewalCounter: 1,
        issuedAt: 10_000_000_000,
        expiresAt: 20_000_000_000
    )
    let runtime = RenewalSchedulerRuntimeV1(
        initialLease: initial,
        renewalResult: .replacement(replacement)
    )
    let clock = RuntimeOwnerClockV1([
        2_000_000_000, 10_000_000_000, 10_000_000_000,
    ])
    let sleeper = RenewalSchedulerSleeperV1(successfulCalls: 1)
    let owner = AgentInteractiveLeaseRenewalOwnerV1(
        runtime: runtime,
        monotonicNowNanoseconds: { clock.now() },
        sleep: { try await sleeper.sleep(nanoseconds: $0) }
    )

    try await owner.install(
        initialBootstrap(),
        requirement: initialRequirement()
    )
    for _ in 0..<100 where await runtime.renewalSamples().isEmpty {
        await Task.yield()
    }

    #expect(await runtime.installCount() == 1)
    #expect(await runtime.renewalSamples() == [10_000_000_000])
    #expect(await sleeper.delays().first == 8_000_000_000)

    await owner.terminate(
        interactiveSessionID: initialSessionID,
        primaryConnectionID: initialConnectionID,
        reason: .clientDisconnected
    )
    #expect(await runtime.terminations() == [.clientDisconnected])
}

@Test func interactiveLeaseSchedulerNeverRetriesAmbiguousRenewal()
    async throws
{
    let initial = try schedulerLease(
        renewalCounter: 0,
        issuedAt: 2_000_000_000,
        expiresAt: 12_000_000_000
    )
    let runtime = RenewalSchedulerRuntimeV1(
        initialLease: initial,
        renewalResult: .failure
    )
    let clock = RuntimeOwnerClockV1([2_000_000_000, 10_000_000_000])
    let sleeper = RenewalSchedulerSleeperV1(successfulCalls: 1)
    let owner = AgentInteractiveLeaseRenewalOwnerV1(
        runtime: runtime,
        monotonicNowNanoseconds: { clock.now() },
        sleep: { try await sleeper.sleep(nanoseconds: $0) }
    )

    try await owner.install(
        initialBootstrap(),
        requirement: initialRequirement()
    )
    for _ in 0..<100 where await runtime.renewalSamples().isEmpty {
        await Task.yield()
    }
    for _ in 0..<20 { await Task.yield() }

    #expect(await runtime.renewalSamples() == [10_000_000_000])
    #expect(await sleeper.delays() == [8_000_000_000])

    await owner.terminate(
        interactiveSessionID: initialSessionID,
        primaryConnectionID: initialConnectionID,
        reason: .protocolViolation
    )
    #expect(await runtime.terminations() == [.protocolViolation])
}

@Test func interactiveLeaseSchedulerTerminatesStructurallyChangedLease()
    async throws
{
    let initial = try schedulerLease(
        renewalCounter: 0,
        issuedAt: 2_000_000_000,
        expiresAt: 12_000_000_000
    )
    let changed = try schedulerLease(
        selectedDisplayID: UUID(),
        renewalCounter: 1,
        issuedAt: 10_000_000_000,
        expiresAt: 20_000_000_000
    )
    let runtime = RenewalSchedulerRuntimeV1(
        initialLease: initial,
        renewalResult: .replacement(changed)
    )
    let clock = RuntimeOwnerClockV1([2_000_000_000, 10_000_000_000])
    let sleeper = RenewalSchedulerSleeperV1(successfulCalls: 1)
    let owner = AgentInteractiveLeaseRenewalOwnerV1(
        runtime: runtime,
        monotonicNowNanoseconds: { clock.now() },
        sleep: { try await sleeper.sleep(nanoseconds: $0) }
    )

    try await owner.install(
        initialBootstrap(),
        requirement: initialRequirement()
    )
    for _ in 0..<100 where await runtime.terminations().isEmpty {
        await Task.yield()
    }

    #expect(await runtime.renewalSamples() == [10_000_000_000])
    #expect(await runtime.terminations() == [.protocolViolation])
}
