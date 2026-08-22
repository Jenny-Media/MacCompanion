#if os(macOS)
import CompanionIPC
import Foundation

/// The only application authorities an authenticated menu receiver may invoke.
/// A public client initializer deliberately does not accept these surfaces;
/// package product composition must opt into Agent-to-menu presentation.
package struct MacLocalXPCMenuPresentationReceiverSurfacesV1: Sendable {
    package let pairingReviews: any LocalPairingReviewSurfaceV0
    package let hostIdentityRecovery: any LocalHostIdentityRecoverySurfaceV0
    package let nowUnixMilliseconds: @Sendable () -> Int64

    package init(
        pairingReviews: any LocalPairingReviewSurfaceV0,
        hostIdentityRecovery: any LocalHostIdentityRecoverySurfaceV0,
        nowUnixMilliseconds: @escaping @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.pairingReviews = pairingReviews
        self.hostIdentityRecovery = hostIdentityRecovery
        self.nowUnixMilliseconds = nowUnixMilliseconds
    }
}

package enum MacLocalXPCMenuPresentationReceiverErrorV1:
    Error,
    Equatable,
    Sendable
{
    case malformedPayload
    case recoveryReviewOutsideFreshWindow
    case conflictingRetainedPresentation
    case retainedStateChanged
}

package enum MacLocalXPCMenuPresentationPreparedMutationV1:
    Equatable,
    Sendable
{
    case acknowledgeWithoutMutation
    case presentPairingReview(LocalPairingReviewV0, canonicalPayload: Data)
    case withdrawPairingReview(reviewID: UUID)
    case presentHostRecoveryReview(
        LocalHostIdentityRecoveryReviewV0,
        canonicalPayload: Data
    )
    case presentHostRecoveryResume(
        LocalHostIdentityRecoveryCommandV0,
        canonicalPayload: Data
    )
    case withdrawHostRecovery(reviewID: UUID)

    package var exactPresentationTarget: (family: Family, reviewID: UUID)? {
        switch self {
        case .acknowledgeWithoutMutation:
            nil
        case .presentPairingReview(let review, _):
            (.pairing, review.reviewID)
        case .withdrawPairingReview(let reviewID):
            (.pairing, reviewID)
        case .presentHostRecoveryReview(let review, _):
            (.hostRecovery, review.reviewID)
        case .presentHostRecoveryResume(let command, _):
            (.hostRecovery, command.review.reviewID)
        case .withdrawHostRecovery(let reviewID):
            (.hostRecovery, reviewID)
        }
    }

    package enum Family: Sendable {
        case pairing
        case hostRecovery
    }

    package func execute(
        using surfaces: MacLocalXPCMenuPresentationReceiverSurfacesV1
    ) async throws {
        switch self {
        case .acknowledgeWithoutMutation:
            return
        case .presentPairingReview(let review, _):
            try await surfaces.pairingReviews.presentLocalPairingReview(review)
        case .withdrawPairingReview(let reviewID):
            await surfaces.pairingReviews.withdrawLocalPairingReview(
                reviewID: reviewID
            )
        case .presentHostRecoveryReview(let review, _):
            try await surfaces.hostIdentityRecovery
                .presentHostIdentityRecoveryReview(review)
        case .presentHostRecoveryResume(let command, _):
            try await surfaces.hostIdentityRecovery
                .presentHostIdentityRecoveryResume(command)
        case .withdrawHostRecovery(let reviewID):
            await surfaces.hostIdentityRecovery.withdrawHostIdentityRecovery(
                reviewID: reviewID
            )
        }
    }
}

/// Exact immutable values retained by one authenticated menu generation.
/// Preparation never mutates state. The caller applies a mutation only after
/// its presentation surface has returned successfully and before replying.
package struct MacLocalXPCMenuPresentationRetainedStateV1: Sendable {
    private struct Pairing: Sendable {
        let reviewID: UUID
        let canonicalPayload: Data
    }

    private enum RecoveryMode: Equatable, Sendable {
        case review
        case resume
    }

    private struct Recovery: Sendable {
        let reviewID: UUID
        let mode: RecoveryMode
        let canonicalPayload: Data
    }

    private var pairing: Pairing?
    private var recovery: Recovery?

    package init() {}

    package var pairingReviewID: UUID? { pairing?.reviewID }
    package var hostRecoveryReviewID: UUID? { recovery?.reviewID }

    package func prepare(
        _ request: MacLocalXPCMenuPresentationRequestV1,
        nowUnixMilliseconds: Int64
    ) throws -> MacLocalXPCMenuPresentationPreparedMutationV1 {
        switch request {
        case .pairingReview(let payload):
            guard let review = try? LocalMenuPresentationWireCodecV1
                .decodePairingReview(payload) else {
                throw MacLocalXPCMenuPresentationReceiverErrorV1
                    .malformedPayload
            }
            if let pairing {
                guard pairing.reviewID == review.reviewID,
                      pairing.canonicalPayload == payload else {
                    throw MacLocalXPCMenuPresentationReceiverErrorV1
                        .conflictingRetainedPresentation
                }
                return .acknowledgeWithoutMutation
            }
            return .presentPairingReview(review, canonicalPayload: payload)

        case .pairingWithdrawal(let reviewID):
            guard pairing?.reviewID == reviewID else {
                return .acknowledgeWithoutMutation
            }
            return .withdrawPairingReview(reviewID: reviewID)

        case .hostRecoveryReview(let payload):
            guard let review = try? LocalMenuPresentationWireCodecV1
                .decodeHostIdentityRecoveryReview(payload) else {
                throw MacLocalXPCMenuPresentationReceiverErrorV1
                    .malformedPayload
            }
            if let recovery {
                guard recovery.reviewID == review.reviewID,
                      recovery.mode == .review,
                      recovery.canonicalPayload == payload else {
                    throw MacLocalXPCMenuPresentationReceiverErrorV1
                        .conflictingRetainedPresentation
                }
                return .acknowledgeWithoutMutation
            }
            guard review.createdAtUnixMilliseconds <= nowUnixMilliseconds,
                  nowUnixMilliseconds < review.expiresAtUnixMilliseconds else {
                throw MacLocalXPCMenuPresentationReceiverErrorV1
                    .recoveryReviewOutsideFreshWindow
            }
            return .presentHostRecoveryReview(
                review,
                canonicalPayload: payload
            )

        case .hostRecoveryResume(let payload):
            guard let command = try? LocalMenuPresentationWireCodecV1
                .decodeHostIdentityRecoveryResume(payload) else {
                throw MacLocalXPCMenuPresentationReceiverErrorV1
                    .malformedPayload
            }
            if let recovery {
                guard recovery.reviewID == command.review.reviewID,
                      recovery.mode == .resume,
                      recovery.canonicalPayload == payload else {
                    throw MacLocalXPCMenuPresentationReceiverErrorV1
                        .conflictingRetainedPresentation
                }
                return .acknowledgeWithoutMutation
            }
            return .presentHostRecoveryResume(
                command,
                canonicalPayload: payload
            )

        case .hostRecoveryWithdrawal(let reviewID):
            guard recovery?.reviewID == reviewID else {
                return .acknowledgeWithoutMutation
            }
            return .withdrawHostRecovery(reviewID: reviewID)
        }
    }

    package mutating func apply(
        _ mutation: MacLocalXPCMenuPresentationPreparedMutationV1
    ) throws {
        switch mutation {
        case .acknowledgeWithoutMutation:
            return
        case .presentPairingReview(let review, let payload):
            guard pairing == nil else {
                throw MacLocalXPCMenuPresentationReceiverErrorV1
                    .retainedStateChanged
            }
            pairing = Pairing(
                reviewID: review.reviewID,
                canonicalPayload: payload
            )
        case .withdrawPairingReview(let reviewID):
            guard pairing?.reviewID == reviewID else {
                throw MacLocalXPCMenuPresentationReceiverErrorV1
                    .retainedStateChanged
            }
            pairing = nil
        case .presentHostRecoveryReview(let review, let payload):
            guard recovery == nil else {
                throw MacLocalXPCMenuPresentationReceiverErrorV1
                    .retainedStateChanged
            }
            recovery = Recovery(
                reviewID: review.reviewID,
                mode: .review,
                canonicalPayload: payload
            )
        case .presentHostRecoveryResume(let command, let payload):
            guard recovery == nil else {
                throw MacLocalXPCMenuPresentationReceiverErrorV1
                    .retainedStateChanged
            }
            recovery = Recovery(
                reviewID: command.review.reviewID,
                mode: .resume,
                canonicalPayload: payload
            )
        case .withdrawHostRecovery(let reviewID):
            guard recovery?.reviewID == reviewID else {
                throw MacLocalXPCMenuPresentationReceiverErrorV1
                    .retainedStateChanged
            }
            recovery = nil
        }
    }

    package mutating func takeRetainedPresentationIDs()
        -> (pairing: Set<UUID>, hostRecovery: Set<UUID>)
    {
        let result = (
            pairing: Set(pairing.map { [$0.reviewID] } ?? []),
            hostRecovery: Set(recovery.map { [$0.reviewID] } ?? [])
        )
        pairing = nil
        recovery = nil
        return result
    }
}

package struct MacLocalXPCMenuPresentationRetirementPlanV1: Sendable {
    package let pairingReviewIDs: Set<UUID>
    package let hostRecoveryReviewIDs: Set<UUID>

    package init(
        retainedState: inout MacLocalXPCMenuPresentationRetainedStateV1,
        activeMutation: MacLocalXPCMenuPresentationPreparedMutationV1?
    ) {
        self.init(
            retainedState: &retainedState,
            possiblyRetainedMutations: activeMutation.map { [$0] } ?? []
        )
    }

    package init(
        retainedState: inout MacLocalXPCMenuPresentationRetainedStateV1,
        possiblyRetainedMutations:
            [MacLocalXPCMenuPresentationPreparedMutationV1]
    ) {
        let retained = retainedState.takeRetainedPresentationIDs()
        var pairing = retained.pairing
        var recovery = retained.hostRecovery
        for mutation in possiblyRetainedMutations {
            guard let target = mutation.exactPresentationTarget else {
                continue
            }
            switch target.family {
            case .pairing:
                pairing.insert(target.reviewID)
            case .hostRecovery:
                recovery.insert(target.reviewID)
            }
        }
        pairingReviewIDs = pairing
        hostRecoveryReviewIDs = recovery
    }

    package func execute(
        using surfaces: MacLocalXPCMenuPresentationReceiverSurfacesV1
    ) async {
        for reviewID in pairingReviewIDs {
            await surfaces.pairingReviews.withdrawLocalPairingReview(
                reviewID: reviewID
            )
        }
        for reviewID in hostRecoveryReviewIDs {
            await surfaces.hostIdentityRecovery.withdrawHostIdentityRecovery(
                reviewID: reviewID
            )
        }
    }
}

package enum MacLocalXPCMenuPresentationRetirementBarrierV1 {
    package static func finish(
        awaiting activeTasks: [Task<Void, Never>],
        plan: MacLocalXPCMenuPresentationRetirementPlanV1,
        surfaces: MacLocalXPCMenuPresentationReceiverSurfacesV1
    ) async {
        for activeTask in activeTasks {
            await activeTask.value
        }
        await plan.execute(using: surfaces)
    }
}

package final class MacLocalXPCMenuPresentationScheduledDeadlineV1:
    @unchecked Sendable
{
    private let cancelBody: () -> Void

    package init(cancel: @escaping () -> Void) {
        cancelBody = cancel
    }

    package func cancel() { cancelBody() }
}

/// One queue-confined authenticated menu generation. Production and tests use
/// this exact owner for FIFO admission, request leasing, mutation completion,
/// acknowledgements, deadlines, terminal fencing, and retirement cleanup.
@available(macOS 26.0, *)
package final class MacLocalXPCMenuPresentationReceiverGenerationV1<Request>:
    @unchecked Sendable
{
    package typealias Enqueue = (@escaping @Sendable () -> Void) -> Void
    package typealias DeadlineScheduler = (
        DispatchTimeInterval,
        @escaping @Sendable () -> Void
    ) -> MacLocalXPCMenuPresentationScheduledDeadlineV1

    private final class Pending: @unchecked Sendable {
        let requestID: UUID
        let operation: UInt64
        let request: MacLocalXPCMenuPresentationRequestV1
        let lease: MacLocalXPCStatusRequestLeaseV1<Request>
        var mutation: MacLocalXPCMenuPresentationPreparedMutationV1?
        var task: Task<Void, Never>?
        var deadline: MacLocalXPCMenuPresentationScheduledDeadlineV1?

        init(
            requestID: UUID,
            operation: UInt64,
            request: MacLocalXPCMenuPresentationRequestV1,
            borrowedRequest: Request,
            retainRequest: (Request) -> Void,
            releaseRequest: @escaping (Request) -> Void
        ) {
            self.requestID = requestID
            self.operation = operation
            self.request = request
            lease = MacLocalXPCStatusRequestLeaseV1(
                request: borrowedRequest,
                retainRequest: retainRequest,
                releaseRequest: releaseRequest
            )
        }
    }

    package static var operationTimeout: DispatchTimeInterval { .seconds(2) }

    private let surfaces: MacLocalXPCMenuPresentationReceiverSurfacesV1
    private let retainRequest: (Request) -> Void
    private let releaseRequest: (Request) -> Void
    private let reply: (Request, MacLocalXPCMenuPresentationRequestV1) -> Bool
    private let enqueue: Enqueue
    private let scheduleDeadline: DeadlineScheduler
    private let onTerminal: () -> Void
    private let makeRequestID: () -> UUID
    private var fifo = MacLocalXPCMenuPresentationFIFOStateV1()
    private var pending: [UUID: Pending] = [:]
    private var retainedState = MacLocalXPCMenuPresentationRetainedStateV1()
    package private(set) var isTerminal = false

    package init(
        surfaces: MacLocalXPCMenuPresentationReceiverSurfacesV1,
        retainRequest: @escaping (Request) -> Void,
        releaseRequest: @escaping (Request) -> Void,
        reply: @escaping (
            Request,
            MacLocalXPCMenuPresentationRequestV1
        ) -> Bool,
        enqueue: @escaping Enqueue,
        scheduleDeadline: @escaping DeadlineScheduler,
        makeRequestID: @escaping () -> UUID = UUID.init,
        onTerminal: @escaping () -> Void
    ) {
        self.surfaces = surfaces
        self.retainRequest = retainRequest
        self.releaseRequest = releaseRequest
        self.reply = reply
        self.enqueue = enqueue
        self.scheduleDeadline = scheduleDeadline
        self.makeRequestID = makeRequestID
        self.onTerminal = onTerminal
    }

    package var pendingCount: Int { pending.count }
    package var retainedPairingReviewID: UUID? {
        retainedState.pairingReviewID
    }
    package var retainedHostRecoveryReviewID: UUID? {
        retainedState.hostRecoveryReviewID
    }

    package func receive(
        copiedRequest: MacLocalXPCMenuPresentationRequestV1?,
        borrowedRequest: Request,
        authenticatedAndReady: Bool,
        authorized: Bool
    ) {
        guard !isTerminal,
              authenticatedAndReady,
              authorized,
              let copiedRequest else {
            requestTerminalFence()
            return
        }
        let requestID = makeRequestID()
        guard pending[requestID] == nil else {
            requestTerminalFence()
            return
        }
        switch fifo.admit(requestID: requestID, cancelled: false) {
        case .admitted(let operation, let startsImmediately):
            pending[requestID] = Pending(
                requestID: requestID,
                operation: operation,
                request: copiedRequest,
                borrowedRequest: borrowedRequest,
                retainRequest: retainRequest,
                releaseRequest: releaseRequest
            )
            if startsImmediately { startHead() }
        case .cancelledBeforeAdmission, .overflow, .operationExhausted,
             .terminal:
            requestTerminalFence()
        }
    }

    package func retire()
        -> Task<Void, Never>
    {
        isTerminal = true
        let activeTasks = pending.values.compactMap(\.task)
        let possiblyRetainedMutations = pending.values.compactMap(\.mutation)
        _ = fifo.fence()
        for value in pending.values {
            value.deadline?.cancel()
            value.task?.cancel()
            value.lease.releaseIfOwned()
        }
        let plan = MacLocalXPCMenuPresentationRetirementPlanV1(
            retainedState: &retainedState,
            possiblyRetainedMutations: possiblyRetainedMutations
        )
        pending.removeAll()
        let surfaces = self.surfaces
        return Task {
            await MacLocalXPCMenuPresentationRetirementBarrierV1.finish(
                awaiting: activeTasks,
                plan: plan,
                surfaces: surfaces
            )
        }
    }

    private func startHead() {
        guard !isTerminal,
              let head = fifo.head,
              !head.sent,
              let value = pending[head.requestID],
              value.operation == head.operation,
              fifo.claimHeadForSend(
                requestID: head.requestID,
                operation: head.operation
              ) else {
            requestTerminalFence()
            return
        }
        let mutation: MacLocalXPCMenuPresentationPreparedMutationV1
        do {
            mutation = try retainedState.prepare(
                value.request,
                nowUnixMilliseconds: surfaces.nowUnixMilliseconds()
            )
        } catch {
            requestTerminalFence()
            return
        }
        value.mutation = mutation
        if mutation == .acknowledgeWithoutMutation {
            complete(
                requestID: value.requestID,
                operation: value.operation,
                succeeded: true
            )
            return
        }

        let requestID = value.requestID
        let operation = value.operation
        let surfaces = self.surfaces
        // Fix the absolute monotonic deadline before any asynchronous surface
        // effect can begin; task scheduling latency never extends the bound.
        value.deadline = scheduleDeadline(Self.operationTimeout) {
            [weak self] in
            self?.expire(requestID: requestID, operation: operation)
        }
        value.task = Task { [weak self, mutation, surfaces] in
            let succeeded: Bool
            do {
                try await mutation.execute(using: surfaces)
                succeeded = true
            } catch {
                succeeded = false
            }
            self?.enqueue { [weak self] in
                self?.complete(
                    requestID: requestID,
                    operation: operation,
                    succeeded: succeeded
                )
            }
        }
    }

    private func complete(
        requestID: UUID,
        operation: UInt64,
        succeeded: Bool
    ) {
        guard !isTerminal,
              fifo.admitsActiveCallback(
                requestID: requestID,
                operation: operation
              ),
              let value = pending[requestID],
              value.operation == operation,
              let mutation = value.mutation,
              succeeded else {
            if !isTerminal { requestTerminalFence() }
            return
        }
        value.deadline?.cancel()
        value.deadline = nil
        do {
            try retainedState.apply(mutation)
        } catch {
            requestTerminalFence()
            return
        }
        guard let ownedRequest = value.lease.takeOwnedRequest() else {
            requestTerminalFence()
            return
        }
        defer { releaseRequest(ownedRequest) }
        guard reply(ownedRequest, value.request) else {
            requestTerminalFence()
            return
        }
        value.task = nil
        pending.removeValue(forKey: requestID)
        guard fifo.completeHead(
            requestID: requestID,
            operation: operation
        ) else {
            requestTerminalFence()
            return
        }
        if fifo.head != nil { startHead() }
    }

    private func expire(requestID: UUID, operation: UInt64) {
        guard !isTerminal,
              fifo.admitsActiveCallback(
                requestID: requestID,
                operation: operation
              ) else {
            return
        }
        requestTerminalFence()
    }

    private func requestTerminalFence() {
        guard !isTerminal else { return }
        isTerminal = true
        _ = fifo.fence()
        onTerminal()
    }
}
#endif
