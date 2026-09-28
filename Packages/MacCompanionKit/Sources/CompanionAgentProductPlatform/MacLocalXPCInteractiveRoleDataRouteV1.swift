#if os(macOS)
import CompanionAgentNetworkPlatform
import CompanionInteractiveWire
import CompanionLocalXPCPlatform
import Foundation
import OSLog

private let macLocalXPCInteractiveRoleDataRouteLoggerV1 = Logger(
    subsystem: "media.jenny.maccompanion.agent",
    category: "interactive-role-data-route"
)

package enum MacLocalXPCInteractiveRoleDataRouteErrorV1:
    Error, Equatable, Sendable
{
    case unavailable
    case staleGeneration
    case duplicateOperation
    case pairMismatch
}

/// A zero-buffer rendezvous between the menu's authenticated XPC publication
/// and the exact network media role. The menu acknowledgement is withheld
/// until the role-data pump takes ownership of the complete record or the
/// exact retired pair takes ownership of discarding it.
@available(macOS 26.0, *)
package actor MacLocalXPCInteractiveRoleDataRouteV1:
    MacLocalXPCInteractiveMediaHandlingV1,
    AgentInteractiveMenuRoleDataRoutingV0
{
    private struct MediaFence: Hashable {
        let sessionID: UUID
        let epoch: UInt64
    }
    private var activeMediaFence: MediaFence?
    private var retiredMediaFences: [MediaFence] = []

    private struct Publication {
        let id: UUID
        let record: AgentInteractiveOutboundMediaRecordV0
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct Consumer {
        let id: UUID
        let generation: UInt64
        let pair: AgentInteractiveReadyRolePairV0
        let continuation: CheckedContinuation<
            AgentInteractiveOutboundMediaRecordV0?, any Error
        >
    }

    private var generation: UInt64?
    private var input: (any MacLocalXPCInteractiveInputSendingV1)?
    private var publication: Publication?
    private var consumer: Consumer?

    package init() {}

    package func bind(
        generation: UInt64,
        input: any MacLocalXPCInteractiveInputSendingV1
    ) throws {
        guard generation > 0, self.generation == nil,
              publication == nil, consumer == nil else {
            throw MacLocalXPCInteractiveRoleDataRouteErrorV1
                .duplicateOperation
        }
        self.generation = generation
        self.input = input
    }

    package func invalidate(generation: UInt64) {
        guard self.generation == generation else { return }
        self.generation = nil
        activeMediaFence = nil
        retiredMediaFences.removeAll()
        input = nil
        let publication = self.publication
        self.publication = nil
        publication?.continuation.resume(throwing:
            MacLocalXPCInteractiveRoleDataRouteErrorV1.staleGeneration
        )
        let consumer = self.consumer
        self.consumer = nil
        consumer?.continuation.resume(throwing:
            MacLocalXPCInteractiveRoleDataRouteErrorV1.staleGeneration
        )
    }

    package func publishInteractiveMedia(
        header: MediaRecordHeader,
        payload: Data,
        transportGeneration: UInt64
    ) async throws {
        let record = try AgentInteractiveOutboundMediaRecordV0(
            header: header,
            payload: payload
        )
        guard generation == transportGeneration else {
            macLocalXPCInteractiveRoleDataRouteLoggerV1.error(
                "media publication rejected: stale menu generation"
            )
            throw MacLocalXPCInteractiveRoleDataRouteErrorV1.staleGeneration
        }
        let fence = mediaFence(record.header)
        if retiredMediaFences.contains(fence) { return }
        if let activeMediaFence, activeMediaFence != fence {
            throw MacLocalXPCInteractiveRoleDataRouteErrorV1.pairMismatch
        }
        if let consumer {
            guard pair(consumer.pair, admits: record) else {
                macLocalXPCInteractiveRoleDataRouteLoggerV1.error(
                    "media publication rejected: role-pair fence mismatch"
                )
                throw MacLocalXPCInteractiveRoleDataRouteErrorV1.pairMismatch
            }
            self.consumer = nil
            consumer.continuation.resume(returning: record)
            return
        }
        guard publication == nil else {
            macLocalXPCInteractiveRoleDataRouteLoggerV1.error(
                "media publication rejected: duplicate publication"
            )
            throw MacLocalXPCInteractiveRoleDataRouteErrorV1
                .duplicateOperation
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                publication = Publication(
                    id: id,
                    record: record,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { await self.cancelPublication(id: id) }
        }
    }

    package func invalidateInteractiveMedia(
        transportGeneration: UInt64
    ) {
        invalidate(generation: transportGeneration)
    }

    package func applyInteractiveInput(
        _ envelope: InteractiveInputEnvelope,
        pair: AgentInteractiveReadyRolePairV0,
        nowMonotonicNanoseconds _: UInt64
    ) async throws {
        guard let generation, let input else {
            throw MacLocalXPCInteractiveRoleDataRouteErrorV1.staleGeneration
        }
        guard envelope.interactiveSessionID.rawValue
                == pair.interactiveSessionID,
              envelope.authorizationEpoch == pair.authorizationEpoch else {
            throw MacLocalXPCInteractiveRoleDataRouteErrorV1.pairMismatch
        }
        try await input.applyInteractiveInput(envelope)
        guard self.generation == generation else {
            throw MacLocalXPCInteractiveRoleDataRouteErrorV1.staleGeneration
        }
    }

    package func nextInteractiveMediaRecord(
        pair: AgentInteractiveReadyRolePairV0
    ) async throws -> AgentInteractiveOutboundMediaRecordV0? {
        guard let generation else {
            throw MacLocalXPCInteractiveRoleDataRouteErrorV1.unavailable
        }
        let fence = mediaFence(pair)
        guard !retiredMediaFences.contains(fence),
              activeMediaFence == nil || activeMediaFence == fence else {
            throw MacLocalXPCInteractiveRoleDataRouteErrorV1.pairMismatch
        }
        activeMediaFence = fence
        if let publication {
            guard self.pair(pair, admits: publication.record) else {
                macLocalXPCInteractiveRoleDataRouteLoggerV1.error(
                    "media consumer rejected: publication fence mismatch"
                )
                throw MacLocalXPCInteractiveRoleDataRouteErrorV1.pairMismatch
            }
            self.publication = nil
            publication.continuation.resume()
            return publication.record
        }
        guard consumer == nil else {
            macLocalXPCInteractiveRoleDataRouteLoggerV1.error(
                "media consumer rejected: duplicate consumer"
            )
            throw MacLocalXPCInteractiveRoleDataRouteErrorV1
                .duplicateOperation
        }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                consumer = Consumer(
                    id: id,
                    generation: generation,
                    pair: pair,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { await self.cancelConsumer(id: id) }
        }
    }

    package func retireInteractiveMedia(pair: AgentInteractiveReadyRolePairV0) {
        guard generation != nil else { return }
        let fence = mediaFence(pair)
        guard activeMediaFence == fence || publication.map({ mediaFence($0.record.header) == fence }) == true
            || consumer.map({ mediaFence($0.pair) == fence }) == true else { return }
        if activeMediaFence == fence { activeMediaFence = nil }
        if !retiredMediaFences.contains(fence) {
            retiredMediaFences.append(fence)
            if retiredMediaFences.count > 32 { retiredMediaFences.removeFirst() }
        }
        if let publication, mediaFence(publication.record.header) == fence {
            self.publication = nil
            publication.continuation.resume()
        }
        if let consumer, mediaFence(consumer.pair) == fence {
            self.consumer = nil
            consumer.continuation.resume(throwing: CancellationError())
        }
    }

    private func mediaFence(_ pair: AgentInteractiveReadyRolePairV0) -> MediaFence {
        .init(sessionID: pair.interactiveSessionID, epoch: pair.authorizationEpoch.rawValue)
    }
    private func mediaFence(_ header: MediaRecordHeader) -> MediaFence {
        .init(sessionID: header.interactiveSessionID, epoch: header.authorizationEpoch.rawValue)
    }

    private func pair(
        _ pair: AgentInteractiveReadyRolePairV0,
        admits record: AgentInteractiveOutboundMediaRecordV0
    ) -> Bool {
        record.header.interactiveSessionID == pair.interactiveSessionID
            && record.header.authorizationEpoch == pair.authorizationEpoch
    }

    private func cancelPublication(id: UUID) {
        guard publication?.id == id else { return }
        let publication = self.publication
        self.publication = nil
        publication?.continuation.resume(throwing: CancellationError())
    }

    private func cancelConsumer(id: UUID) {
        guard consumer?.id == id else { return }
        let consumer = self.consumer
        self.consumer = nil
        consumer?.continuation.resume(throwing: CancellationError())
    }
}
#endif
