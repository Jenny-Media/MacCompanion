import CompanionClient
import CompanionDomain
import CompanionWire
import Foundation

public struct ClientApprovedActionRowProjectionV1:
    Equatable,
    Identifiable,
    Sendable
{
    public let id: String
    public let title: String
    public let summary: String
    public let effectSummary: String

    init(_ descriptor: CapabilityDiscoveryDescriptorV1) {
        id = descriptor.capabilityID
        title = descriptor.englishTitle
        summary = descriptor.englishSummary
        effectSummary = ClientApprovedActionEffectProjectionV1(
            descriptor.effects
        ).summary
    }
}

public struct ClientApprovedActionsProjectionV1: Equatable, Sendable {
    public let rows: [ClientApprovedActionRowProjectionV1]

    public init(catalog: GrantedCapabilityCatalogV1) {
        rows = catalog.capabilities
            .map(ClientApprovedActionRowProjectionV1.init)
            .sorted {
                if $0.title == $1.title { return $0.id < $1.id }
                return $0.title.localizedStandardCompare($1.title)
                    == .orderedAscending
            }
    }
}

public struct ClientApprovedActionEffectProjectionV1: Equatable, Sendable {
    public let facts: [String]
    public let requiresExplicitReview: Bool

    public init(_ wire: CapabilityEffectFactsWireV1) {
        var values: [String] = []
        switch wire.dataAccess {
        case .none:
            values.append("Does not read data")
        case .publicData:
            values.append("Reads public data")
        case .privateData:
            values.append("Reads private data")
        case .credentials:
            values.append("Reads credential data")
        }
        switch wire.changesLocalState {
        case .none:
            values.append("Does not change Mac state")
        case .reversible:
            values.append("Makes a reversible change")
        case .irreversible:
            values.append("Makes an irreversible change")
        }
        if wire.mayDisruptUser { values.append("May disrupt the Mac user") }
        if wire.invokesExternalService { values.append("Contacts an external service") }
        if wire.usesCredentials { values.append("Uses saved credentials") }
        if wire.destructive { values.append("Can destroy or remove data") }
        if wire.requiresForegroundSession {
            values.append("Requires an active Mac user session")
        }
        values.append(
            wire.allowedWhileLocked
                ? "Allowed while the Mac is locked"
                : "Unavailable while the Mac is locked"
        )
        switch wire.cancellation {
        case .notApplicable:
            values.append("Cannot be cancelled after admission")
        case .bestEffort:
            values.append("Cancellation is best effort")
        }
        facts = values
        requiresExplicitReview = wire.destructive
            || wire.changesLocalState == .irreversible
            || wire.usesCredentials
            || wire.invokesExternalService
            || wire.mayDisruptUser
    }

    public var summary: String {
        facts.joined(separator: " • ")
    }
}

public struct ClientApprovedActionStateProjectionV1: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String
    public let isBusy: Bool
    public let canInvoke: Bool
    public let canCancel: Bool
    public let canQuery: Bool
    public let verifiedResult: CanonicalJSONValue?

    public init(_ state: ClientOperationSessionStateV1) {
        switch state {
        case .idle:
            self.init(
                title: "Ready",
                detail: "Review the parameters and effects before running this action.",
                systemImage: "checkmark.circle",
                isBusy: false,
                canInvoke: true
            )
        case .awaitingInvokeReply:
            self.init(
                title: "Checking with Mac",
                detail: "The Mac is applying its current grant and safety policy.",
                systemImage: "arrow.triangle.2.circlepath",
                isBusy: true
            )
        case .awaitingUserPresence:
            self.init(
                title: "Confirm on iPhone",
                detail: "Use Face ID, Touch ID, or the device passcode to approve this exact action.",
                systemImage: "person.badge.key",
                isBusy: true
            )
        case .awaitingApprovalReply:
            self.init(
                title: "Submitting Approval",
                detail: "The one-time approval is being verified by the Mac.",
                systemImage: "lock.shield",
                isBusy: true
            )
        case let .observing(operation):
            let status: (String, String) = switch operation {
            case .pendingPolicy: ("Checking Policy", "The Mac is evaluating current authorization.")
            case .awaitingApproval: ("Approval Required", "Fresh approval is required before admission.")
            case .queued: ("Queued", "The action is admitted and waiting to run.")
            case .running: ("Running", "The Mac is executing the bounded action.")
            case .cancelRequested: ("Cancellation Requested", "The provider is attempting best-effort cancellation.")
            case .denied, .expired, .succeeded, .failed, .cancelled,
                 .outcomeUnknown:
                ("Updating", "The Mac returned an unexpected nonterminal projection.")
            }
            self.init(
                title: status.0,
                detail: status.1,
                systemImage: "clock.arrow.circlepath",
                isBusy: operation != .cancelRequested,
                canCancel: operation == .queued || operation == .running,
                canQuery: true
            )
        case .awaitingStatusReply:
            self.init(
                title: "Refreshing Status",
                detail: "Checking the durable operation on the Mac.",
                systemImage: "arrow.clockwise",
                isBusy: true
            )
        case .awaitingCancelReply:
            self.init(
                title: "Requesting Cancellation",
                detail: "Waiting for the Mac's authoritative operation status.",
                systemImage: "stop.circle",
                isBusy: true
            )
        case .deliveryUnknown:
            self.init(
                title: "Delivery Unknown",
                detail: "Do not run a replacement. Reconnect and query this same operation.",
                systemImage: "questionmark.diamond",
                isBusy: false,
                canQuery: true
            )
        case let .terminal(result):
            switch result {
            case let .succeeded(verifiedResult):
                self.init(
                    title: "Completed",
                    detail: "The result was validated. Observe remains the authoritative current state.",
                    systemImage: "checkmark.circle.fill",
                    isBusy: false,
                    verifiedResult: verifiedResult
                )
            case .denied:
                self.init(
                    title: "Denied",
                    detail: "The Mac's current grant or policy did not allow this action.",
                    systemImage: "hand.raised.fill",
                    isBusy: false
                )
            case .expired:
                self.init(
                    title: "Expired",
                    detail: "The operation or its approval expired before admission.",
                    systemImage: "clock.badge.exclamationmark",
                    isBusy: false
                )
            case let .failed(failure):
                self.init(
                    title: "Failed",
                    detail: Self.failureDetail(failure),
                    systemImage: "xmark.circle.fill",
                    isBusy: false
                )
            case .cancelled:
                self.init(
                    title: "Cancelled",
                    detail: "The Mac confirmed that the action was cancelled.",
                    systemImage: "stop.circle.fill",
                    isBusy: false
                )
            case .outcomeUnknown:
                self.init(
                    title: "Outcome Unknown",
                    detail: "The Mac cannot prove whether the effect occurred. Verify through Observe before retrying.",
                    systemImage: "questionmark.diamond.fill",
                    isBusy: false
                )
            case .pending:
                self.init(
                    title: "Updating",
                    detail: "Waiting for a durable operation state.",
                    systemImage: "clock",
                    isBusy: true
                )
            }
        case let .remoteRejected(error):
            self.init(
                title: "Request Rejected",
                detail: Self.remoteDetail(error),
                systemImage: "exclamationmark.triangle.fill",
                isBusy: false
            )
        case .invalidated:
            self.init(
                title: "Connection Changed",
                detail: "This action owner was invalidated. Reconnect and reload approved actions.",
                systemImage: "bolt.slash",
                isBusy: false
            )
        }
    }

    private init(
        title: String,
        detail: String,
        systemImage: String,
        isBusy: Bool,
        canInvoke: Bool = false,
        canCancel: Bool = false,
        canQuery: Bool = false,
        verifiedResult: CanonicalJSONValue? = nil
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.isBusy = isBusy
        self.canInvoke = canInvoke
        self.canCancel = canCancel
        self.canQuery = canQuery
        self.verifiedResult = verifiedResult
    }

    private static func failureDetail(_ failure: KnownOperationFailureV1) -> String {
        switch failure {
        case .authorizationRevoked: "Authorization changed before execution."
        case .hostRestarted: "The Mac restarted before it could prove the outcome."
        case .expired: "The operation expired before execution."
        case .providerUnavailable: "The approved capability is currently unavailable."
        case .permissionDenied: "macOS denied a permission required by this capability."
        case .providerRejected: "The capability rejected the requested state."
        case .providerTimedOut: "The capability did not finish before its deadline."
        case .executionFailed: "The capability could not complete the action."
        case .invalidResult: "The Mac rejected an invalid capability result."
        case .genericFailure: "The Mac reported a bounded failure."
        }
    }

    private static func remoteDetail(_ error: ClientOperationRemoteErrorV1) -> String {
        switch error.retry {
        case .never: "The Mac rejected this request. Code: \(error.code)"
        case .afterUserAction: "Review the Mac and try again. Code: \(error.code)"
        case .afterReconnect: "Reconnect and reload approved actions. Code: \(error.code)"
        case .afterApproval: "Fresh local approval is required. Code: \(error.code)"
        case .backoff: "Wait before trying again. Code: \(error.code)"
        }
    }
}

public struct ClientVerifiedResultRowV1: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let value: String

    public init(id: String, label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public enum ClientVerifiedResultProjectionV1 {
    public static func rows(
        _ value: CanonicalJSONValue
    ) -> [ClientVerifiedResultRowV1] {
        var result: [ClientVerifiedResultRowV1] = []
        append(value, path: "$", label: "Result", to: &result)
        return result
    }

    private static func append(
        _ value: CanonicalJSONValue,
        path: String,
        label: String,
        to result: inout [ClientVerifiedResultRowV1]
    ) {
        switch value {
        case .null:
            result.append(.init(id: path, label: label, value: "None"))
        case let .boolean(value):
            result.append(.init(id: path, label: label, value: value ? "Yes" : "No"))
        case let .integer(value):
            result.append(.init(id: path, label: label, value: String(value)))
        case let .string(value):
            result.append(.init(id: path, label: label, value: value))
        case let .array(values):
            if values.isEmpty {
                result.append(.init(id: path, label: label, value: "Empty"))
            } else {
                for (index, child) in values.enumerated() {
                    append(
                        child,
                        path: "\(path)[\(index)]",
                        label: "\(label) \(index + 1)",
                        to: &result
                    )
                }
            }
        case let .object(members):
            for member in members.sorted(by: { $0.key < $1.key }) {
                append(
                    member.value,
                    path: "\(path).\(member.key)",
                    label: displayName(member.key),
                    to: &result
                )
            }
        }
    }

    public static func displayName(_ identifier: String) -> String {
        let spaced = identifier.reduce(into: "") { result, character in
            if character.isUppercase, !result.isEmpty { result.append(" ") }
            result.append(character)
        }
        return spaced
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
