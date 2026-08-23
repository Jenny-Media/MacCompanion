#if os(macOS)
import CompanionAgentNetworkPlatform
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionNetworkPlatform
import Foundation

package protocol MacAgentFocusCandidateProvidingV1: Sendable {
    func focusCandidate(
        current descriptor: AdaptiveSurfaceDescriptor
    ) async throws -> InteractiveFocusEventCandidateV0
}

@available(macOS 26.0, *)
extension MacLocalXPCInteractiveMenuRuntimeRouteV1:
    MacAgentFocusCandidateProvidingV1 {}

package enum MacAgentFocusCandidateSourceErrorV1:
    Error, Equatable, Sendable
{
    case unavailable
    case invalidGeneration
    case alreadyBound
    case staleGeneration
    case terminal
}

/// Stable Agent-side handle for the exact authenticated menu generation. Raw
/// Accessibility state never crosses this boundary; providers return only the
/// already privacy-filtered focus candidate.
package actor MacAgentFocusCandidateSourceAuthorityV1 {
    private struct Bound: Sendable {
        let generation: UInt64
        let source: any MacAgentFocusCandidateProvidingV1
    }

    private var bound: Bound?
    private var highestGeneration: UInt64 = 0
    private var terminal = false

    package func bind(
        _ source: any MacAgentFocusCandidateProvidingV1,
        generation: UInt64
    ) throws {
        guard !terminal else {
            throw MacAgentFocusCandidateSourceErrorV1.terminal
        }
        guard generation > 0 else {
            throw MacAgentFocusCandidateSourceErrorV1.invalidGeneration
        }
        guard bound == nil else {
            throw MacAgentFocusCandidateSourceErrorV1.alreadyBound
        }
        guard generation > highestGeneration else {
            throw MacAgentFocusCandidateSourceErrorV1.staleGeneration
        }
        highestGeneration = generation
        bound = Bound(generation: generation, source: source)
    }

    package func candidate(
        current descriptor: AdaptiveSurfaceDescriptor
    ) async throws -> InteractiveFocusEventCandidateV0 {
        guard !terminal, let bound else {
            throw MacAgentFocusCandidateSourceErrorV1.unavailable
        }
        let candidate = try await bound.source.focusCandidate(
            current: descriptor
        )
        guard !terminal, self.bound?.generation == bound.generation else {
            throw MacAgentFocusCandidateSourceErrorV1.unavailable
        }
        return candidate
    }

    @discardableResult
    package func invalidate(generation: UInt64) -> Bool {
        guard !terminal, bound?.generation == generation else { return false }
        bound = nil
        return true
    }

    package func finish() {
        terminal = true
        bound = nil
    }
}

package enum MacAgentFocusEventObserverErrorV1:
    Error, Equatable, Sendable
{
    case alreadyInstalled
    case terminal
}

/// Permanent Agent observer for automatic Smart Zoom suggestions. It polls
/// only while the product is live, never samples Accessibility without an
/// authenticated primary sink, and permits at most one outstanding event per
/// exact surface fence.
@available(macOS 26.0, *)
package actor MacAgentFocusEventObserverV1 {
    private struct Fence: Equatable, Sendable {
        let sessionID: UUID
        let authorizationEpoch: UInt64
        let surfaceID: UUID
        let surfaceRevision: UInt64
        let coordinateRevision: UInt64

        init(_ descriptor: AdaptiveSurfaceDescriptor) {
            sessionID = descriptor.interactiveSessionID
            authorizationEpoch = descriptor.authorizationEpoch.rawValue
            surfaceID = descriptor.surfaceID
            surfaceRevision = descriptor.surfaceRevision.rawValue
            coordinateRevision =
                descriptor.coordinateSpaceRevision.rawValue
        }
    }

    private let source: MacAgentFocusCandidateSourceAuthorityV1
    private let control: any InteractiveSurfaceControlDispatchingV0
    private var listener: MacAgentNetworkListenerRuntimeOwnerV1?
    private var context: (@Sendable () -> NetworkHostRequestContextV0)?
    private var loop: Task<Void, Never>?
    private var outstandingFence: Fence?
    private var terminal = false

    package init(
        source: MacAgentFocusCandidateSourceAuthorityV1,
        control: any InteractiveSurfaceControlDispatchingV0
    ) {
        self.source = source
        self.control = control
    }

    package func install(
        listener: MacAgentNetworkListenerRuntimeOwnerV1,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0
    ) throws {
        guard !terminal else {
            throw MacAgentFocusEventObserverErrorV1.terminal
        }
        guard self.listener == nil, self.context == nil else {
            throw MacAgentFocusEventObserverErrorV1.alreadyInstalled
        }
        self.listener = listener
        self.context = context
    }

    package func start() throws {
        guard !terminal else {
            throw MacAgentFocusEventObserverErrorV1.terminal
        }
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sampleOnce()
                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                } catch {
                    return
                }
            }
        }
    }

    package func sampleOnce() async {
        guard !terminal, let listener, let context,
              let readiness = await control.currentFocusEventReadiness(),
              await listener.hasAuthenticatedPrimaryEventSink(
                primaryConnectionID: readiness.primaryConnectionID
              )
        else { return }
        let descriptor = readiness.descriptor
        let fence = Fence(descriptor)
        guard outstandingFence != fence else { return }

        let candidate: InteractiveFocusEventCandidateV0
        do {
            candidate = try await source.candidate(current: descriptor)
        } catch {
            return
        }
        if candidate.recommendedTargetKind == descriptor.kind,
           candidate.focus == descriptor.focus,
           !candidate.inputPaused {
            return
        }

        let fresh = context()
        let hostContext: InteractiveFocusEventHostContextV0
        do {
            hostContext = try InteractiveFocusEventHostContextV0(
                hostState: fresh.hostState,
                wallNowUnixMilliseconds: fresh.wallNowUnixMilliseconds,
                monotonicNowMilliseconds: fresh.monotonicNowMilliseconds,
                eventMessageID: fresh.responseMessageID
            )
            let prepared = try await control.prepareFocusEvent(
                candidate: candidate,
                hostContext: hostContext
            )
            try await listener.sendAuthenticatedEvent(
                prepared.eventJSON,
                primaryConnectionID: readiness.primaryConnectionID
            )
            outstandingFence = fence
        } catch {
            await control.revokePreparedFocusEvent()
            await control.primarySessionClosed()
        }
    }

    package func finish() async {
        guard !terminal else { return }
        terminal = true
        let loop = self.loop
        self.loop = nil
        loop?.cancel()
        if let loop { await loop.value }
        listener = nil
        context = nil
        outstandingFence = nil
    }
}
#endif
