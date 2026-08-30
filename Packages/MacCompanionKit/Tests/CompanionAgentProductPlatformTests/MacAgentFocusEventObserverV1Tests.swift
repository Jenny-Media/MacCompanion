#if os(macOS)
@testable import CompanionAgentProductPlatform
import CompanionAgentNetworkPlatform
import CompanionDomain
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionNetworkPlatform
import CompanionWire
import Foundation
import Testing

private enum FocusObserverProbeErrorV1: Error {
    case unused
    case prepareFailed
    case sendFailed
}
private let focusObserverPrimaryIDV1 = Data(repeating: 0x51, count: 16)

@available(macOS 26.0, *)
private actor FocusObserverListenerV1: MacAgentNetworkListenerRuntimeV1 {
    var hasPrimary: Bool
    var rejectSend: Bool
    let primaryConnectionID: Data
    private var events: [Data] = []

    init(
        hasPrimary: Bool,
        rejectSend: Bool = false,
        primaryConnectionID: Data = focusObserverPrimaryIDV1
    ) {
        self.hasPrimary = hasPrimary
        self.rejectSend = rejectSend
        self.primaryConnectionID = primaryConnectionID
    }

    func start() async throws {}
    func cancel() async {}
    func snapshot() -> AgentNetworkListenerServiceSnapshotV1 {
        AgentNetworkListenerServiceSnapshotV1(
            state: .listening,
            handoff: AgentNetworkListenerHandoffSnapshotV1(
                isCancelled: false,
                hasPendingTLS: false,
                isBinding: false,
                hasActivePrimary: hasPrimary
            ),
            lastListenerTerminationReason: nil,
            hasAcceptedConnectionStartFailure: false
        )
    }
    func hasAuthenticatedEventSink(
        primaryConnectionID: Data
    ) async -> Bool {
        hasPrimary && primaryConnectionID == self.primaryConnectionID
    }
    func sendAuthenticatedEvent(
        _ eventJSON: Data,
        primaryConnectionID: Data
    ) async throws {
        guard primaryConnectionID == self.primaryConnectionID else {
            throw FocusObserverProbeErrorV1.sendFailed
        }
        if rejectSend { throw FocusObserverProbeErrorV1.sendFailed }
        events.append(eventJSON)
    }
    func sentEvents() -> [Data] { events }
}

private actor FocusObserverSourceV1: MacAgentFocusCandidateProvidingV1 {
    private var value: InteractiveFocusEventCandidateV0
    private var reads = 0

    init(_ value: InteractiveFocusEventCandidateV0) { self.value = value }

    func focusCandidate(
        current descriptor: AdaptiveSurfaceDescriptor
    ) -> InteractiveFocusEventCandidateV0 {
        reads += 1
        return value
    }
    func readCount() -> Int { reads }
    func setValue(_ value: InteractiveFocusEventCandidateV0) {
        self.value = value
    }
}

private final class FocusObserverClockV1: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) { self.value = value }

    func now() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: UInt64) {
        lock.lock()
        self.value = value
        lock.unlock()
    }
}

private actor FocusObserverControlV1:
    InteractiveSurfaceControlDispatchingV0
{
    let descriptor: AdaptiveSurfaceDescriptor
    let eventJSON: Data
    private var rejectPreparation = false
    private var preparations = 0
    private var revocations = 0
    private var closes = 0

    init(descriptor: AdaptiveSurfaceDescriptor, eventJSON: Data) {
        self.descriptor = descriptor
        self.eventJSON = eventJSON
    }

    func currentFocusEventReadiness()
        -> InteractiveFocusEventReadinessV0?
    {
        guard closes == 0 else { return nil }
        return try? InteractiveFocusEventReadinessV0(
            descriptor: descriptor,
            primaryConnectionID: focusObserverPrimaryIDV1
        )
    }
    func prepareFocusEvent(
        candidate: InteractiveFocusEventCandidateV0,
        hostContext: InteractiveFocusEventHostContextV0
    ) throws -> InteractivePreparedFocusEventV0 {
        preparations += 1
        if rejectPreparation {
            throw FocusObserverProbeErrorV1.prepareFailed
        }
        return InteractivePreparedFocusEventV0(
            eventJSON: eventJSON,
            eventSequence: Int64(preparations),
            targetToken: WireUUID(UUID())
        )
    }
    func revokePreparedFocusEvent() { revocations += 1 }
    func primarySessionClosed() { closes += 1 }
    func setRejectPreparation(_ value: Bool) {
        rejectPreparation = value
    }

    func requestInitial(
        _ request: InteractiveInitialSurfaceRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveInitialSurfaceDescriptorBodyV0 {
        throw FocusObserverProbeErrorV1.unused
    }
    func acknowledgeInitial(
        _ request: InteractiveInitialSurfaceAcknowledgementBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveInitialSurfaceAcknowledgedBodyV0 {
        throw FocusObserverProbeErrorV1.unused
    }
    func targets(
        _ request: InteractiveSurfaceTargetsRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceTargetsResponseBodyV0 {
        throw FocusObserverProbeErrorV1.unused
    }
    func select(
        _ request: InteractiveSurfaceSelectBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceSelectedBodyV0 {
        throw FocusObserverProbeErrorV1.unused
    }
    func acknowledge(
        _ request: InteractiveSurfaceAcknowledgementBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceAcknowledgedBodyV0 {
        throw FocusObserverProbeErrorV1.unused
    }

    func counts() -> (Int, Int, Int) {
        (preparations, revocations, closes)
    }
}

@available(macOS 26.0, *)
@Test func focusObserverRecoversFromNonterminalPreparationFailure()
    async throws
{
    let listener = FocusObserverListenerV1(hasPrimary: true)
    let source = FocusObserverSourceV1(try focusObserverCandidateV1())
    let control = FocusObserverControlV1(
        descriptor: try focusObserverDescriptorV1(),
        eventJSON: Data([8])
    )
    await control.setRejectPreparation(true)
    let observer = try await focusObserverV1(
        listener: listener, source: source, control: control
    )
    await observer.sampleOnce()
    #expect(await control.counts() == (0, 0, 0))
    await observer.sampleOnce()
    #expect(await control.counts() == (1, 0, 0))
    #expect(await listener.sentEvents().isEmpty)

    await control.setRejectPreparation(false)
    await observer.sampleOnce()
    #expect(await control.counts() == (1, 0, 0))
    await observer.sampleOnce()
    #expect(await control.counts() == (2, 0, 0))
    #expect(await listener.sentEvents() == [Data([8])])
}

private func focusObserverDescriptorV1() throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: UUID(),
        authorizationEpoch: .init(rawValue: 2),
        surfaceID: UUID(),
        kind: .desktop,
        surfaceRevision: .init(rawValue: 3),
        coordinateSpaceRevision: .init(rawValue: 4),
        encodedWidth: 1_440,
        encodedHeight: 900,
        logicalWidthPoints: 1_440,
        logicalHeightPoints: 900,
        interactionClasses: [.view, .pointer, .keyboard, .text],
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 1_000,
        expiresAtMonotonicMilliseconds: 11_000
    )
}

@available(macOS 26.0, *)
@Test func focusObserverDoesNotSampleWithoutTextAuthority() async throws {
    let listener = FocusObserverListenerV1(hasPrimary: true)
    let source = FocusObserverSourceV1(try focusObserverCandidateV1())
    let descriptor = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: UUID(),
        authorizationEpoch: .init(rawValue: 2),
        surfaceID: UUID(),
        kind: .desktop,
        surfaceRevision: .init(rawValue: 3),
        coordinateSpaceRevision: .init(rawValue: 4),
        encodedWidth: 1_440,
        encodedHeight: 900,
        logicalWidthPoints: 1_440,
        logicalHeightPoints: 900,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 1_000,
        expiresAtMonotonicMilliseconds: 11_000
    )
    let control = FocusObserverControlV1(
        descriptor: descriptor,
        eventJSON: Data([1])
    )
    let observer = try await focusObserverV1(
        listener: listener, source: source, control: control
    )
    await observer.sampleOnce()
    #expect(await source.readCount() == 0)
    #expect(await control.counts().0 == 0)
}

private func focusObserverCandidateV1()
    throws -> InteractiveFocusEventCandidateV0
{
    try InteractiveFocusEventCandidateV0(
        recommendedTargetKind: .focusedRegion,
        focus: try SurfaceFocus(
            token: UUID(),
            revision: .init(rawValue: 1),
            category: .text,
            bounds: try NormalizedSurfaceRect(
                x: 1_000, y: 2_000, width: 20_000, height: 5_000
            ),
            editable: true,
            secure: false
        ),
        inputPaused: false,
        reason: .verifiedFocus
    )
}

@available(macOS 26.0, *)
private func focusObserverV1(
    listener: FocusObserverListenerV1,
    source: FocusObserverSourceV1,
    control: FocusObserverControlV1,
    monotonicNow: @escaping @Sendable () -> UInt64 = { 2_000 }
) async throws -> MacAgentFocusEventObserverV1 {
    let authority = MacAgentFocusCandidateSourceAuthorityV1()
    try await authority.bind(source, generation: 1)
    let observer = MacAgentFocusEventObserverV1(
        source: authority,
        control: control
    )
    try await observer.install(
        listener: MacAgentNetworkListenerRuntimeOwnerV1(runtime: listener),
        context: {
            NetworkHostRequestContextV0(
                hostState: .userSessionActive,
                wallNowUnixMilliseconds: 1_724_100_000_000,
                monotonicNowMilliseconds: monotonicNow(),
                responseMessageID: WireUUID(UUID())
            )
        }
    )
    return observer
}

@available(macOS 26.0, *)
@Test func focusObserverDoesNotSampleWithoutAuthenticatedPrimary()
    async throws
{
    let listener = FocusObserverListenerV1(hasPrimary: false)
    let source = FocusObserverSourceV1(try focusObserverCandidateV1())
    let control = FocusObserverControlV1(
        descriptor: try focusObserverDescriptorV1(),
        eventJSON: Data([1])
    )
    let observer = try await focusObserverV1(
        listener: listener, source: source, control: control
    )
    await observer.sampleOnce()
    #expect(await source.readCount() == 0)
    #expect(await control.counts().0 == 0)
}

@available(macOS 26.0, *)
@Test func focusObserverDoesNotSampleReplacementPrimary() async throws {
    let listener = FocusObserverListenerV1(
        hasPrimary: true,
        primaryConnectionID: Data(repeating: 0x52, count: 16)
    )
    let source = FocusObserverSourceV1(try focusObserverCandidateV1())
    let control = FocusObserverControlV1(
        descriptor: try focusObserverDescriptorV1(),
        eventJSON: Data([1])
    )
    let observer = try await focusObserverV1(
        listener: listener, source: source, control: control
    )
    await observer.sampleOnce()
    #expect(await source.readCount() == 0)
    #expect(await control.counts().0 == 0)
}

@available(macOS 26.0, *)
@Test func focusObserverCoalescesUnchangedFreshCandidate() async throws {
    let listener = FocusObserverListenerV1(hasPrimary: true)
    let source = FocusObserverSourceV1(try focusObserverCandidateV1())
    let control = FocusObserverControlV1(
        descriptor: try focusObserverDescriptorV1(),
        eventJSON: Data([1, 2, 3])
    )
    let observer = try await focusObserverV1(
        listener: listener, source: source, control: control
    )
    await observer.sampleOnce()
    await observer.sampleOnce()
    #expect(await source.readCount() == 2)
    #expect(await control.counts() == (1, 0, 0))
    #expect(await listener.sentEvents() == [Data([1, 2, 3])])
}

@available(macOS 26.0, *)
@Test func focusObserverRefreshesExpiringCandidate() async throws {
    let listener = FocusObserverListenerV1(hasPrimary: true)
    let source = FocusObserverSourceV1(try focusObserverCandidateV1())
    let control = FocusObserverControlV1(
        descriptor: try focusObserverDescriptorV1(),
        eventJSON: Data([4])
    )
    let clock = FocusObserverClockV1(2_000)
    let observer = try await focusObserverV1(
        listener: listener,
        source: source,
        control: control,
        monotonicNow: { clock.now() }
    )
    await observer.sampleOnce()
    await observer.sampleOnce()
    clock.set(2_500)
    await observer.sampleOnce()
    #expect(await control.counts() == (2, 0, 0))
    #expect(await listener.sentEvents() == [Data([4]), Data([4])])
}

@available(macOS 26.0, *)
@Test func focusObserverReplacesChangedCandidateOnSameSurface() async throws {
    let listener = FocusObserverListenerV1(hasPrimary: true)
    let source = FocusObserverSourceV1(try focusObserverCandidateV1())
    let control = FocusObserverControlV1(
        descriptor: try focusObserverDescriptorV1(),
        eventJSON: Data([5])
    )
    let observer = try await focusObserverV1(
        listener: listener, source: source, control: control
    )
    await observer.sampleOnce()
    await observer.sampleOnce()
    let changed = try InteractiveFocusEventCandidateV0(
        recommendedTargetKind: .focusedRegion,
        focus: try SurfaceFocus(
            token: UUID(),
            revision: .init(rawValue: 2),
            category: .text,
            bounds: try NormalizedSurfaceRect(
                x: 2_000, y: 3_000, width: 18_000, height: 4_000
            ),
            editable: true,
            secure: false
        ),
        inputPaused: false,
        reason: .verifiedFocus
    )
    await source.setValue(changed)
    await observer.sampleOnce()
    #expect(await control.counts() == (1, 0, 0))
    await observer.sampleOnce()
    #expect(await control.counts() == (2, 0, 0))
    #expect(await listener.sentEvents() == [Data([5]), Data([5])])
}

@available(macOS 26.0, *)
@Test func focusObserverRevokesAndClosesOnPublicationRace() async throws {
    let listener = FocusObserverListenerV1(
        hasPrimary: true,
        rejectSend: true
    )
    let source = FocusObserverSourceV1(try focusObserverCandidateV1())
    let control = FocusObserverControlV1(
        descriptor: try focusObserverDescriptorV1(),
        eventJSON: Data([9])
    )
    let observer = try await focusObserverV1(
        listener: listener, source: source, control: control
    )
    await observer.sampleOnce()
    #expect(await control.counts() == (0, 0, 0))
    await observer.sampleOnce()
    #expect(await control.counts() == (1, 1, 1))
    #expect(await listener.sentEvents().isEmpty)
}

@available(macOS 26.0, *)
@Test func focusObserverCoalescesRapidCandidateChurnBeforePublication()
    async throws
{
    let first = try focusObserverCandidateV1()
    let transientDesktop = try InteractiveFocusEventCandidateV0(
        recommendedTargetKind: .desktop,
        focus: nil,
        inputPaused: false,
        reason: .ambiguousGeometry
    )
    let listener = FocusObserverListenerV1(hasPrimary: true)
    let source = FocusObserverSourceV1(first)
    let control = FocusObserverControlV1(
        descriptor: try focusObserverDescriptorV1(),
        eventJSON: Data([0x0a])
    )
    let observer = try await focusObserverV1(
        listener: listener, source: source, control: control
    )

    await observer.sampleOnce()
    await source.setValue(transientDesktop)
    await observer.sampleOnce()
    await source.setValue(first)
    await observer.sampleOnce()
    #expect(await control.counts() == (0, 0, 0))
    #expect(await listener.sentEvents().isEmpty)

    await observer.sampleOnce()
    #expect(await control.counts() == (1, 0, 0))
    #expect(await listener.sentEvents() == [Data([0x0a])])
}
#endif
