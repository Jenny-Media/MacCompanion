import CompanionPersistence
import CompanionWire
import Foundation

public enum OperationWireDispatchError: Error, Equatable, Sendable {
    case unsupportedKind
    case missingKind
}

public actor OperationWireCommandDispatcherV0 {
    private let coordinator: OperationCommandCoordinatorV0

    public init(coordinator: OperationCommandCoordinatorV0) {
        self.coordinator = coordinator
    }

    public func dispatch(
        requestJSON: Data,
        context: AuthenticatedOperationCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let kind = try requestKind(requestJSON)
        switch kind {
        case .operationInvoke:
            return try await dispatch(
                WireEnvelope<OperationInvokeRequestBody>.self,
                requestJSON: requestJSON,
                responseMessageID: responseMessageID,
                context: context
            ) { body in
                try await self.coordinator.invoke(body, context: context)
            }
        case .operationApprove:
            return try await dispatch(
                WireEnvelope<OperationApproveRequestBody>.self,
                requestJSON: requestJSON,
                responseMessageID: responseMessageID,
                context: context
            ) { body in
                try await self.coordinator.approve(body, context: context)
            }
        case .operationStatusRequest:
            return try await dispatch(
                WireEnvelope<OperationStatusRequestBody>.self,
                requestJSON: requestJSON,
                responseMessageID: responseMessageID,
                context: context
            ) { body in
                try await self.coordinator.status(body, context: context)
            }
        case .operationCancel:
            return try await dispatch(
                WireEnvelope<OperationCancelRequestBody>.self,
                requestJSON: requestJSON,
                responseMessageID: responseMessageID,
                context: context
            ) { body in
                try await self.coordinator.cancel(body, context: context)
            }
        default:
            throw OperationWireDispatchError.unsupportedKind
        }
    }

    private func dispatch<Body: WireBody>(
        _ type: WireEnvelope<Body>.Type,
        requestJSON: Data,
        responseMessageID: WireUUID,
        context: AuthenticatedOperationCommandContextV0,
        handler: (Body) async throws -> OperationCommandReplyV0
    ) async throws -> Data {
        let request = try WireCodec.decode(type, from: requestJSON)
        do {
            let reply = try await handler(request.body)
            switch reply {
            case let .approvalRequired(body):
                return try WireCodec.encode(WireEnvelope(
                    messageID: responseMessageID,
                    correlationID: request.messageID,
                    sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
                    body: body
                ))
            case let .status(body):
                return try WireCodec.encode(WireEnvelope(
                    messageID: responseMessageID,
                    correlationID: request.messageID,
                    sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
                    body: body
                ))
            }
        } catch {
            let body = try safeErrorBody(
                error,
                requestBody: request.body
            )
            return try WireCodec.encode(WireEnvelope(
                messageID: responseMessageID,
                correlationID: request.messageID,
                sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
                body: body
            ))
        }
    }

    private func requestKind(_ data: Data) throws -> WireMessageKind {
        do {
            return try WireCodec.messageKind(from: data)
        } catch WireError.invalidFrame {
            throw OperationWireDispatchError.missingKind
        } catch WireError.unknownKind {
            throw OperationWireDispatchError.unsupportedKind
        }
    }

    private func safeErrorBody<Body: WireBody>(
        _ error: any Error,
        requestBody: Body
    ) throws -> ProtocolErrorResponseBody {
        let operationID = operationID(from: requestBody)
        let capabilityID = capabilityID(from: requestBody)
        let code: String
        let retry: ProtocolErrorRetry
        let arguments: [CanonicalJSONMember]

        switch error {
        case OperationStartupError.reconciliationRequired:
            code = "storage.securityUnavailable"
            retry = .afterUserAction
            arguments = [
                .init(key: "recovery", value: .string("localRepair")),
            ]
        case OperationCommandError.operationNotFound:
            code = "operation.notFound"
            retry = .never
            arguments = operationID.map {
                [.init(key: "operationID", value: .string($0.description))]
            } ?? []
        case OperationCommandError.providerUnavailable,
             OperationExecutionError.capabilityUnavailable,
             OperationExecutionError.providerIdentityMismatch:
            code = "provider.unavailable"
            retry = .afterReconnect
            arguments = []
        case OperationAdmissionError.approvalNotFound:
            code = "operation.approvalNotFound"
            retry = .afterApproval
            arguments = []
        case OperationAdmissionError.approvalCapacityExceeded:
            code = "rateLimit.exceeded"
            retry = .backoff
            arguments = [
                .init(key: "retryAfterMilliseconds", value: .integer(1_000)),
            ]
        case OperationAdmissionError.capabilityUnavailable,
             OperationAdmissionError.capabilityNotGranted,
             OperationAdmissionError.deviceAuthorizationChanged,
             OperationAdmissionError.hostStateDenied:
            code = "policy.denied"
            retry = .afterUserAction
            arguments = capabilityID.map {
                [.init(key: "capabilityID", value: .string($0))]
            } ?? []
        case SecurityStoreError.operationIDConflict:
            code = "protocol.operationIDConflict"
            retry = .never
            arguments = operationID.map {
                [.init(key: "operationID", value: .string($0.description))]
            } ?? []
        default:
            code = "protocol.invalidFrame"
            retry = .never
            arguments = [
                .init(key: "reasonCode", value: .string("invalidBody")),
            ]
        }
        return try ProtocolErrorResponseBody(
            code: code,
            retry: retry,
            safeArguments: .object(arguments)
        )
    }

    private func operationID<Body: WireBody>(from body: Body) -> WireUUID? {
        switch body {
        case let body as OperationInvokeRequestBody: body.operationID
        case let body as OperationStatusRequestBody: body.operationID
        case let body as OperationCancelRequestBody: body.operationID
        default: nil
        }
    }

    private func capabilityID<Body: WireBody>(from body: Body) -> String? {
        (body as? OperationInvokeRequestBody)?.capabilityID
    }
}
