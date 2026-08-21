import CompanionWire
import Foundation

public protocol ClientAuthenticatedCommandSendingV1: Sendable {
    func sendAuthenticatedCommand(_ frame: Data) async throws
}

public struct ClientActChannelEnvironmentV1: Sendable {
    public let makeMessageID: @Sendable () throws -> WireUUID
    public let wallNowUnixMilliseconds: @Sendable () -> Int64

    public init(
        makeMessageID: @escaping @Sendable () throws -> WireUUID,
        wallNowUnixMilliseconds: @escaping @Sendable () -> Int64
    ) {
        self.makeMessageID = makeMessageID
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
    }

    public static let live = Self(
        makeMessageID: { WireUUID(UUID()) },
        wallNowUnixMilliseconds: {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        }
    )
}

public enum ClientActChannelStateV1: String, Equatable, Sendable {
    case idle
    case loadingCatalog
    case ready
    case operating
    case invalidated
}

public enum ClientActRequestKindV1: String, Equatable, Sendable {
    case catalog
    case operation
}

public enum ClientActChannelEventV1: Equatable, Sendable {
    case catalogPublished(GrantedCapabilityCatalogV1)
    case operationState(ClientOperationSessionStateV1)
    case operationApprovalSubmitted(ClientOperationApprovalPromptV1)
    case remoteError(
        request: ClientActRequestKindV1,
        error: ClientOperationRemoteErrorV1
    )
}

public enum ClientActChannelErrorV1: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidState(ClientActChannelStateV1)
    case invalidClock
    case duplicateMessageID
    case sendFailed
    case invalidCorrelation
    case unexpectedMessage(WireMessageKind)
    case catalogRejected
    case operationRejected
    case invalidated
}

/// Catalog and single-operation owner for one already-authenticated primary
/// command channel. Network identity and framing remain outside this actor.
public actor ClientActChannelV1 {
    public private(set) var state: ClientActChannelStateV1 = .idle
    public private(set) var catalog: GrantedCapabilityCatalogV1?

    private let pairedHost: ClientDurablePairedHostV0
    private let authenticatedSession: ClientAuthenticatedSessionV0
    private let signer: any ClientOperationApprovalSigningV1
    private let sender: any ClientAuthenticatedCommandSendingV1
    private let environment: ClientActChannelEnvironmentV1
    private var assembler = CapabilityCatalogAssemblerV1()
    private var pendingCatalogMessageID: WireUUID?
    private var activeOperation: ClientOperationSessionV1?
    private var generation: UInt64 = 0
    private var issuedMessageIDs: [WireUUID] = []
    private var issuedMessageIDSet: Set<WireUUID> = []

    public init(
        pairedHost: ClientDurablePairedHostV0,
        authenticatedSession: ClientAuthenticatedSessionV0,
        signer: any ClientOperationApprovalSigningV1,
        sender: any ClientAuthenticatedCommandSendingV1,
        environment: ClientActChannelEnvironmentV1 = .live
    ) throws {
        guard pairedHost.clientID == authenticatedSession.clientID,
              pairedHost.hostID == authenticatedSession.hostID,
              pairedHost.deviceID == authenticatedSession.deviceID,
              pairedHost.hostFingerprint.count == 32,
              authenticatedSession.connectionID.count == 16,
              authenticatedSession.deviceState == .activeMonitorOnly
                || authenticatedSession.deviceState == .activeGranted else {
            throw ClientActChannelErrorV1.invalidConfiguration
        }
        self.pairedHost = pairedHost
        self.authenticatedSession = authenticatedSession
        self.signer = signer
        self.sender = sender
        self.environment = environment
    }

    public func reloadCatalog() async throws {
        guard state == .idle || state == .ready else {
            throw ClientActChannelErrorV1.invalidState(state)
        }
        catalog = nil
        activeOperation = nil
        assembler.invalidate()
        let request: CapabilityRegistryRequestBody
        do {
            request = try assembler.begin()
        } catch {
            throw ClientActChannelErrorV1.catalogRejected
        }
        state = .loadingCatalog
        do {
            try await sendCatalogRequest(request)
        } catch {
            assembler.invalidate()
            pendingCatalogMessageID = nil
            state = .invalidated
            throw error
        }
    }

    public func receive(
        _ responseJSON: Data
    ) async throws -> ClientActChannelEventV1? {
        switch state {
        case .loadingCatalog:
            return try await receiveCatalog(responseJSON)
        case .operating:
            return try await receiveOperation(responseJSON)
        case .idle, .ready:
            let kind = try messageKind(responseJSON)
            await invalidate()
            throw ClientActChannelErrorV1.unexpectedMessage(kind)
        case .invalidated:
            throw ClientActChannelErrorV1.invalidated
        }
    }

    public func beginOperation(
        capabilityID: String,
        parameters: CanonicalJSONValue,
        operationID: WireUUID
    ) async throws -> ClientActChannelEventV1 {
        guard state == .ready, let catalog else {
            throw ClientActChannelErrorV1.invalidState(state)
        }
        let operation: ClientOperationSessionV1
        do {
            operation = try ClientOperationSessionV1(
                operationID: operationID,
                capabilityID: capabilityID,
                pairedHost: pairedHost,
                authenticatedSession: authenticatedSession,
                catalog: catalog,
                signer: signer,
                wallNowUnixMilliseconds: environment.wallNowUnixMilliseconds
            )
            let frame = try await operation.begin(
                parameters: parameters,
                messageID: nextMessageID(),
                sentAtUnixMilliseconds: try now()
            )
            activeOperation = operation
            state = .operating
            return await sendOperationFrame(frame, operation: operation)
        } catch let error as ClientActChannelErrorV1 {
            throw error
        } catch {
            throw ClientActChannelErrorV1.operationRejected
        }
    }

    public func resumeOperationStatus(
        capabilityID: String,
        operationID: WireUUID
    ) async throws -> ClientActChannelEventV1 {
        guard state == .ready, let catalog else {
            throw ClientActChannelErrorV1.invalidState(state)
        }
        do {
            let operation = try ClientOperationSessionV1(
                operationID: operationID,
                capabilityID: capabilityID,
                pairedHost: pairedHost,
                authenticatedSession: authenticatedSession,
                catalog: catalog,
                signer: signer,
                wallNowUnixMilliseconds: environment.wallNowUnixMilliseconds
            )
            try await operation.resumeExistingOperationForStatus()
            let frame = try await operation.requestStatus(
                messageID: nextMessageID(),
                sentAtUnixMilliseconds: try now()
            )
            activeOperation = operation
            state = .operating
            return await sendOperationFrame(frame, operation: operation)
        } catch let error as ClientActChannelErrorV1 {
            throw error
        } catch {
            throw ClientActChannelErrorV1.operationRejected
        }
    }

    public func queryOperation() async throws -> ClientActChannelEventV1 {
        guard state == .operating, let activeOperation else {
            throw ClientActChannelErrorV1.invalidState(state)
        }
        do {
            let frame = try await activeOperation.requestStatus(
                messageID: nextMessageID(),
                sentAtUnixMilliseconds: try now()
            )
            return await sendOperationFrame(frame, operation: activeOperation)
        } catch let error as ClientActChannelErrorV1 {
            throw error
        } catch {
            throw ClientActChannelErrorV1.operationRejected
        }
    }

    public func cancelOperation() async throws -> ClientActChannelEventV1 {
        guard state == .operating, let activeOperation else {
            throw ClientActChannelErrorV1.invalidState(state)
        }
        do {
            let frame = try await activeOperation.requestCancel(
                messageID: nextMessageID(),
                sentAtUnixMilliseconds: try now()
            )
            return await sendOperationFrame(frame, operation: activeOperation)
        } catch let error as ClientActChannelErrorV1 {
            throw error
        } catch {
            throw ClientActChannelErrorV1.operationRejected
        }
    }

    public func finishOperation() async throws {
        guard state == .operating, let activeOperation else {
            throw ClientActChannelErrorV1.invalidState(state)
        }
        let operationState = await activeOperation.state
        switch operationState {
        case .terminal, .remoteRejected:
            await activeOperation.invalidate()
            self.activeOperation = nil
            state = .ready
        default:
            throw ClientActChannelErrorV1.operationRejected
        }
    }

    public func operationState() async -> ClientOperationSessionStateV1? {
        await activeOperation?.state
    }

    public func invalidate() async {
        generation &+= 1
        pendingCatalogMessageID = nil
        assembler.invalidate()
        catalog = nil
        if let activeOperation { await activeOperation.invalidate() }
        activeOperation = nil
        state = .invalidated
    }

    private func receiveCatalog(
        _ responseJSON: Data
    ) async throws -> ClientActChannelEventV1? {
        guard let pendingCatalogMessageID else {
            await invalidate()
            throw ClientActChannelErrorV1.invalidCorrelation
        }
        let kind = try messageKind(responseJSON)
        if kind == .error {
            let response = try WireCodec.decode(
                WireEnvelope<ProtocolErrorResponseBody>.self,
                from: responseJSON
            )
            guard response.correlationID == pendingCatalogMessageID else {
                await invalidate()
                throw ClientActChannelErrorV1.invalidCorrelation
            }
            self.pendingCatalogMessageID = nil
            assembler.invalidate()
            state = .idle
            return .remoteError(
                request: .catalog,
                error: ClientOperationRemoteErrorV1(response.body)
            )
        }
        guard kind == .capabilityRegistryResponse else {
            await invalidate()
            throw ClientActChannelErrorV1.unexpectedMessage(kind)
        }
        do {
            let response = try WireCodec.decode(
                WireEnvelope<CapabilityRegistryResponseBody>.self,
                from: responseJSON
            )
            guard response.correlationID == pendingCatalogMessageID else {
                throw ClientActChannelErrorV1.invalidCorrelation
            }
            self.pendingCatalogMessageID = nil
            if let continuation = try assembler.accept(response.body) {
                try await sendCatalogRequest(continuation)
                return nil
            }
            guard let complete = assembler.catalog else {
                throw ClientActChannelErrorV1.catalogRejected
            }
            catalog = complete
            state = .ready
            return .catalogPublished(complete)
        } catch let error as ClientActChannelErrorV1 {
            await invalidate()
            throw error
        } catch {
            await invalidate()
            throw ClientActChannelErrorV1.catalogRejected
        }
    }

    private func receiveOperation(
        _ responseJSON: Data
    ) async throws -> ClientActChannelEventV1 {
        guard let activeOperation else {
            await invalidate()
            throw ClientActChannelErrorV1.operationRejected
        }
        let kind = try messageKind(responseJSON)
        do {
            let event = try await activeOperation.acceptReply(
                responseJSON,
                approvalMessageID: kind == .operationApprovalRequired
                    ? nextMessageID() : nil,
                approvalSentAtUnixMilliseconds:
                    kind == .operationApprovalRequired ? try now() : nil
            )
            switch event {
            case let .approvalFrame(frame, prompt):
                let sendEvent = await sendOperationFrame(
                    frame,
                    operation: activeOperation
                )
                if case .operationState(.deliveryUnknown) = sendEvent {
                    return sendEvent
                }
                return .operationApprovalSubmitted(prompt)
            case .status:
                return .operationState(await activeOperation.state)
            case let .remoteError(error):
                return .remoteError(request: .operation, error: error)
            }
        } catch {
            if state == .invalidated {
                throw ClientActChannelErrorV1.invalidated
            }
            await invalidate()
            throw ClientActChannelErrorV1.operationRejected
        }
    }

    private func sendCatalogRequest(
        _ body: CapabilityRegistryRequestBody
    ) async throws {
        let messageID = try nextMessageID()
        let frame = try WireCodec.encode(WireEnvelope(
            messageID: messageID,
            correlationID: nil,
            sentAtUnixMilliseconds: try now(),
            body: body
        ))
        let expectedGeneration = generation
        pendingCatalogMessageID = messageID
        do {
            try await sender.sendAuthenticatedCommand(frame)
        } catch {
            throw ClientActChannelErrorV1.sendFailed
        }
        guard generation == expectedGeneration, state == .loadingCatalog else {
            throw ClientActChannelErrorV1.invalidated
        }
    }

    private func sendOperationFrame(
        _ frame: Data,
        operation: ClientOperationSessionV1
    ) async -> ClientActChannelEventV1 {
        let expectedGeneration = generation
        do {
            try await sender.sendAuthenticatedCommand(frame)
            guard generation == expectedGeneration, state == .operating else {
                return .operationState(.invalidated)
            }
            return .operationState(await operation.state)
        } catch {
            if generation == expectedGeneration, state == .operating {
                try? await operation.markDeliveryUnknown()
                return .operationState(await operation.state)
            }
            return .operationState(.invalidated)
        }
    }

    private func nextMessageID() throws -> WireUUID {
        let value: WireUUID
        do { value = try environment.makeMessageID() } catch {
            throw ClientActChannelErrorV1.duplicateMessageID
        }
        guard issuedMessageIDSet.insert(value).inserted else {
            throw ClientActChannelErrorV1.duplicateMessageID
        }
        issuedMessageIDs.append(value)
        if issuedMessageIDs.count > 4_096 {
            issuedMessageIDSet.remove(issuedMessageIDs.removeFirst())
        }
        return value
    }

    private func now() throws -> Int64 {
        let value = environment.wallNowUnixMilliseconds()
        guard (0...WireLimits.maximumSafeInteger).contains(value) else {
            throw ClientActChannelErrorV1.invalidClock
        }
        return value
    }

    private func messageKind(_ data: Data) throws -> WireMessageKind {
        do { return try WireCodec.messageKind(from: data) } catch {
            throw ClientActChannelErrorV1.catalogRejected
        }
    }
}
