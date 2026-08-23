#if os(macOS)
import CompanionAgentNetworkPlatform
import CompanionInteractiveWire
import CompanionLocalXPCPlatform
import Foundation

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
/// until the role-data pump takes ownership of the complete record.
@available(macOS 26.0, *)
package actor MacLocalXPCInteractiveRoleDataRouteV1:
    MacLocalXPCInteractiveMediaHandlingV1,
    AgentInteractiveMenuRoleDataRoutingV0
{
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
            throw MacLocalXPCInteractiveRoleDataRouteErrorV1.staleGeneration
        }
        if let consumer {
            guard pair(consumer.pair, admits: record) else {
                throw MacLocalXPCInteractiveRoleDataRouteErrorV1.pairMismatch
            }
            self.consumer = nil
            consumer.continuation.resume(returning: record)
            return
        }
        guard publication == nil else {
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
        if let publication {
            guard self.pair(pair, admits: publication.record) else {
                throw MacLocalXPCInteractiveRoleDataRouteErrorV1.pairMismatch
            }
            self.publication = nil
            publication.continuation.resume()
            return publication.record
        }
        guard consumer == nil else {
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
