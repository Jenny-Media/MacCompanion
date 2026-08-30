#if os(macOS)
import CompanionAgentNetworkPlatform
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionNetworkPlatform
import Foundation
import OSLog

private let macAgentFocusEventLoggerV1 = Logger(
    subsystem: "media.jenny.maccompanion.agent",
    category: "interactive-focus"
)

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
/// authenticated primary sink. It keeps at most one current host binding,
/// replaces it when focus changes, and refreshes unchanged short-lived focus
/// authority before it expires on the client.
@available(macOS 26.0, *)
package actor MacAgentFocusEventObserverV1 {
    private struct CandidateSummary: Equatable, Sendable {
        let kind: InteractiveSurfaceKind
        let hasFocus: Bool
        let editable: Bool
        let secure: Bool
        let inputPaused: Bool
        let reason: InteractiveFocusEventReasonV0
        let matchesCurrentSurface: Bool
    }

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

    private struct Publication: Equatable, Sendable {
        let fence: Fence
        let candidate: InteractiveFocusEventCandidateV0
        let refreshAtMonotonicMilliseconds: UInt64
    }

    /// Accessibility can briefly alternate between the desktop and a focused
    /// element while an application replaces a large part of its hierarchy.
    /// Keep those advisory samples local until the same target has survived a
    /// bounded number of polls. Input-pausing and secure-focus observations
    /// remain immediate because they reduce authority rather than expand it.
    private struct Stabilization: Equatable, Sendable {
        let fence: Fence
        let candidate: InteractiveFocusEventCandidateV0
        var consecutiveSamples: Int
    }

    private let source: MacAgentFocusCandidateSourceAuthorityV1
    private let control: any InteractiveSurfaceControlDispatchingV0
    private var listener: MacAgentNetworkListenerRuntimeOwnerV1?
    private var context: (@Sendable () -> NetworkHostRequestContextV0)?
    private var loop: Task<Void, Never>?
    private var publication: Publication?
    private var stabilization: Stabilization?
    private var lastCandidateSummary: CandidateSummary?
    private var sampleUnavailable = false
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
        guard descriptor.interactionClasses.contains(.keyboard),
              descriptor.interactionClasses.contains(.text) else { return }
        let fence = Fence(descriptor)

        let candidate: InteractiveFocusEventCandidateV0
        do {
            candidate = try await source.candidate(current: descriptor)
        } catch {
            if !sampleUnavailable {
                macAgentFocusEventLoggerV1.notice(
                    "focus candidate sample unavailable"
                )
                sampleUnavailable = true
            }
            return
        }
        sampleUnavailable = false
        let fresh = context()
        let matchesCurrentSurface =
            candidate.recommendedTargetKind == descriptor.kind
            && candidate.focus == descriptor.focus
            && !candidate.inputPaused
        let summary = CandidateSummary(
            kind: candidate.recommendedTargetKind,
            hasFocus: candidate.focus != nil,
            editable: candidate.focus?.editable ?? false,
            secure: candidate.focus?.secure ?? false,
            inputPaused: candidate.inputPaused,
            reason: candidate.reason,
            matchesCurrentSurface: matchesCurrentSurface
        )
        if summary != lastCandidateSummary {
            macAgentFocusEventLoggerV1.notice(
                "focus candidate kind=\(summary.kind.rawValue, privacy: .public) hasFocus=\(summary.hasFocus, privacy: .public) editable=\(summary.editable, privacy: .public) secure=\(summary.secure, privacy: .public) inputPaused=\(summary.inputPaused, privacy: .public) reason=\(summary.reason.rawValue, privacy: .public) matchesCurrent=\(summary.matchesCurrentSurface, privacy: .public)"
            )
            lastCandidateSummary = summary
        }
        if matchesCurrentSurface,
           publication?.fence != fence {
            publication = nil
            stabilization = nil
            return
        }
        if let publication,
           publication.fence == fence,
           publication.candidate == candidate,
           fresh.monotonicNowMilliseconds
                < publication.refreshAtMonotonicMilliseconds {
            stabilization = nil
            return
        }
        let refreshingCurrentPublication = publication?.fence == fence
            && publication?.candidate == candidate
        if !refreshingCurrentPublication {
            if stabilization?.fence == fence,
               stabilization?.candidate == candidate {
                stabilization?.consecutiveSamples += 1
            } else {
                stabilization = Stabilization(
                    fence: fence,
                    candidate: candidate,
                    consecutiveSamples: 1
                )
            }
            guard let stabilization,
                  stabilization.consecutiveSamples
                    >= Self.requiredStableSamples(for: candidate) else {
                return
            }
        }
        stabilization = nil
        let hostContext: InteractiveFocusEventHostContextV0
        do {
            hostContext = try InteractiveFocusEventHostContextV0(
                hostState: fresh.hostState,
                wallNowUnixMilliseconds: fresh.wallNowUnixMilliseconds,
                monotonicNowMilliseconds: fresh.monotonicNowMilliseconds,
                eventMessageID: fresh.responseMessageID
            )
        } catch {
            publication = nil
            return
        }
        let prepared: InteractivePreparedFocusEventV0
        do {
            prepared = try await control.prepareFocusEvent(
                candidate: candidate,
                hostContext: hostContext
            )
        } catch {
            // The sampled descriptor/lease/primary snapshot may have become
            // stale across the local async read. No event was disclosed, so
            // discarding it is fail-closed without ending current Control.
            publication = nil
            return
        }
        do {
            try await listener.sendAuthenticatedEvent(
                prepared.eventJSON,
                primaryConnectionID: readiness.primaryConnectionID
            )
            let refreshInterval = UInt64(max(
                1,
                candidate.validForMilliseconds / 2
            ))
            let refreshAt = fresh.monotonicNowMilliseconds
                <= UInt64.max - refreshInterval
                ? fresh.monotonicNowMilliseconds + refreshInterval
                : UInt64.max
            publication = Publication(
                fence: fence,
                candidate: candidate,
                refreshAtMonotonicMilliseconds: refreshAt
            )
        } catch {
            // Preparation installed a one-use binding, but delivery on the
            // still-selected authenticated event lane is now ambiguous.
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
        publication = nil
        stabilization = nil
        lastCandidateSummary = nil
        sampleUnavailable = false
    }

    private static func requiredStableSamples(
        for candidate: InteractiveFocusEventCandidateV0
    ) -> Int {
        if candidate.inputPaused || candidate.focus?.secure == true {
            return 1
        }
        // Returning to the full desktop is intentionally slower so a
        // transient loss of Accessibility focus does not tear down and
        // recreate an otherwise useful focused capture.
        if candidate.recommendedTargetKind == .desktop { return 4 }
        return 2
    }
}
#endif
