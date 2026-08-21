import CompanionDomain
import CompanionSecurity
import CompanionWire
import Foundation

public protocol ClientOperationApprovalSigningV1: Sendable {
    func signOperationApprovalInput(_ input: Data) async throws -> Data
}

/// Approval-only adapter. Session-key access is intentionally absent.
public struct ClientCustodiedOperationApprovalSignerV1:
    ClientOperationApprovalSigningV1,
    Sendable
{
    private let custody: any ClientIdentityKeyCustodyV0
    private let reference: ClientSigningKeyReferenceV0

    public init(
        custody: any ClientIdentityKeyCustodyV0,
        approvalKey: ClientCustodiedPublicKeyV0
    ) throws {
        guard approvalKey.role == .approval,
              approvalKey.protection == .whenUnlockedThisDeviceOnlyUserPresence else {
            throw ClientIdentityPublicationErrorV0.invalidIdentity
        }
        self.custody = custody
        reference = approvalKey.reference
    }

    public func signOperationApprovalInput(_ input: Data) async throws -> Data {
        let signature = try await custody.signApprovalInput(
            input,
            using: reference,
            reason: .approveOperation
        )
        guard signature.count == 64 else {
            throw ClientIdentityPublicationErrorV0.invalidIdentity
        }
        return signature
    }
}

public enum ClientOperationSessionStateV1: Equatable, Sendable {
    case idle
    case awaitingInvokeReply
    case awaitingUserPresence
    case awaitingApprovalReply
    case observing(OperationState)
    case awaitingStatusReply
    case awaitingCancelReply
    case deliveryUnknown
    case terminal(OperationResultPresentationV1)
    case remoteRejected(ClientOperationRemoteErrorV1)
    case invalidated
}

public struct ClientOperationRemoteErrorV1: Equatable, Sendable {
    public let code: String
    public let retry: ProtocolErrorRetry
    public let safeArguments: CanonicalJSONValue

    public init(_ body: ProtocolErrorResponseBody) {
        code = body.code
        retry = body.retry
        safeArguments = body.safeArguments
    }
}

public struct ClientOperationApprovalPromptV1: Equatable, Sendable {
    public let operationID: WireUUID
    public let approvalID: WireUUID
    public let capabilityTitle: String
    public let capabilitySummary: String
    public let effects: CapabilityEffectFactsWireV1
    public let expiresAtUnixMilliseconds: Int64
}

public enum ClientOperationSessionEventV1: Equatable, Sendable {
    case approvalFrame(Data, prompt: ClientOperationApprovalPromptV1)
    case status(OperationResultPresentationV1)
    case remoteError(ClientOperationRemoteErrorV1)
}

public enum ClientOperationSessionErrorV1: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidState
    case invalidClock
    case invalidCorrelation
    case operationMismatch
    case unexpectedMessage(WireMessageKind)
    case parameterSchemaRejected
    case approvalExpired
    case approvalSigningFailed
    case invalidSignature
    case lateApproval
    case resultSchemaRejected
}

/// One-operation, one-primary-connection Act owner. Transport sends the frames
/// it returns and routes correlated replies back into this actor.
public actor ClientOperationSessionV1 {
    public let operationID: WireUUID
    public let descriptor: CapabilityDiscoveryDescriptorV1
    public private(set) var state: ClientOperationSessionStateV1 = .idle

    private let clientID: UUID
    private let hostFingerprint: Data
    private let primaryConnectionID: Data
    private let signer: any ClientOperationApprovalSigningV1
    private let wallNowUnixMilliseconds: @Sendable () -> Int64
    private let version = WireVersion()
    private var generation: UInt64 = 0
    private var pendingMessageID: WireUUID?
    private var pendingRequestKind: WireMessageKind?

    public init(
        operationID: WireUUID,
        capabilityID: String,
        pairedHost: ClientDurablePairedHostV0,
        authenticatedSession: ClientAuthenticatedSessionV0,
        catalog: GrantedCapabilityCatalogV1,
        signer: any ClientOperationApprovalSigningV1,
        wallNowUnixMilliseconds: @escaping @Sendable () -> Int64
    ) throws {
        guard pairedHost.clientID == authenticatedSession.clientID,
              pairedHost.hostID == authenticatedSession.hostID,
              pairedHost.deviceID == authenticatedSession.deviceID,
              pairedHost.hostFingerprint.count == 32,
              authenticatedSession.connectionID.count == 16,
              authenticatedSession.deviceState == .activeMonitorOnly
                || authenticatedSession.deviceState == .activeGranted,
              catalog.grantRevision
                == Int64(authenticatedSession.grantRevision.rawValue),
              catalog.policyRevision
                == Int64(authenticatedSession.policyRevision.rawValue),
              let descriptor = catalog.capability(capabilityID) else {
            throw ClientOperationSessionErrorV1.invalidConfiguration
        }
        self.operationID = operationID
        self.descriptor = descriptor
        clientID = pairedHost.clientID
        hostFingerprint = pairedHost.hostFingerprint
        primaryConnectionID = authenticatedSession.connectionID
        self.signer = signer
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
    }

    public func begin(
        parameters: CanonicalJSONValue,
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> Data {
        guard state == .idle else {
            throw ClientOperationSessionErrorV1.invalidState
        }
        guard sentAtUnixMilliseconds >= 0 else {
            throw ClientOperationSessionErrorV1.invalidClock
        }
        do {
            let schema = try CapabilitySchemaV1(
                wireValue: descriptor.parameterSchema
            )
            try schema.validate(parameters)
            let body = try OperationInvokeRequestBody(
                operationID: operationID,
                capabilityID: descriptor.capabilityID,
                parameters: parameters
            )
            let envelope = try WireEnvelope(
                messageID: messageID,
                correlationID: nil,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: body
            )
            registerPending(messageID, kind: .operationInvoke)
            state = .awaitingInvokeReply
            return try WireCodec.encode(envelope)
        } catch let error as ClientOperationSessionErrorV1 {
            throw error
        } catch {
            throw ClientOperationSessionErrorV1.parameterSchemaRejected
        }
    }

    public func acceptReply(
        _ responseJSON: Data,
        approvalMessageID: WireUUID? = nil,
        approvalSentAtUnixMilliseconds: Int64? = nil
    ) async throws -> ClientOperationSessionEventV1 {
        guard let pendingMessageID, let pendingRequestKind else {
            throw ClientOperationSessionErrorV1.invalidState
        }
        do {
            let kind = try WireCodec.messageKind(from: responseJSON)
            if kind == .error {
                let response = try WireCodec.decode(
                    WireEnvelope<ProtocolErrorResponseBody>.self,
                    from: responseJSON
                )
                guard response.correlationID == pendingMessageID else {
                    throw ClientOperationSessionErrorV1.invalidCorrelation
                }
                clearPending()
                let remote = ClientOperationRemoteErrorV1(response.body)
                state = response.body.code == "operation.outcomeUnknown"
                    ? .deliveryUnknown
                    : .remoteRejected(remote)
                clearApprovalAuthority()
                return .remoteError(remote)
            }

            switch kind {
            case .operationApprovalRequired:
                guard pendingRequestKind == .operationInvoke else {
                    throw ClientOperationSessionErrorV1.unexpectedMessage(kind)
                }
                let response = try WireCodec.decode(
                    WireEnvelope<OperationApprovalRequiredBody>.self,
                    from: responseJSON
                )
                guard response.correlationID == pendingMessageID else {
                    throw ClientOperationSessionErrorV1.invalidCorrelation
                }
                guard response.body.operationID == operationID else {
                    throw ClientOperationSessionErrorV1.operationMismatch
                }
                guard let approvalMessageID,
                      let approvalSentAtUnixMilliseconds,
                      approvalSentAtUnixMilliseconds >= 0 else {
                    throw ClientOperationSessionErrorV1.invalidClock
                }
                clearPending()
                return try await approve(
                    response.body,
                    messageID: approvalMessageID,
                    sentAtUnixMilliseconds: approvalSentAtUnixMilliseconds
                )

            case .operationStatusResponse:
                guard pendingRequestKind == .operationInvoke
                        || pendingRequestKind == .operationApprove
                        || pendingRequestKind == .operationStatusRequest
                        || pendingRequestKind == .operationCancel else {
                    throw ClientOperationSessionErrorV1.unexpectedMessage(kind)
                }
                let response = try WireCodec.decode(
                    WireEnvelope<OperationStatusResponseBody>.self,
                    from: responseJSON
                )
                guard response.correlationID == pendingMessageID else {
                    throw ClientOperationSessionErrorV1.invalidCorrelation
                }
                guard response.body.operationID == operationID else {
                    throw ClientOperationSessionErrorV1.operationMismatch
                }
                clearPending()
                let presentation: OperationResultPresentationV1
                do {
                    presentation = try OperationResultPresenterV1.present(
                        response.body,
                        invokedCapabilityID: descriptor.capabilityID,
                        descriptor: descriptor
                    )
                } catch {
                    throw ClientOperationSessionErrorV1.resultSchemaRejected
                }
                switch presentation {
                case let .pending(operationState):
                    state = .observing(operationState)
                case .succeeded, .denied, .expired, .failed, .cancelled,
                     .outcomeUnknown:
                    state = .terminal(presentation)
                    clearApprovalAuthority()
                }
                return .status(presentation)

            default:
                throw ClientOperationSessionErrorV1.unexpectedMessage(kind)
            }
        } catch let error as ClientOperationSessionErrorV1 {
            invalidate()
            throw error
        } catch {
            invalidate()
            throw ClientOperationSessionErrorV1.invalidCorrelation
        }
    }

    public func requestStatus(
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> Data {
        switch state {
        case .observing, .deliveryUnknown:
            break
        default:
            throw ClientOperationSessionErrorV1.invalidState
        }
        let frame = try commandFrame(
            messageID: messageID,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: OperationStatusRequestBody(operationID: operationID)
        )
        registerPending(messageID, kind: .operationStatusRequest)
        state = .awaitingStatusReply
        return frame
    }

    /// Rehydrates only the ability to query a caller-retained durable
    /// operation ID after connection replacement. It cannot invoke or approve
    /// an effect and retains the newly authenticated connection fence.
    public func resumeExistingOperationForStatus() throws {
        guard state == .idle else {
            throw ClientOperationSessionErrorV1.invalidState
        }
        state = .deliveryUnknown
    }

    public func requestCancel(
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> Data {
        guard case .observing = state else {
            throw ClientOperationSessionErrorV1.invalidState
        }
        let frame = try commandFrame(
            messageID: messageID,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: OperationCancelRequestBody(operationID: operationID)
        )
        registerPending(messageID, kind: .operationCancel)
        state = .awaitingCancelReply
        return frame
    }

    /// Call only after a transport failure or timeout makes delivery
    /// ambiguous. The same durable operation ID remains available to query.
    public func markDeliveryUnknown() throws {
        switch state {
        case .awaitingInvokeReply, .awaitingApprovalReply,
             .awaitingCancelReply, .awaitingStatusReply:
            generation &+= 1
            clearPending()
            clearApprovalAuthority()
            state = .deliveryUnknown
        default:
            throw ClientOperationSessionErrorV1.invalidState
        }
    }

    public func invalidate() {
        generation &+= 1
        clearPending()
        clearApprovalAuthority()
        state = .invalidated
    }

    private func approve(
        _ challenge: OperationApprovalRequiredBody,
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) async throws -> ClientOperationSessionEventV1 {
        let nowBefore = wallNowUnixMilliseconds()
        guard nowBefore >= 0 else {
            throw ClientOperationSessionErrorV1.invalidClock
        }
        guard nowBefore < challenge.expiresAtUnixMilliseconds else {
            throw ClientOperationSessionErrorV1.approvalExpired
        }
        let signingInput = try CompanionSecurityV0.operationApprovalSigningInput(
            hostFingerprint: hostFingerprint,
            clientID: clientID,
            primaryConnectionID: primaryConnectionID,
            approvalID: challenge.approvalID.rawValue,
            operationDigest: challenge.operationDigest.rawValue,
            serverChallenge: challenge.serverChallenge.rawValue,
            issuedAtUnixMilliseconds: UInt64(challenge.issuedAtUnixMilliseconds),
            expiresAtUnixMilliseconds: UInt64(challenge.expiresAtUnixMilliseconds),
            selectedMajor: version.major,
            selectedMinor: version.minor
        )
        let approvalGeneration = generation
        state = .awaitingUserPresence
        let signature: Data
        do {
            signature = try await signer.signOperationApprovalInput(signingInput)
        } catch {
            if Task.isCancelled {
                invalidate()
                throw ClientOperationSessionErrorV1.lateApproval
            }
            invalidate()
            throw ClientOperationSessionErrorV1.approvalSigningFailed
        }
        guard generation == approvalGeneration,
              state == .awaitingUserPresence else {
            throw ClientOperationSessionErrorV1.lateApproval
        }
        let nowAfter = wallNowUnixMilliseconds()
        guard nowAfter >= 0 else {
            throw ClientOperationSessionErrorV1.invalidClock
        }
        guard nowAfter < challenge.expiresAtUnixMilliseconds else {
            invalidate()
            throw ClientOperationSessionErrorV1.approvalExpired
        }
        guard signature.count == 64 else {
            invalidate()
            throw ClientOperationSessionErrorV1.invalidSignature
        }
        let body = OperationApproveRequestBody(
            approvalID: challenge.approvalID,
            signature: try WireBytes64(signature)
        )
        let frame = try commandFrame(
            messageID: messageID,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: body
        )
        registerPending(messageID, kind: .operationApprove)
        state = .awaitingApprovalReply
        let prompt = ClientOperationApprovalPromptV1(
            operationID: operationID,
            approvalID: challenge.approvalID,
            capabilityTitle: descriptor.englishTitle,
            capabilitySummary: descriptor.englishSummary,
            effects: descriptor.effects,
            expiresAtUnixMilliseconds: challenge.expiresAtUnixMilliseconds
        )
        return .approvalFrame(frame, prompt: prompt)
    }

    private func commandFrame<Body: WireBody>(
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64,
        body: Body
    ) throws -> Data {
        guard sentAtUnixMilliseconds >= 0 else {
            throw ClientOperationSessionErrorV1.invalidClock
        }
        return try WireCodec.encode(WireEnvelope(
            messageID: messageID,
            correlationID: nil,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: body
        ))
    }

    private func registerPending(
        _ messageID: WireUUID,
        kind: WireMessageKind
    ) {
        pendingMessageID = messageID
        pendingRequestKind = kind
    }

    private func clearPending() {
        pendingMessageID = nil
        pendingRequestKind = nil
    }

    private func clearApprovalAuthority() {
        // Approval challenges and signing input are method-local by design.
    }
}
