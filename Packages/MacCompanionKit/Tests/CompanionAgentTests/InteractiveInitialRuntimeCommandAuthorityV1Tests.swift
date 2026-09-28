@testable import CompanionAgent
import CompanionDomain
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionIPC
import CompanionSecurity
import CompanionWire
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

private actor RuntimeBindingProbeV1: InteractiveSessionRuntimeOwningV0 {
    private var installCountStorage = 0
    private var terminationsStorage: [(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    )] = []

    func install(
        _: InteractiveSessionBootstrap,
        requirement _: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        installCountStorage += 1
    }

    func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {
        terminationsStorage.append((
            interactiveSessionID,
            primaryConnectionID,
            reason
        ))
    }

    func installCount() -> Int { installCountStorage }
    func terminationReasons() -> [InteractiveSessionEndReason] {
        terminationsStorage.map(\.reason)
    }
}

private actor RuntimeBindingDisplayProbeV1:
    InteractiveDisplaySelectionDispatchingV1
{
    private var catalogCountStorage = 0

    func displayCatalog(
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveDisplayCatalogResponseBodyV1 {
        catalogCountStorage += 1
        return try InteractiveDisplayCatalogResponseBodyV1(
            authorizationEpoch: context.authorizationEpoch,
            admissionRevision: 9,
            selectedDisplayID: WireUUID(initialDisplayID),
            validForMilliseconds: 5_000,
            displays: [try InteractiveDisplayCandidateV1(
                displayID: WireUUID(initialDisplayID),
                ordinal: 1,
                pixelWidth: 2_560,
                pixelHeight: 1_067,
                layoutX: 0,
                layoutY: 0,
                layoutWidth: 2_560,
                layoutHeight: 1_067,
                isMain: true
            )]
        )
    }

    func selectDisplay(
        _ request: InteractiveDisplaySelectBodyV1,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveDisplaySelectedBodyV1 {
        try InteractiveDisplaySelectedBodyV1(
            authorizationEpoch: context.authorizationEpoch,
            admissionRevision: request.expectedAdmissionRevision + 1,
            selectedDisplayID: request.displayID
        )
    }

    func catalogCount() -> Int { catalogCountStorage }
}

@Test func runtimeBindingAuthorityIsUnavailableUntilExactGenerationBinds()
    async throws
{
    let authority = AgentInteractiveRuntimeBindingAuthorityV1()

    await #expect(
        throws: AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable
    ) {
        try await authority.install(
            initialBootstrap(),
            requirement: initialRequirement()
        )
    }
    await #expect(
        throws:
            AgentInteractiveRuntimeBindingAuthorityErrorV1
                .invalidGeneration
    ) {
        try await authority.bind(
            runtime: RuntimeBindingProbeV1(),
            generation: 0
        )
    }
    #expect(await authority.state() == .unavailable)
}

@Test func runtimeBindingAuthorityTerminatesBeforeGenerationReplacement()
    async throws
{
    let authority = AgentInteractiveRuntimeBindingAuthorityV1()
    let first = RuntimeBindingProbeV1()
    let second = RuntimeBindingProbeV1()
    try await authority.bind(runtime: first, generation: 7)
    try await authority.install(
        initialBootstrap(),
        requirement: initialRequirement()
    )

    #expect(await first.installCount() == 1)
    #expect(await authority.state() == .active(
        generation: 7,
        interactiveSessionID: initialSessionID
    ))
    #expect(await authority.invalidate(generation: 6) == false)
    #expect(await authority.invalidate(generation: 7))
    #expect(await first.terminationReasons() == [.menuAppUnavailable])
    #expect(await authority.state() == .unavailable)

    await #expect(
        throws:
            AgentInteractiveRuntimeBindingAuthorityErrorV1
                .staleGeneration(7)
    ) {
        try await authority.bind(runtime: second, generation: 7)
    }
    try await authority.bind(runtime: second, generation: 8)
    #expect(await authority.state() == .bound(generation: 8))
}

@Test func runtimeBindingAuthorityServesCatalogForExactActivePrimary()
    async throws
{
    let authority = AgentInteractiveRuntimeBindingAuthorityV1()
    let runtime = RuntimeBindingProbeV1()
    let displays = RuntimeBindingDisplayProbeV1()
    let requirement = try initialRequirement()
    try await authority.bind(
        runtime: runtime,
        channelAuthenticator: nil,
        displayControl: displays,
        generation: 1
    )

    _ = try await authority.displayCatalog(context: requirement.command)
    try await authority.install(
        initialBootstrap(),
        requirement: requirement
    )
    _ = try await authority.displayCatalog(context: requirement.command)

    let foreignPrimary = try InteractiveSessionCommandContextV0(
        deviceID: initialDeviceID,
        clientID: initialClientID,
        deviceState: .activeGranted,
        authorizationEpoch: .init(rawValue: 4),
        grantRevision: .init(rawValue: 5),
        policyRevision: .init(rawValue: 6),
        primaryConnectionID: Data(repeating: 0xff, count: 16),
        hostID: initialHostID,
        hostFingerprint: initialFingerprint,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 1_724_000_010_000,
        monotonicNowMilliseconds: 2_000
    )
    await #expect(
        throws: AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable
    ) {
        _ = try await authority.displayCatalog(context: foreignPrimary)
    }
    #expect(await displays.catalogCount() == 2)
}

@Test func runtimeBindingAuthorityExplicitTerminationAndFinishAreTerminal()
    async throws
{
    let authority = AgentInteractiveRuntimeBindingAuthorityV1()
    let runtime = RuntimeBindingProbeV1()
    try await authority.bind(runtime: runtime, generation: 1)
    try await authority.install(
        initialBootstrap(),
        requirement: initialRequirement()
    )
    await authority.terminate(
        interactiveSessionID: initialSessionID,
        primaryConnectionID: initialConnectionID,
        reason: .clientDisconnected
    )

    #expect(await runtime.terminationReasons() == [.clientDisconnected])
    #expect(await authority.state() == .bound(generation: 1))
    await authority.finish()
    await authority.finish()
    #expect(await authority.state() == .terminal)
    await #expect(
        throws: AgentInteractiveRuntimeBindingAuthorityErrorV1.terminal
    ) {
        try await authority.bind(
            runtime: RuntimeBindingProbeV1(),
            generation: 2
        )
    }
}

private func initialDesktop(
    classes: Set<SurfaceInteractionClass> = [.view, .pointer],
    createdAtMilliseconds: Int64 = 2_000,
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
        createdAtMonotonicMilliseconds: createdAtMilliseconds,
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
    let suspension: RuntimeInstallSuspensionV1?
    private var requestsStorage: [AgentInteractiveInitialDesktopRequestV1] = []

    init(descriptor: AdaptiveSurfaceDescriptor, suspension: RuntimeInstallSuspensionV1? = nil) {
        self.descriptor = descriptor
        self.suspension = suspension
    }

    func prepareInitialDesktop(
        _ request: AgentInteractiveInitialDesktopRequestV1
    ) async throws -> AdaptiveSurfaceDescriptor {
        requestsStorage.append(request)
        await suspension?.suspend()
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
    let suspension: RuntimeInstallSuspensionV1?
    private var installsStorage: [InteractiveRuntimeInstallCommandV0] = []
    private var renewalsStorage: [InteractiveRuntimeLeaseRenewalV0] = []
    private var revokesStorage: [InteractiveRuntimeRevokeCommandV0] = []

    init(wrongGeneration: Bool = false, suspension: RuntimeInstallSuspensionV1? = nil) {
        self.wrongGeneration = wrongGeneration
        self.suspension = suspension
    }

    func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        installsStorage.append(command)
        await suspension?.suspend()
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

private actor RuntimeOwnerDisplayRouteV1:
    AgentInteractiveDisplayMenuRoutingV1
{
    func interactiveDisplayCatalog() async throws
        -> LocalInteractiveDisplayCatalogReceiptV1
    {
        try LocalInteractiveDisplayCatalogReceiptV1(
            correlationID: UUID(),
            selectedDisplayID: initialDisplayID,
            candidates: [try LocalInteractiveDisplayCandidateV1(
                displayID: initialDisplayID,
                ordinal: 1,
                pixelWidth: 2_560,
                pixelHeight: 1_067,
                layoutX: 0,
                layoutY: 0,
                layoutWidth: 2_560,
                layoutHeight: 1_067,
                isMain: true
            )]
        )
    }

    func selectInteractiveDisplay(_ displayID: UUID) async throws
        -> LocalInteractiveDisplaySelectedReceiptV1
    {
        LocalInteractiveDisplaySelectedReceiptV1(
            correlationID: UUID(),
            selectedDisplayID: displayID
        )
    }
}

private actor RuntimeInstallSuspensionV1 {
    private(set) var entered = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func suspend() async {
        entered = true
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@Test(arguments: [false, true], [false, true])
func pendingRuntimeTerminationFencesDesktopAndLateReceipt(wrapped: Bool, receiptSent: Bool) async throws {
    let requirement = try initialRequirement()
    let suspension = RuntimeInstallSuspensionV1()
    let route = RuntimeOwnerMenuRouteV1(suspension: receiptSent ? suspension : nil)
    let owner = AgentInteractiveRuntimeOwnerV1(
        admission: RuntimeOwnerAdmissionV1([requirement.admission, requirement.admission]),
        desktop: RuntimeOwnerDesktopV1(descriptor: try initialDesktop(), suspension: receiptSent ? nil : suspension),
        runtime: route, monotonicNowNanoseconds: { 2_000_000_000 })
    let runtime: any InteractiveSessionRuntimeOwningV0
    let binding = AgentInteractiveRuntimeBindingAuthorityV1()
    if wrapped {
        try await binding.bind(runtime: AgentInteractiveLeaseRenewalOwnerV1(runtime: owner), generation: 1)
        runtime = binding
    } else { runtime = owner }
    let install = Task { try await runtime.install(initialBootstrap(), requirement: requirement) }
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await suspension.entered), ContinuousClock.now < deadline { await Task.yield() }
    #expect(await suspension.entered)
    let termination = Task {
        await runtime.terminate(interactiveSessionID: initialSessionID,
            primaryConnectionID: initialConnectionID, reason: .clientDisconnected)
    }
    // Give the independent termination actor work a chance to reach its fence;
    // cleanup must remain pending until the suspended operation is released.
    for _ in 0..<100 { await Task.yield() }
    await suspension.release()
    let result = await install.result
    if case .success = result { Issue.record("A terminated pending install succeeded") }
    await termination.value
    #expect(await route.installs().count == (receiptSent ? 1 : 0))
    #expect(await route.revokes().count == (receiptSent ? 1 : 0))
    #expect(await owner.state() == .idle)
    #expect(await owner.activeLeaseForScheduling() == nil)
    if wrapped { #expect(await binding.state() == .bound(generation: 1)) }
}

@Test
func stalePendingRuntimeTerminationCannotCancelAnotherConnection() async throws {
    let requirement = try initialRequirement()
    let suspension = RuntimeInstallSuspensionV1()
    let route = RuntimeOwnerMenuRouteV1()
    let owner = AgentInteractiveRuntimeOwnerV1(
        admission: RuntimeOwnerAdmissionV1([requirement.admission, requirement.admission]),
        desktop: RuntimeOwnerDesktopV1(descriptor: try initialDesktop(), suspension: suspension),
        runtime: route, monotonicNowNanoseconds: { 2_000_000_000 })
    let binding = AgentInteractiveRuntimeBindingAuthorityV1()
    try await binding.bind(runtime: owner, generation: 1)
    let install = Task { try await binding.install(initialBootstrap(), requirement: requirement) }
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await suspension.entered), ContinuousClock.now < deadline { await Task.yield() }
    #expect(await suspension.entered)
    let stale = Task {
        await binding.terminate(interactiveSessionID: initialSessionID,
            primaryConnectionID: Data(repeating: 255, count: 16), reason: .clientDisconnected)
    }
    let wrongGeneration = Task { await binding.invalidate(generation: 2) }
    for _ in 0..<100 { await Task.yield() }
    await suspension.release()
    try await install.value
    await stale.value
    #expect(!(await wrongGeneration.value))
    #expect(await route.installs().count == 1)
    #expect(await route.revokes().isEmpty)
    #expect(await binding.state() == .active(generation: 1, interactiveSessionID: initialSessionID))
    await binding.finish()
    #expect(await owner.state() == .idle)
}

@Test(arguments: [false, true])
func pendingBindingLifecycleLossFencesPreparation(shutdown: Bool) async throws {
    let requirement = try initialRequirement()
    let suspension = RuntimeInstallSuspensionV1()
    let route = RuntimeOwnerMenuRouteV1()
    let owner = AgentInteractiveRuntimeOwnerV1(
        admission: RuntimeOwnerAdmissionV1([requirement.admission, requirement.admission]),
        desktop: RuntimeOwnerDesktopV1(descriptor: try initialDesktop(), suspension: suspension),
        runtime: route, monotonicNowNanoseconds: { 2_000_000_000 })
    let binding = AgentInteractiveRuntimeBindingAuthorityV1()
    try await binding.bind(runtime: AgentInteractiveLeaseRenewalOwnerV1(runtime: owner), generation: 1)
    let install = Task { try await binding.install(initialBootstrap(), requirement: requirement) }
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await suspension.entered), ContinuousClock.now < deadline { await Task.yield() }
    #expect(await suspension.entered)
    let retire = Task {
        if shutdown { await binding.finish() }
        else { #expect(await binding.invalidate(generation: 1)) }
    }
    for _ in 0..<100 { await Task.yield() }
    await suspension.release()
    if case .success = await install.result { Issue.record("Retired binding installed a pending session") }
    await retire.value
    #expect(await route.installs().isEmpty)
    #expect(await route.revokes().isEmpty)
    #expect(await owner.state() == .idle)
    #expect(await binding.state() == (shutdown ? .terminal : .unavailable))
}

private enum RuntimeOwnerSurfaceRouteErrorV1: Error { case unavailable }

private actor RuntimeOwnerSurfaceRouteV1:
    AgentInteractiveSurfaceMenuRoutingV1
{
    func prepareSurfaceTransition(
        _: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        throw RuntimeOwnerSurfaceRouteErrorV1.unavailable
    }

    func acknowledgeSurface(
        _: InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        throw RuntimeOwnerSurfaceRouteErrorV1.unavailable
    }

    func terminateSurfaceFailure(
        interactiveSessionID _: UUID,
        reason _: InteractiveSessionEndReason
    ) async throws -> Bool { true }

    func resolve(
        _: InteractiveSurfaceSelectBodyV0,
        context _: InteractiveSessionCommandContextV0
    ) async throws -> AdaptiveSurfaceDescriptor {
        throw RuntimeOwnerSurfaceRouteErrorV1.unavailable
    }

    func snapshot(
        _: InteractiveSurfaceTargetsRequestBodyV0,
        context _: InteractiveSessionCommandContextV0
    ) async throws -> AdaptiveSurfaceTargetInventorySnapshotV0 {
        throw RuntimeOwnerSurfaceRouteErrorV1.unavailable
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

@Test func activeRuntimeOwnerServesDisplayCatalogForItsLeaseBinding()
    async throws
{
    let requirement = try initialRequirement()
    let owner = AgentInteractiveRuntimeOwnerV1(
        admission: RuntimeOwnerAdmissionV1([
            requirement.admission,
            requirement.admission,
            requirement.admission,
        ]),
        desktop: RuntimeOwnerDesktopV1(descriptor: try initialDesktop()),
        runtime: RuntimeOwnerMenuRouteV1(),
        displayRuntime: RuntimeOwnerDisplayRouteV1(),
        monotonicNowNanoseconds: { 2_100_000_000 }
    )

    try await owner.install(initialBootstrap(), requirement: requirement)
    let catalog = try await owner.displayCatalog(
        context: requirement.command
    )

    #expect(catalog.authorizationEpoch == requirement.command.authorizationEpoch)
    #expect(catalog.admissionRevision == 9)
    #expect(catalog.selectedDisplayID.rawValue == initialDisplayID)
    #expect(catalog.displays.map(\.displayID.rawValue) == [initialDisplayID])
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
        2_000_000_000, 2_001_000_000, 2_100_000_000,
        6_000_000_000,
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

    let renewalResult = try await owner.renewActiveLease(
        nowMonotonicNanoseconds: 5_000_000_000
    )
    let renewals = await route.renewals()
    #expect(renewalResult.previous == installs.first?.lease)
    #expect(renewalResult.renewal == renewals.first)
    #expect(renewalResult.renewal.replacement.issuedAtMonotonicNanoseconds == 6_000_000_000)
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

@Test func agentRuntimeOwnerSamplesLeaseTimeAfterMenuCreatesDescriptor()
    async throws
{
    let requirement = try initialRequirement()
    let admission = RuntimeOwnerAdmissionV1([
        requirement.admission, requirement.admission,
    ])
    let desktop = RuntimeOwnerDesktopV1(descriptor: try initialDesktop(
        createdAtMilliseconds: 2_001
    ))
    let route = RuntimeOwnerMenuRouteV1()
    let clock = RuntimeOwnerClockV1([
        // The menu creates the descriptor after the Agent's request sample.
        2_000_000_000, 2_002_000_000, 2_100_000_000,
    ])
    let owner = AgentInteractiveRuntimeOwnerV1(
        admission: admission,
        desktop: desktop,
        runtime: route,
        monotonicNowNanoseconds: { clock.now() }
    )

    try await owner.install(initialBootstrap(), requirement: requirement)

    let install = try #require(await route.installs().first)
    #expect(install.lease.issuedAtMonotonicNanoseconds == 2_002_000_000)
    #expect(await owner.state() == .active(
        interactiveSessionID: initialSessionID,
        leaseID: install.lease.leaseID
    ))
}

@Test func agentRuntimeOwnerConsumesExactRoleCredentialWithoutTransfer()
    async throws
{
    let requirement = try initialRequirement()
    let bootstrap = try initialBootstrap()
    let inputOffer = bootstrap.acceptedBody.inputChannel
    let admission = RuntimeOwnerAdmissionV1([
        requirement.admission, requirement.admission,
    ])
    let clock = RuntimeOwnerClockV1([
        2_000_000_000, 2_001_000_000, 2_100_000_000,
    ])
    let identifiers = RuntimeOwnerIdentifiersV1([UUID(), UUID()])
    let owner = AgentInteractiveRuntimeOwnerV1(
        admission: admission,
        desktop: RuntimeOwnerDesktopV1(
            descriptor: try initialDesktop()
        ),
        runtime: RuntimeOwnerMenuRouteV1(),
        monotonicNowNanoseconds: { clock.now() },
        identifier: { identifiers.next() }
    )
    try await owner.install(bootstrap, requirement: requirement)

    let clientNonce = try WireBytes32(
        Data(repeating: 0x61, count: 32)
    )
    let hostNonce = try WireBytes32(
        Data(repeating: 0x62, count: 32)
    )
    let hello = try InteractiveChannelHelloBody(
        channelID: inputOffer.channelID,
        role: .input,
        clientID: WireUUID(initialClientID),
        primaryConnectionID: try WireBytes16(initialConnectionID),
        interactiveSessionID: WireUUID(initialSessionID),
        authorizationEpoch: .init(rawValue: 4),
        clientNonce: clientNonce
    )
    let challenge = try await owner.beginInteractiveChannel(
        hello: hello,
        hostNonce: hostNonce,
        monotonicNowMilliseconds: 2_100
    )
    #expect(challenge.channelID == inputOffer.channelID)
    #expect(challenge.role == .input)
    #expect(challenge.hostID.rawValue == initialHostID)
    #expect(challenge.hostFingerprint.rawValue == initialFingerprint)

    let transcript = try hello.transcriptInput(
        challenge: challenge,
        version: .init()
    )
    let clientProof = try CompanionSecurityV0
        .interactiveChannelClientProof(
            credential: Data(repeating: 1, count: 32),
            transcriptDigest: CompanionSecurityV0
                .interactiveChannelTranscriptDigest(transcript)
        )
    let accepted = try await owner.consumeInteractiveChannel(
        hello: hello,
        proof: InteractiveChannelProofBody(
            channelID: inputOffer.channelID,
            clientProof: try WireBytes32(clientProof)
        ),
        monotonicNowMilliseconds: 2_101
    )
    #expect(accepted.channelID == inputOffer.channelID)
    #expect(accepted.role == .input)
    #expect(try accepted.serverProof.rawValue == CompanionSecurityV0
        .interactiveChannelServerProof(
            credential: Data(repeating: 1, count: 32),
            transcriptDigest: CompanionSecurityV0
                .interactiveChannelTranscriptDigest(transcript)
        ))

    await #expect(throws: InteractiveSecurityAuthorityError.notChallenged) {
        _ = try await owner.consumeInteractiveChannel(
            hello: hello,
            proof: InteractiveChannelProofBody(
                channelID: inputOffer.channelID,
                clientProof: try WireBytes32(clientProof)
            ),
            monotonicNowMilliseconds: 2_102
        )
    }
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
        2_000_000_000, 2_001_000_000, 2_100_000_000,
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

@Test func agentRuntimeOwnerCompensatesFailedSurfaceCoordinatorConstruction()
    async throws
{
    let requirement = try initialRequirement()
    let admission = RuntimeOwnerAdmissionV1([
        requirement.admission, requirement.admission,
    ])
    let route = RuntimeOwnerMenuRouteV1()
    let identifiers = RuntimeOwnerIdentifiersV1([UUID(), UUID(), UUID()])
    let clock = RuntimeOwnerClockV1([
        2_000_000_000, 2_001_000_000, 2_100_000_000,
        21_000_000_000,
    ])
    let owner = AgentInteractiveRuntimeOwnerV1(
        admission: admission,
        desktop: RuntimeOwnerDesktopV1(
            descriptor: try initialDesktop()
        ),
        runtime: route,
        surfaceRuntime: RuntimeOwnerSurfaceRouteV1(),
        monotonicNowNanoseconds: { clock.now() },
        identifier: { identifiers.next() }
    )

    await #expect(
        throws: AgentInteractiveRuntimeOwnerErrorV1.unavailable
    ) {
        try await owner.install(
            initialBootstrap(),
            requirement: requirement
        )
    }
    #expect(await route.installs().count == 1)
    #expect(await route.revokes().count == 1)
    #expect(await owner.state() == .idle)
}

private enum RenewalSchedulerProbeErrorV1: Error {
    case stop
    case renewalFailed
}

#if DEBUG
@Test func interactiveLeaseSchedulerTestEntryUsesInstalledLeaseWithoutInstalling() async throws {
    let initial = try schedulerLease(renewalCounter: 0, issuedAt: 2_000_000_000, expiresAt: 12_000_000_000)
    let replacement = try schedulerLease(renewalCounter: 1, issuedAt: 10_000_000_000, expiresAt: 20_000_000_000)
    let runtime = RenewalSchedulerRuntimeV1(initialLease: initial, renewalResult: .replacement(replacement))
    let clock = RuntimeOwnerClockV1([2_000_000_000, 10_000_000_000, 10_000_000_000])
    let sleeper = RenewalSchedulerSleeperV1(successfulCalls: 1)
    let owner = AgentInteractiveLeaseRenewalOwnerV1(runtime: runtime,
        monotonicNowNanoseconds: { clock.now() }, sleep: { try await sleeper.sleep(nanoseconds: $0) })
    try await owner.startForInstalledTestRuntime(interactiveSessionID: initialSessionID,
        primaryConnectionID: initialConnectionID)
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while await sleeper.delays().count < 2, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(await runtime.installCount() == 0)
    #expect(await runtime.renewalSamples() == [10_000_000_000])
    #expect(await sleeper.delays() == [8_000_000_000, 8_000_000_000])
    await owner.terminate(interactiveSessionID: initialSessionID,
        primaryConnectionID: initialConnectionID, reason: .clientDisconnected)
    #expect(await runtime.terminations() == [.clientDisconnected])
}

@Test(arguments: ["foreignSession", "invalidPrimary"])
func interactiveLeaseSchedulerTestEntryRejectsInvalidBinding(fault: String) async throws {
    let initial = try schedulerLease(renewalCounter: 0, issuedAt: 2_000_000_000, expiresAt: 12_000_000_000)
    let runtime = RenewalSchedulerRuntimeV1(initialLease: initial, renewalResult: .failure)
    let owner = AgentInteractiveLeaseRenewalOwnerV1(runtime: runtime)
    let expected: AgentInteractiveLeaseRenewalOwnerErrorV1 = fault == "foreignSession" ? .invalidLease : .unavailable
    await #expect(throws: expected) {
        try await owner.startForInstalledTestRuntime(
            interactiveSessionID: fault == "foreignSession" ? UUID() : initialSessionID,
            primaryConnectionID: fault == "invalidPrimary" ? Data() : initialConnectionID)
    }
    #expect(await runtime.installCount() == 0)
    #expect(await runtime.renewalSamples().isEmpty)
    #expect(await runtime.terminations() == (fault == "foreignSession" ? [.protocolViolation] : []))
}
#endif

private actor RenewalSchedulerRuntimeV1:
    AgentInteractiveLeaseRenewingRuntimeV1
{
    enum RenewalResult: Sendable {
        case replacement(InteractiveExecutionLease)
        case failure
    }

    private let initialLease: InteractiveExecutionLease
    private let leaseAtRenewal: InteractiveExecutionLease
    private let renewalResult: RenewalResult
    private let leaseSnapshotSuspension: RuntimeInstallSuspensionV1?
    private var installCountStorage = 0
    private var renewalSamplesStorage: [UInt64] = []
    private var terminationsStorage: [InteractiveSessionEndReason] = []

    init(
        initialLease: InteractiveExecutionLease,
        leaseAtRenewal: InteractiveExecutionLease? = nil,
        renewalResult: RenewalResult,
        leaseSnapshotSuspension: RuntimeInstallSuspensionV1? = nil
    ) {
        self.initialLease = initialLease
        self.leaseAtRenewal = leaseAtRenewal ?? initialLease
        self.renewalResult = renewalResult
        self.leaseSnapshotSuspension = leaseSnapshotSuspension
    }

    func install(
        _: InteractiveSessionBootstrap,
        requirement _: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        installCountStorage += 1
    }

    func activeLeaseForScheduling() async -> InteractiveExecutionLease? {
        await leaseSnapshotSuspension?.suspend()
        return initialLease
    }

    func renewActiveLease(
        nowMonotonicNanoseconds: UInt64
    ) async throws -> AgentInteractiveLeaseRenewalResultV1 {
        renewalSamplesStorage.append(nowMonotonicNanoseconds)
        switch renewalResult {
        case .replacement(let replacement):
            return try .init(previous: leaseAtRenewal, renewal: .init(commandID: UUID(),
                previousLeaseID: leaseAtRenewal.leaseID, replacement: replacement))
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
    surfaceID: UUID = initialSurfaceID,
    revision: UInt64 = 1,
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
        surfaceID: surfaceID,
        surfaceRevision: .init(rawValue: revision),
        coordinateRevision: .init(rawValue: revision),
        allowedInteractionClasses: [.view, .pointer],
        renewalCounter: renewalCounter,
        issuedAtMonotonicNanoseconds: issuedAt,
        expiresAtMonotonicNanoseconds: expiresAt
    )
}

@Test
func leaseSchedulerCannotStartFromSnapshotReturnedAfterTermination() async throws {
    let pause = RuntimeInstallSuspensionV1()
    let runtime = RenewalSchedulerRuntimeV1(initialLease: try schedulerLease(
        renewalCounter: 0, issuedAt: 2_000_000_000, expiresAt: 12_000_000_000),
        renewalResult: .failure, leaseSnapshotSuspension: pause)
    let sleeper = RenewalSchedulerSleeperV1(successfulCalls: 0)
    let owner = AgentInteractiveLeaseRenewalOwnerV1(runtime: runtime,
        monotonicNowNanoseconds: { 2_000_000_000 },
        sleep: { try await sleeper.sleep(nanoseconds: $0) })
    let install = Task { try await owner.install(initialBootstrap(), requirement: initialRequirement()) }
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await pause.entered), ContinuousClock.now < deadline { await Task.yield() }
    #expect(await pause.entered)
    await owner.terminate(interactiveSessionID: initialSessionID,
        primaryConnectionID: initialConnectionID, reason: .clientDisconnected)
    await pause.release()
    if case .success = await install.result { Issue.record("A terminated install started lease renewal") }
    for _ in 0..<100 { await Task.yield() }
    #expect(await sleeper.delays().isEmpty)
    #expect(await runtime.renewalSamples().isEmpty)
    #expect(await runtime.terminations() == [.clientDisconnected])
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

@Test(arguments: [1, 3], [0, 500_000_000])
func interactiveLeaseSchedulerAcceptsSerializedSurfaceChangeBeforeRenewal(transitions: UInt64, issuanceDelay: UInt64) async throws {
    let initial = try schedulerLease(renewalCounter: 0, issuedAt: 2_000_000_000, expiresAt: 12_000_000_000)
    let surface = UUID()
    let changed = try schedulerLease(surfaceID: surface, revision: transitions + 1,
        renewalCounter: transitions, issuedAt: 3_000_000_000, expiresAt: 13_000_000_000)
    let replacement = try schedulerLease(surfaceID: surface, revision: transitions + 1,
        renewalCounter: transitions + 1, issuedAt: 10_000_000_000 + issuanceDelay,
        expiresAt: 20_000_000_000 + issuanceDelay)
    let runtime = RenewalSchedulerRuntimeV1(initialLease: initial, leaseAtRenewal: changed,
        renewalResult: .replacement(replacement))
    let clock = RuntimeOwnerClockV1([2_000_000_000, 10_000_000_000, 10_000_000_000])
    let sleeper = RenewalSchedulerSleeperV1(successfulCalls: 1)
    let owner = AgentInteractiveLeaseRenewalOwnerV1(runtime: runtime,
        monotonicNowNanoseconds: { clock.now() }, sleep: { try await sleeper.sleep(nanoseconds: $0) })
    try await owner.install(initialBootstrap(), requirement: initialRequirement())
    for _ in 0..<1_000 {
        let delays = await sleeper.delays()
        let terminations = await runtime.terminations()
        if delays.count > 1 || !terminations.isEmpty { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(await runtime.terminations().isEmpty)
    #expect(await sleeper.delays() == [8_000_000_000, 8_000_000_000 + issuanceDelay])
    await owner.terminate(interactiveSessionID: initialSessionID,
        primaryConnectionID: initialConnectionID, reason: .clientDisconnected)
}

@Test func interactiveLeaseSchedulerAcceptsSerializedDisplayChangeBeforeRenewal()
    async throws
{
    let initial = try schedulerLease(
        renewalCounter: 0,
        issuedAt: 2_000_000_000,
        expiresAt: 12_000_000_000
    )
    let display = UUID()
    let surface = UUID()
    let changed = try schedulerLease(
        selectedDisplayID: display,
        surfaceID: surface,
        revision: 2,
        renewalCounter: 1,
        issuedAt: 3_000_000_000,
        expiresAt: 13_000_000_000
    )
    let replacement = try schedulerLease(
        selectedDisplayID: display,
        surfaceID: surface,
        revision: 2,
        renewalCounter: 2,
        issuedAt: 10_000_000_000,
        expiresAt: 20_000_000_000
    )
    let runtime = RenewalSchedulerRuntimeV1(
        initialLease: initial,
        leaseAtRenewal: changed,
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
    for _ in 0..<1_000 {
        let delays = await sleeper.delays()
        let terminations = await runtime.terminations()
        if delays.count > 1 || !terminations.isEmpty { break }
        try await Task.sleep(for: .milliseconds(1))
    }

    #expect(await runtime.terminations().isEmpty)
    #expect(await sleeper.delays() == [
        8_000_000_000, 8_000_000_000,
    ])
    await owner.terminate(
        interactiveSessionID: initialSessionID,
        primaryConnectionID: initialConnectionID,
        reason: .clientDisconnected
    )
}

@Test(arguments: ["counterGap", "sameRevision", "wrongIssueTime", "wrongSurface"])
func interactiveLeaseSchedulerRejectsInvalidPostTransitionRenewal(fault: String) async throws {
    let initial = try schedulerLease(renewalCounter: 0, issuedAt: 2_000_000_000, expiresAt: 12_000_000_000)
    let surface = UUID()
    let revision: UInt64 = fault == "sameRevision" ? 1 : 2
    let previous = try schedulerLease(surfaceID: surface, revision: revision,
        renewalCounter: 1, issuedAt: 3_000_000_000, expiresAt: 13_000_000_000)
    let replacement = try schedulerLease(
        surfaceID: fault == "wrongSurface" ? UUID() : surface,
        revision: revision,
        renewalCounter: fault == "counterGap" ? 3 : 2,
        issuedAt: fault == "wrongIssueTime" ? 9_000_000_000 : 10_000_000_000, expiresAt: 19_000_000_000)
    let runtime = RenewalSchedulerRuntimeV1(initialLease: initial, leaseAtRenewal: previous,
        renewalResult: .replacement(replacement))
    let clock = RuntimeOwnerClockV1([2_000_000_000, 10_000_000_000])
    let sleeper = RenewalSchedulerSleeperV1(successfulCalls: 1)
    let owner = AgentInteractiveLeaseRenewalOwnerV1(runtime: runtime,
        monotonicNowNanoseconds: { clock.now() }, sleep: { try await sleeper.sleep(nanoseconds: $0) })
    try await owner.install(initialBootstrap(), requirement: initialRequirement())
    for _ in 0..<1_000 {
        if await !runtime.terminations().isEmpty { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(await runtime.terminations() == [.protocolViolation])
    #expect(await runtime.renewalSamples().count == 1)
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
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while await runtime.terminations().isEmpty,
          ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(1))
    }

    #expect(await runtime.renewalSamples() == [10_000_000_000])
    #expect(await runtime.terminations() == [.protocolViolation])
}

private actor NativeSnapshotInertBackendV1: InteractiveNativeVideoEnrollmentBackendV0 {
    func prepare(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0, clientCertificateDER: Data) throws -> Data {
        throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
    }
    func activate(operationID: UUID) throws -> InteractiveNativeVideoEndpointV0 {
        throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
    }
    func isActive(operationID: UUID) -> Bool { false }
    func retire(operationID: UUID) {}
}
private actor NativeSnapshotRuntimeProbeV1: InteractiveNativeVideoRuntimeProvidingV0 {
    let value: InteractiveNativeVideoRuntimeSnapshotV0
    let snapshotGate: RuntimeInstallSuspensionV1?
    let backendGate: RuntimeInstallSuspensionV1?
    private(set) var backendCount = 0
    init(snapshotGate: RuntimeInstallSuspensionV1? = nil, backendGate: RuntimeInstallSuspensionV1? = nil) throws {
        self.snapshotGate = snapshotGate; self.backendGate = backendGate
        value = .init(binding: try .init(hostID: initialHostID, hostFingerprint: initialFingerprint,
            clientID: initialClientID, primaryConnectionID: initialConnectionID,
            interactiveSessionID: initialSessionID, authorizationEpoch: 4, grantRevision: 5, policyRevision: 6,
            controlGeneration: UUID(), expiresAtMonotonicMilliseconds: 61_000),
            surface: try .init(surfaceID: initialSurfaceID, surfaceRevision: 1, coordinateSpaceRevision: 1,
                encodedWidth: 1280, encodedHeight: 720),
            logicalWidthPoints: 2560, logicalHeightPoints: 1440, rotation: .degrees0, selectedDisplayID: initialDisplayID,
            visibleMenuAppGeneration: initialMenuGeneration, visibleMenuAppRevision: 9)
    }
    func snapshot(fence: InteractiveNativeVideoRequestFenceV0, context: InteractiveSessionCommandContextV0) async -> InteractiveNativeVideoRuntimeSnapshotV0? {
        await snapshotGate?.suspend()
        return value
    }
    func makeBackend(snapshot: InteractiveNativeVideoRuntimeSnapshotV0) async -> any InteractiveNativeVideoEnrollmentBackendV0 {
        backendCount += 1
        await backendGate?.suspend()
        return NativeSnapshotInertBackendV1()
    }
}
private func nativeBindingFenceV1() throws -> InteractiveNativeVideoRequestFenceV0 {
    try .init(interactiveSessionID: .init(initialSessionID), authorizationEpoch: .init(rawValue: 4),
        negotiationID: .init(UUID()), peerGeneration: 1, surfaceID: .init(initialSurfaceID),
        surfaceRevision: 1, coordinateSpaceRevision: 1)
}

@Test func nativeRuntimeBindingDropsSnapshotAfterMenuGenerationLoss() async throws {
    let authority = AgentInteractiveRuntimeBindingAuthorityV1()
    let gate = RuntimeInstallSuspensionV1()
    let native = try NativeSnapshotRuntimeProbeV1(snapshotGate: gate)
    try await authority.bind(runtime: RuntimeBindingProbeV1(), channelAuthenticator: nil, nativeRuntime: native, generation: 1)
    let requirement = try initialRequirement()
    try await authority.install(initialBootstrap(), requirement: requirement)
    let fence = try nativeBindingFenceV1()
    let pending = Task { try await authority.snapshot(fence: fence, context: requirement.command) }
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await gate.entered), ContinuousClock.now < deadline { await Task.yield() }
    #expect(await gate.entered)
    #expect(await authority.invalidate(generation: 1))
    await gate.release()
    #expect(try await pending.value == nil)
    #expect(await native.backendCount == 0)
}

@Test func nativeRuntimeBindingDropsBackendAfterPrimaryRetirement() async throws {
    let authority = AgentInteractiveRuntimeBindingAuthorityV1()
    let gate = RuntimeInstallSuspensionV1()
    let native = try NativeSnapshotRuntimeProbeV1(backendGate: gate)
    try await authority.bind(runtime: RuntimeBindingProbeV1(), channelAuthenticator: nil, nativeRuntime: native, generation: 1)
    let requirement = try initialRequirement()
    try await authority.install(initialBootstrap(), requirement: requirement)
    let snapshot = try #require(await authority.snapshot(fence: nativeBindingFenceV1(), context: requirement.command))
    let pending = Task { try await authority.makeBackend(snapshot: snapshot) }
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await gate.entered), ContinuousClock.now < deadline { await Task.yield() }
    #expect(await gate.entered)
    await authority.terminate(interactiveSessionID: initialSessionID, primaryConnectionID: initialConnectionID, reason: .clientDisconnected)
    await gate.release()
    await #expect(throws: AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable) { try await pending.value }
}

private actor NativeSnapshotSlowStopRuntimeV1: InteractiveSessionRuntimeOwningV0 {
    let gate: RuntimeInstallSuspensionV1
    init(_ gate: RuntimeInstallSuspensionV1) { self.gate = gate }
    func install(_ bootstrap: InteractiveSessionBootstrap, requirement: InteractiveSessionRuntimeRequirementV0) {}
    func terminate(interactiveSessionID: UUID, primaryConnectionID: Data, reason: InteractiveSessionEndReason) async {
        await gate.suspend()
    }
}
@Test func nativeRuntimeAdmissionFencesBeforeSlowStopDrains() async throws {
    let authority = AgentInteractiveRuntimeBindingAuthorityV1()
    let gate = RuntimeInstallSuspensionV1()
    let native = try NativeSnapshotRuntimeProbeV1()
    try await authority.bind(runtime: NativeSnapshotSlowStopRuntimeV1(gate), channelAuthenticator: nil, nativeRuntime: native, generation: 1)
    let requirement = try initialRequirement()
    try await authority.install(initialBootstrap(), requirement: requirement)
    let fence = try nativeBindingFenceV1()
    let value = try #require(await authority.snapshot(fence: fence, context: requirement.command))
    let stopping = Task { await authority.terminate(interactiveSessionID: initialSessionID,
        primaryConnectionID: initialConnectionID, reason: .clientDisconnected) }
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await gate.entered), ContinuousClock.now < deadline { await Task.yield() }
    #expect(await gate.entered)
    #expect(try await authority.snapshot(fence: fence, context: requirement.command) == nil)
    await #expect(throws: AgentInteractiveRuntimeBindingAuthorityErrorV1.unavailable) { try await authority.makeBackend(snapshot: value) }
    #expect(await native.backendCount == 0)
    await gate.release()
    await stopping.value
}
