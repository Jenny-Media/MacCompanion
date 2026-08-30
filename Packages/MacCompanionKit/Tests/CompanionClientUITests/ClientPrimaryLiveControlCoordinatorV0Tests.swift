#if os(iOS)
@testable import CompanionClientUI
import CompanionClientPlatform
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import Combine
import Foundation
import Testing

@available(iOS 17.0, *)
@MainActor
private final class LiveControlTextProductV0:
    ClientPrimaryLiveControlProductV0
{
    let descriptor: AdaptiveSurfaceDescriptor
    let surface = UIKitClientLiveSurfaceViewV0(
        mode: .trackpad,
        onPayloads: { _ in },
        onFailure: { _ in }
    )
    private(set) var textPreparationStarted = false
    private(set) var composerBinding: SurfaceInputFence?
    private(set) var composedText: String?
    private var textPreparationContinuation: CheckedContinuation<Bool, Never>?

    init() throws {
        descriptor = try AdaptiveSurfaceDescriptor(
            interactiveSessionID: UUID(),
            authorizationEpoch: .init(rawValue: 1),
            surfaceID: UUID(),
            kind: .desktop,
            surfaceRevision: .init(rawValue: 1),
            coordinateSpaceRevision: .init(rawValue: 1),
            encodedWidth: 640,
            encodedHeight: 480,
            logicalWidthPoints: 640,
            logicalHeightPoints: 480,
            interactionClasses: [.view, .pointer, .keyboard, .text],
            privacyProfile: .visualOnly,
            metadataFields: [],
            createdAtMonotonicMilliseconds: 1,
            expiresAtMonotonicMilliseconds: 30_001
        )
    }

    func refreshPrimaryState() async -> Bool { true }
    func activationFailedOrClosed() async -> Bool { false }
    func requestSurfaceTargets() async throws
        -> [InteractiveSurfaceTargetCandidateV0]
    { [] }
    func setAutomaticSmartZoomEnabled(_ enabled: Bool) async throws {}

    func prepareNativeTextComposer() async throws -> SurfaceInputFence? {
        composerBinding
    }

    func sendComposedText(
        _ text: String,
        boundTo binding: SurfaceInputFence
    ) async throws {
        guard binding == composerBinding else {
            throw ClientPrimaryLiveControlErrorV0.unavailable
        }
        composedText = text
    }

    func enableComposer() {
        composerBinding = SurfaceInputFence(
            interactiveSessionID: descriptor.interactiveSessionID,
            authorizationEpoch: descriptor.authorizationEpoch,
            surfaceID: descriptor.surfaceID,
            surfaceRevision: descriptor.surfaceRevision,
            coordinateSpaceRevision: descriptor.coordinateSpaceRevision
        )
    }

    func prepareTextInput() async throws -> Bool {
        textPreparationStarted = true
        return await withCheckedContinuation { continuation in
            textPreparationContinuation = continuation
        }
    }

    func finishTextPreparation(_ prepared: Bool) {
        textPreparationContinuation?.resume(returning: prepared)
        textPreparationContinuation = nil
    }

    func selectSurface(
        kind: InteractiveSurfaceKind,
        targetToken: UUID?
    ) async throws {}

    func close() async {}
}

@Test @MainActor
func textPreparationKeepsTheActiveMediaPhase() async throws {
    let product = try LiveControlTextProductV0()
    let coordinator = ClientPrimaryLiveControlCoordinatorV0(
        productFactory: { _, _ in product }
    )
    coordinator.start(mode: .trackpad)
    while coordinator.phase != .active { await Task.yield() }

    let preparation = Task { try await coordinator.prepareTextInput() }
    while !product.textPreparationStarted { await Task.yield() }

    #expect(coordinator.phase == .active)
    product.finishTextPreparation(true)
    #expect(try await preparation.value)
    #expect(coordinator.phase == .active)
}

@Test @MainActor
func nativeComposerPreparationAndSendKeepTheActiveMediaPhase() async throws {
    let product = try LiveControlTextProductV0()
    product.enableComposer()
    let coordinator = ClientPrimaryLiveControlCoordinatorV0(
        productFactory: { _, _ in product }
    )
    coordinator.start(mode: .directTouch)
    while coordinator.phase != .active { await Task.yield() }

    let binding = try #require(
        try await coordinator.prepareNativeTextComposer()
    )
    #expect(coordinator.phase == .active)
    try await coordinator.sendComposedText(
        "Local draft",
        boundTo: binding
    )
    #expect(product.composedText == "Local draft")
    #expect(coordinator.phase == .active)
}

@Test @MainActor
func repeatedTerminalWorkspaceModeDoesNotRepublishCoordinatorState() {
    let coordinator = ClientPrimaryLiveControlCoordinatorV0(
        productFactory: { _, _ in
            throw ClientPrimaryLiveControlErrorV0.unavailable
        }
    )
    var changes = 0
    let observation = coordinator.objectWillChange.sink { changes += 1 }

    coordinator.acceptWorkspaceMode(.unavailable)
    let changesAfterFirstDelivery = changes
    coordinator.acceptWorkspaceMode(.unavailable)
    coordinator.acceptWorkspaceMode(.unavailable)

    #expect(coordinator.phase == .failed)
    #expect(changesAfterFirstDelivery > 0)
    #expect(changes == changesAfterFirstDelivery)
    withExtendedLifetime(observation) {}
}
#endif
