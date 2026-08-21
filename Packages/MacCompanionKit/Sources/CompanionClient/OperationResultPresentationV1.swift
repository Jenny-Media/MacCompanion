import CompanionDomain
import CompanionWire

public enum KnownOperationFailureV1: String, Equatable, Sendable {
    case authorizationRevoked = "operation.authorizationRevoked"
    case hostRestarted = "operation.hostRestarted"
    case expired = "operation.expired"
    case providerUnavailable = "provider.unavailable"
    case permissionDenied = "provider.permissionDenied"
    case providerRejected = "provider.rejected"
    case providerTimedOut = "provider.timedOut"
    case executionFailed = "provider.executionFailed"
    case invalidResult = "provider.invalidResult"
    case genericFailure
}

public enum OperationResultPresentationV1: Equatable, Sendable {
    case pending(OperationState)
    case succeeded(verifiedResult: CanonicalJSONValue?)
    case denied
    case expired
    case failed(KnownOperationFailureV1)
    case cancelled
    case outcomeUnknown
}

public enum OperationResultPresentationErrorV1: Error, Equatable, Sendable {
    case capabilityMismatch
    case resultSchemaRejected
}

public enum OperationResultPresenterV1 {
    public static func present(
        _ status: OperationStatusResponseBody,
        invokedCapabilityID: String,
        descriptor: CapabilityDiscoveryDescriptorV1
    ) throws -> OperationResultPresentationV1 {
        guard descriptor.capabilityID == invokedCapabilityID else {
            throw OperationResultPresentationErrorV1.capabilityMismatch
        }
        switch status.state {
        case .pendingPolicy, .awaitingApproval, .queued, .running, .cancelRequested:
            return .pending(status.state)
        case .succeeded:
            if let result = status.result {
                let schema = try CapabilitySchemaV1(
                    wireValue: descriptor.resultSchema
                )
                do {
                    try schema.validate(result)
                } catch {
                    throw OperationResultPresentationErrorV1.resultSchemaRejected
                }
            }
            return .succeeded(verifiedResult: status.result)
        case .denied:
            return .denied
        case .expired:
            return .expired
        case .failed:
            let failure = status.terminalCode
                .flatMap(KnownOperationFailureV1.init(rawValue:))
                ?? .genericFailure
            return .failed(failure)
        case .cancelled:
            return .cancelled
        case .outcomeUnknown:
            return .outcomeUnknown
        }
    }
}
