#if os(macOS)
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionLocalXPCPlatform
import Foundation

/// Product wrapper that owns the sole queue-to-XPC drain for one menu client.
/// It transfers a complete record only after dequeue and never dequeues the
/// next record until the exact local-XPC acknowledgement arrives.
@available(macOS 26.0, *)
package final class MacLocalXPCInteractiveMediaDrainClientV1:
    MacLocalXPCDashboardClientV1,
    @unchecked Sendable
{
    private let client: any MacLocalXPCDashboardClientV1
    private let mediaQueue: BoundedInteractiveMediaQueueV0
    private let lock = NSLock()
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var handlerToken: UUID?
    private var drainTask: Task<Void, Never>?
    private var stopped = false

    package init(
        client: any MacLocalXPCDashboardClientV1,
        mediaQueue: BoundedInteractiveMediaQueueV0
    ) {
        self.client = client
        self.mediaQueue = mediaQueue
        let pair = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        stream = pair.stream
        continuation = pair.continuation
    }

    deinit {
        stopDrain(cancelClient: false)
    }

    package func start() throws {
        do {
            try lock.withLock {
                guard !stopped,
                      handlerToken == nil,
                      drainTask == nil else {
                    throw MacLocalXPCConstructionErrorV1.alreadyStarted
                }
                try client.start()
                let token = UUID()
                guard mediaQueue.installEnqueuedHandler(token: token, {
                    [continuation] in
                    continuation.yield(())
                }) else {
                    throw MacLocalXPCConstructionErrorV1.invalidProfile
                }
                handlerToken = token
                let stream = self.stream
                drainTask = Task { [weak self] in
                    for await _ in stream {
                        guard let self, !Task.isCancelled else { return }
                        while let record = mediaQueue.dequeue() {
                            guard !Task.isCancelled else { return }
                            do {
                                try await client.publishInteractiveMedia(
                                    header: record.header,
                                    payload: record.payload
                                )
                            } catch {
                                stopDrain(cancelClient: true)
                                return
                            }
                        }
                    }
                }
            }
        } catch {
            stopDrain(cancelClient: true)
            throw error
        }
    }

    package func publishMenuReady() { client.publishMenuReady() }
    package func readAgentStatus() { client.readAgentStatus() }

    package func createPairingSession(
        _ command: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0 {
        try await client.createPairingSession(command)
    }

    package func dismissPairingSession(
        _ command: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0 {
        try await client.dismissPairingSession(command)
    }

    package func resolveLocalApproval(
        _ command: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0 {
        try await client.resolveLocalApproval(command)
    }

    package func makeInteractiveControlGrantReview(
        _ request: LocalInteractiveControlGrantReviewRequestV0
    ) async throws -> LocalInteractiveControlGrantReviewV0 {
        try await client.makeInteractiveControlGrantReview(request)
    }

    package func decideInteractiveControlGrant(
        _ command: LocalGrantDecisionCommandV0
    ) async throws -> LocalGrantDecisionReceiptV0 {
        try await client.decideInteractiveControlGrant(command)
    }

    package func recoverHostIdentity(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws -> LocalHostIdentityRecoveredReceiptV0 {
        try await client.recoverHostIdentity(command)
    }

    package func closeNetworkAdmissionForUpdate() async throws {
        try await client.closeNetworkAdmissionForUpdate()
    }

    package func drainNetworkConnectionsForUpdate() async throws {
        try await client.drainNetworkConnectionsForUpdate()
    }

    package func reopenNetworkAdmissionAfterUpdateFailure() async throws {
        try await client.reopenNetworkAdmissionAfterUpdateFailure()
    }

    package func publishInteractiveAdmission(
        _ publication: LocalInteractiveAdmissionPublicationV1
    ) async throws -> LocalInteractiveAdmissionPublishedReceiptV1 {
        try await client.publishInteractiveAdmission(publication)
    }

    package func cancel() {
        stopDrain(cancelClient: true)
    }

    package func finishMenuPresentationReceiver() async {
        stopDrain(cancelClient: false)
        await client.finishMenuPresentationReceiver()
    }

    private func stopDrain(cancelClient: Bool) {
        let value = lock.withLock {
            guard !stopped else {
                return (
                    nil as UUID?,
                    nil as Task<Void, Never>?,
                    false
                )
            }
            stopped = true
            let value = (handlerToken, drainTask, true)
            handlerToken = nil
            drainTask = nil
            return value
        }
        if let token = value.0 {
            mediaQueue.removeEnqueuedHandler(token: token)
        }
        continuation.finish()
        value.1?.cancel()
        if cancelClient, value.2 { client.cancel() }
    }
}
#endif
