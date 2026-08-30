#if os(macOS)
import CompanionIPC
import CompanionLocalXPCPlatformC
import Dispatch
import Foundation

public enum MacLocalXPCRemoteAccessBootstrapClientEventV1:
    Equatable,
    Sendable
{
    case authenticatedAgent(generation: UInt64)
    case offer(
        generation: UInt64,
        offer: LocalRemoteAccessBootstrapOfferV0
    )
    case enabled(
        generation: UInt64,
        receipt: LocalRemoteAccessEnabledReceiptV0
    )
    case invalidated(generation: UInt64)
}

/// Dedicated menu-side client for the one-use disabled-Agent exchange. It has
/// no readiness, status, presentation, pairing, diagnostic, or remote
/// capability methods. Every callback is fenced by one client generation and
/// every borrowed payload is copied before the C callback returns.
@available(macOS 26.0, *)
public final class MacLocalXPCRemoteAccessBootstrapClientV1:
    @unchecked Sendable
{
    public typealias EventHandler = @Sendable (
        MacLocalXPCRemoteAccessBootstrapClientEventV1
    ) -> Void

    package static let handshakeTimeoutSeconds = 10
    package static let operationTimeoutSeconds = 6

    private let queue = DispatchQueue(
        label: "media.jenny.maccompanion.local-xpc.bootstrap-menu"
    )
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let onEvent: EventHandler
    private var session: MCLocalXPCSessionRef?
    private var handshake = MacLocalXPCHandshakeGateV1()
    private var generationGate = MacLocalXPCClientGenerationGateV1()
    private var transaction =
        MacLocalXPCRemoteAccessBootstrapTransactionGateV1()
    private var handshakeDeadline: DispatchWorkItem?
    private var operationDeadline: DispatchWorkItem?
    private var terminalGeneration: UInt64?

    public init(onEvent: @escaping EventHandler) {
        self.onEvent = onEvent
        queue.setSpecific(key: queueKey, value: 1)
    }

    #if DEBUG
    private var isolatedTestID: UUID?

    public convenience init(isolatedTestID: UUID, onEvent: @escaping EventHandler) {
        self.init(onEvent: onEvent)
        self.isolatedTestID = isolatedTestID
    }
    #endif

    private var serviceName: String {
        #if DEBUG
        if let isolatedTestID {
            return MacLocalXPCIsolatedTestAddressV1.serviceName(isolatedTestID)
        }
        #endif
        return MacLocalXPCIdentityV1.serviceName
    }

    deinit {
        cancel()
    }

    public func start() throws {
        try syncOnQueue {
            guard session == nil else {
                throw MacLocalXPCConstructionErrorV1.alreadyStarted
            }
            var result = MCLocalXPCResultOK
            guard let requirement =
                    MCLocalXPCPeerRequirementCreateSameTeamIdentifier(
                        MacLocalXPCIdentityV1.agentSigningIdentifier,
                        &result
                    ),
                  result == MCLocalXPCResultOK else {
                throw MacLocalXPCConstructionErrorV1.peerRequirement
            }
            guard let generation = generationGate.begin() else {
                MCLocalXPCPeerRequirementRelease(requirement)
                throw MacLocalXPCConstructionErrorV1.generationExhausted
            }

            handshake = MacLocalXPCHandshakeGateV1()
            transaction.invalidateAll()
            precondition(transaction.bind(generation: generation))
            terminalGeneration = nil
            cancelDeadlines()

            guard let candidate = MCLocalXPCSessionCreateInactive(
                serviceName,
                queue,
                &result
            ), result == MCLocalXPCResultOK else {
                _ = generationGate.invalidate(generation: generation)
                _ = transaction.invalidate(generation: generation)
                MCLocalXPCPeerRequirementRelease(requirement)
                throw MacLocalXPCConstructionErrorV1.sessionConstruction
            }
            MCLocalXPCSessionSetPeerRequirement(candidate, requirement)
            MCLocalXPCPeerRequirementRelease(requirement)
            MCLocalXPCSessionSetCancelHandler(candidate) { [weak self] in
                self?.handleInvalidation(generation: generation)
            }
            MCLocalXPCSessionSetMessageHandler(candidate) { [weak self] _ in
                self?.invalidateOwnedSession(generation: generation)
            }
            guard MCLocalXPCSessionActivate(candidate)
                    == MCLocalXPCResultOK else {
                _ = generationGate.invalidate(generation: generation)
                _ = transaction.invalidate(generation: generation)
                MCLocalXPCSessionDisposeAfterFailedActivation(candidate)
                throw MacLocalXPCConstructionErrorV1.activation
            }
            session = candidate
            installHandshakeDeadline(generation: generation)
            MCLocalXPCSessionSendHello(candidate) {
                [weak self] reply, hadError in
                var ignoredBuild: UInt64 = 0
                let exact = reply.map {
                    MCLocalXPCMessageGetExactHelloAcknowledgementBuild(
                        $0,
                        &ignoredBuild
                    )
                } ?? false
                self?.handleHelloReply(
                    generation: generation,
                    exactAcknowledgement: exact,
                    hadError: hadError
                )
            }
        }
    }

    public func readOffer() {
        queue.async { [weak self] in self?.sendOfferRead() }
    }

    public func enable(_ command: LocalRemoteAccessEnableCommandV0) {
        queue.async { [weak self] in self?.sendEnable(command) }
    }

    public func cancel() {
        syncOnQueue {
            guard let generation = generationGate.currentGeneration else {
                return
            }
            invalidateOwnedSession(generation: generation)
        }
    }

    private func handleHelloReply(
        generation: UInt64,
        exactAcknowledgement: Bool,
        hadError: Bool
    ) {
        guard generationGate.admitsCallback(generation: generation),
              session != nil,
              !hadError,
              handshake.receive(exactHello: exactAcknowledgement)
                == .acknowledgeAndAuthenticate else {
            invalidateOwnedSession(generation: generation)
            return
        }
        handshakeDeadline?.cancel()
        handshakeDeadline = nil
        onEvent(.authenticatedAgent(generation: generation))
    }

    private func sendOfferRead() {
        guard let generation = generationGate.currentGeneration else { return }
        guard let session,
              let operation = transaction.beginOfferRead(
                generation: generation,
                permitted:
                    handshake.state == .authenticated
                    && authorizes(.readRemoteAccessBootstrap)
              ) else {
            invalidateOwnedSession(generation: generation)
            return
        }
        MCLocalXPCSessionSendRemoteAccessBootstrapRead(session) {
            [weak self] payload, payloadLength, malformed in
            let data = payload.map { Data(bytes: $0, count: payloadLength) }
            self?.handleOfferReply(
                generation: generation,
                operation: operation,
                payload: data,
                malformedOrTransportError: malformed
            )
        }
        installOperationDeadline(
            generation: generation,
            operation: operation
        )
    }

    private func handleOfferReply(
        generation: UInt64,
        operation: UInt64,
        payload: Data?,
        malformedOrTransportError: Bool
    ) {
        guard generationGate.admitsCallback(generation: generation),
              session != nil,
              handshake.state == .authenticated,
              !malformedOrTransportError,
              let payload,
              let offer = try?
                LocalRemoteAccessBootstrapWireCodecV1.decodeOffer(payload),
              transaction.finishOfferRead(
                generation: generation,
                operation: operation,
                offer: offer
              ) else {
            invalidateOwnedSession(generation: generation)
            return
        }
        operationDeadline?.cancel()
        operationDeadline = nil
        onEvent(.offer(generation: generation, offer: offer))
    }

    private func sendEnable(_ command: LocalRemoteAccessEnableCommandV0) {
        guard let generation = generationGate.currentGeneration else { return }
        guard let session,
              let payload = try?
                LocalRemoteAccessBootstrapWireCodecV1
                    .encodeEnableCommand(command),
              let operation = transaction.beginEnable(
                generation: generation,
                permitted:
                    handshake.state == .authenticated
                    && authorizes(.enableRemoteAccess),
                command: command
              ) else {
            invalidateOwnedSession(generation: generation)
            return
        }
        let sendResult = payload.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            else { return MCLocalXPCResultConstructionFailed }
            return MCLocalXPCSessionSendRemoteAccessEnable(
                session,
                bytes,
                payload.count
            ) { [weak self] replyPayload, replyLength, malformed in
                let data = replyPayload.map {
                    Data(bytes: $0, count: replyLength)
                }
                self?.handleEnableReply(
                    generation: generation,
                    operation: operation,
                    payload: data,
                    malformedOrTransportError: malformed
                )
            }
        }
        guard sendResult == MCLocalXPCResultOK else {
            invalidateOwnedSession(generation: generation)
            return
        }
        installOperationDeadline(
            generation: generation,
            operation: operation
        )
    }

    private func handleEnableReply(
        generation: UInt64,
        operation: UInt64,
        payload: Data?,
        malformedOrTransportError: Bool
    ) {
        guard generationGate.admitsCallback(generation: generation),
              session != nil,
              handshake.state == .authenticated,
              !malformedOrTransportError,
              let payload,
              let receipt = try?
                LocalRemoteAccessBootstrapWireCodecV1
                    .decodeEnabledReceipt(payload),
              transaction.finishEnable(
                generation: generation,
                operation: operation,
                receipt: receipt
              ) else {
            invalidateOwnedSession(generation: generation)
            return
        }
        operationDeadline?.cancel()
        operationDeadline = nil
        terminalGeneration = generation
        onEvent(.enabled(generation: generation, receipt: receipt))
        closeTerminalSession(generation: generation)
    }

    private func installHandshakeDeadline(generation: UInt64) {
        let deadline = DispatchWorkItem { [weak self] in
            guard let self,
                  generationGate.admitsCallback(generation: generation),
                  handshake.state != .authenticated else { return }
            invalidateOwnedSession(generation: generation)
        }
        handshakeDeadline = deadline
        queue.asyncAfter(
            deadline: .now() + .seconds(Self.handshakeTimeoutSeconds),
            execute: deadline
        )
    }

    private func installOperationDeadline(
        generation: UInt64,
        operation: UInt64
    ) {
        let deadline = DispatchWorkItem { [weak self] in
            guard let self,
                  generationGate.admitsCallback(generation: generation),
                  transaction.fail(
                    generation: generation,
                    operation: operation
                  ) else { return }
            invalidateOwnedSession(generation: generation)
        }
        operationDeadline = deadline
        queue.asyncAfter(
            deadline: .now() + .seconds(Self.operationTimeoutSeconds),
            execute: deadline
        )
    }

    private func authorizes(_ method: LocalIPCMethod) -> Bool {
        do {
            try LocalIPCAuthorizationPolicy.authorize(
                authenticatedCaller: .menuApp,
                endpoint: .agent,
                method: method,
                version: .init()
            )
            return true
        } catch {
            return false
        }
    }

    private func closeTerminalSession(generation: UInt64) {
        guard generationGate.admitsCallback(generation: generation),
              let session else { return }
        _ = generationGate.invalidate(generation: generation)
        handshake.invalidate()
        _ = transaction.invalidate(generation: generation)
        self.session = nil
        cancelDeadlines()
        MCLocalXPCSessionCancelOwned(session)
    }

    private func invalidateOwnedSession(generation: UInt64) {
        guard generationGate.admitsCallback(generation: generation),
              let session else { return }
        let shouldPublish = terminalGeneration != generation
        _ = generationGate.invalidate(generation: generation)
        handshake.invalidate()
        _ = transaction.invalidate(generation: generation)
        self.session = nil
        cancelDeadlines()
        MCLocalXPCSessionCancelOwned(session)
        if shouldPublish { onEvent(.invalidated(generation: generation)) }
    }

    private func handleInvalidation(generation: UInt64) {
        guard generationGate.admitsCallback(generation: generation),
              let session else { return }
        let shouldPublish = terminalGeneration != generation
            && handshake.state != .invalidated
        _ = generationGate.invalidate(generation: generation)
        handshake.invalidate()
        _ = transaction.invalidate(generation: generation)
        self.session = nil
        cancelDeadlines()
        MCLocalXPCSessionRelease(session)
        if shouldPublish { onEvent(.invalidated(generation: generation)) }
    }

    private func cancelDeadlines() {
        handshakeDeadline?.cancel()
        handshakeDeadline = nil
        operationDeadline?.cancel()
        operationDeadline = nil
    }

    private func syncOnQueue<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try body()
        }
        return try queue.sync(execute: body)
    }
}
#endif
