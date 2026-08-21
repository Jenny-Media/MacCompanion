import CompanionIPC
import CompanionLifecycle
import Foundation

public enum MacAgentDashboardActionV0: String, CaseIterable, Equatable, Sendable {
    case enable
    case disable
    case retryStatus
    case startPairing
    case openDevices
    case openActivityHistory
    case exportDiagnostics
}

public enum MacAgentDashboardDestinationV0: String, Equatable, Sendable {
    case devices
    case activityHistory
}

public enum MacAgentDashboardEffectOutcomeV0: String, Equatable, Sendable {
    case completed
    case notCompleted
    case outcomeUnknown
}

public enum MacAgentDashboardActionFailureV0: String, Equatable, Sendable {
    case effectNotCompleted
    case diagnosticsUnavailable
}

public enum MacAgentDashboardActionCompletionV0: Equatable, Sendable {
    case enabled
    case disabled
    case statusRefreshed
    case pairingPresented
    case navigated(MacAgentDashboardDestinationV0)
    case diagnosticExport(LocalDiagnosticExport)
}

public enum MacAgentDashboardActionResultV0: Equatable, Sendable {
    case completed(
        action: MacAgentDashboardActionV0,
        completion: MacAgentDashboardActionCompletionV0
    )
    case failed(
        action: MacAgentDashboardActionV0,
        reason: MacAgentDashboardActionFailureV0
    )
    case outcomeUnknown(action: MacAgentDashboardActionV0)
}

public enum MacAgentDashboardActionStateV0: Equatable, Sendable {
    case idle
    case performing(MacAgentDashboardActionV0)
    case finished(MacAgentDashboardActionResultV0)
    case invalidated
}

public enum MacAgentDashboardActionCoordinatorErrorV0:
    Error,
    Equatable,
    Sendable
{
    case actionInProgress
    case actionDenied(MacAgentDashboardActionV0)
    case invalidSource
    case revisionExhausted
    case applicationInvalidated
}

public protocol MacAgentDashboardSourceReadingV0: Sendable {
    func snapshot() async -> MacAgentDashboardSourceV0
}

/// A signed-target adapter may report `completed` only after the complete
/// lifecycle transition and all required platform postconditions converge.
/// An effect-then-error without a proven postcondition is `outcomeUnknown`.
public protocol MacAgentDashboardLifecycleCommandingV0: Sendable {
    func setEnabled(_ enabled: Bool) async
        -> MacAgentDashboardEffectOutcomeV0
}

/// `completed` means a fresh response was accepted by the current dashboard
/// connection generation, not merely that a transport request was enqueued.
public protocol MacAgentDashboardStatusRetryingV0: Sendable {
    func retryStatus() async -> MacAgentDashboardEffectOutcomeV0
}

/// `completed` means the existing pairing owner reached a visible, validated
/// Agent-issued pairing presentation.
public protocol MacAgentDashboardPairingStartingV0: Sendable {
    func startPairingFromDashboard() async
        -> MacAgentDashboardEffectOutcomeV0
}

/// An authenticated adapter wraps the Agent's root-issued sanitized export
/// capability. It must not substitute detailed audit history or raw logs.
public protocol MacAgentDashboardDiagnosticExportingV0: Sendable {
    func exportDiagnostics() async throws -> LocalDiagnosticExport
}

public enum MacAgentDashboardActionPolicyV0 {
    public static func isEnabled(
        _ action: MacAgentDashboardActionV0,
        in source: MacAgentDashboardSourceV0
    ) -> Bool {
        (try? authorize(action, in: source)) != nil
    }

    public static func authorize(
        _ action: MacAgentDashboardActionV0,
        in source: MacAgentDashboardSourceV0
    ) throws {
        switch source {
        case .loading:
            throw MacAgentDashboardActionCoordinatorErrorV0
                .actionDenied(action)
        case .unavailable:
            guard action == .retryStatus else {
                throw MacAgentDashboardActionCoordinatorErrorV0
                    .actionDenied(action)
            }
        case let .status(status):
            do {
                try status.validate()
            } catch {
                throw MacAgentDashboardActionCoordinatorErrorV0.invalidSource
            }
            guard statusAllows(action, status: status) else {
                throw MacAgentDashboardActionCoordinatorErrorV0
                    .actionDenied(action)
            }
        }
    }

    private static func statusAllows(
        _ action: MacAgentDashboardActionV0,
        status: LocalAgentStatusSnapshot
    ) -> Bool {
        let administrationReady = status.desiredEnabled
            && status.consoleSession == .active
            && status.agentProcess == .ready
            && status.menuAppProcess == .ready
            && status.securityPosture == .nominal
        return switch action {
        case .enable:
            !status.desiredEnabled && status.consoleSession != .loggedOut
        case .disable:
            status.desiredEnabled
        case .retryStatus:
            false
        case .startPairing:
            administrationReady
                && status.networkState == .listening
                && status.pairedDeviceCount == 0
        case .openDevices:
            administrationReady && status.pairedDeviceCount > 0
        case .openActivityHistory:
            administrationReady
        case .exportDiagnostics:
            status.agentProcess == .ready
        }
    }
}

extension MacAgentDashboardApplicationOwnerV0:
    MacAgentDashboardSourceReadingV0
{}

extension MacPairingApplicationOwnerV0:
    MacAgentDashboardPairingStartingV0
{
    public func startPairingFromDashboard() async
        -> MacAgentDashboardEffectOutcomeV0
    {
        do {
            try await begin()
        } catch {
            return .notCompleted
        }
        switch snapshot().phase {
        case .presenting:
            return .completed
        case .creating:
            return .outcomeUnknown
        case .idle, .creationFailed, .dismissing, .dismissalFailed:
            return .notCompleted
        }
    }
}

/// Single application owner for every dashboard action. It rechecks the same
/// closed admission policy used by SwiftUI, serializes effects, and fences a
/// completion from any retired local-authority generation. It never performs
/// peer authentication, lifecycle effects, IPC, file writing, or navigation
/// itself; those capabilities are injected after their own trust gates and
/// must revalidate their current authoritative state after this UI admission.
public actor MacAgentDashboardActionCoordinatorV0 {
    public typealias StateChanged =
        @Sendable (MacAgentDashboardActionStateV0) async -> Void

    private let source: any MacAgentDashboardSourceReadingV0
    private let lifecycle: any MacAgentDashboardLifecycleCommandingV0
    private let statusRetry: any MacAgentDashboardStatusRetryingV0
    private let pairing: any MacAgentDashboardPairingStartingV0
    private let diagnostics: any MacAgentDashboardDiagnosticExportingV0
    private let stateChanged: StateChanged

    private var state: MacAgentDashboardActionStateV0 = .idle
    private var revision: UInt64 = 0
    private var inFlightRevision: UInt64?
    private var applicationIsInvalidated = false

    public init(
        source: any MacAgentDashboardSourceReadingV0,
        lifecycle: any MacAgentDashboardLifecycleCommandingV0,
        statusRetry: any MacAgentDashboardStatusRetryingV0,
        pairing: any MacAgentDashboardPairingStartingV0,
        diagnostics: any MacAgentDashboardDiagnosticExportingV0,
        stateChanged: @escaping StateChanged = { _ in }
    ) {
        self.source = source
        self.lifecycle = lifecycle
        self.statusRetry = statusRetry
        self.pairing = pairing
        self.diagnostics = diagnostics
        self.stateChanged = stateChanged
    }

    public func snapshot() -> MacAgentDashboardActionStateV0 { state }

    @discardableResult
    public func perform(
        _ action: MacAgentDashboardActionV0
    ) async throws -> MacAgentDashboardActionResultV0 {
        guard !applicationIsInvalidated else {
            throw MacAgentDashboardActionCoordinatorErrorV0
                .applicationInvalidated
        }
        guard inFlightRevision == nil else {
            throw MacAgentDashboardActionCoordinatorErrorV0.actionInProgress
        }
        try MacAgentDashboardActionPolicyV0.authorize(
            action,
            in: await source.snapshot()
        )
        guard revision < UInt64.max else {
            throw MacAgentDashboardActionCoordinatorErrorV0.revisionExhausted
        }
        revision += 1
        let operationRevision = revision
        inFlightRevision = operationRevision
        state = .performing(action)
        await publish()

        let result = await execute(action)
        guard !applicationIsInvalidated,
              inFlightRevision == operationRevision,
              revision == operationRevision else {
            return .outcomeUnknown(action: action)
        }
        inFlightRevision = nil
        state = .finished(result)
        await publish()
        return result
    }

    /// Connection replacement or authority loss fences the current completion
    /// but permits a later authenticated generation to use the coordinator.
    public func authorityInvalidated() async {
        inFlightRevision = nil
        state = .idle
        await publish()
    }

    public func applicationInvalidated() async {
        applicationIsInvalidated = true
        inFlightRevision = nil
        state = .invalidated
        await publish()
    }

    public func clearFinishedResult() async {
        guard case .finished = state,
              inFlightRevision == nil,
              !applicationIsInvalidated else { return }
        state = .idle
        await publish()
    }

    private func execute(
        _ action: MacAgentDashboardActionV0
    ) async -> MacAgentDashboardActionResultV0 {
        switch action {
        case .enable:
            return effectResult(
                await lifecycle.setEnabled(true),
                action: action,
                completion: .enabled
            )
        case .disable:
            return effectResult(
                await lifecycle.setEnabled(false),
                action: action,
                completion: .disabled
            )
        case .retryStatus:
            return effectResult(
                await statusRetry.retryStatus(),
                action: action,
                completion: .statusRefreshed
            )
        case .startPairing:
            return effectResult(
                await pairing.startPairingFromDashboard(),
                action: action,
                completion: .pairingPresented
            )
        case .openDevices:
            return .completed(
                action: action,
                completion: .navigated(.devices)
            )
        case .openActivityHistory:
            return .completed(
                action: action,
                completion: .navigated(.activityHistory)
            )
        case .exportDiagnostics:
            do {
                let value = try await diagnostics.exportDiagnostics()
                try value.validate()
                return .completed(
                    action: action,
                    completion: .diagnosticExport(value)
                )
            } catch {
                return .failed(
                    action: action,
                    reason: .diagnosticsUnavailable
                )
            }
        }
    }

    private func effectResult(
        _ outcome: MacAgentDashboardEffectOutcomeV0,
        action: MacAgentDashboardActionV0,
        completion: MacAgentDashboardActionCompletionV0
    ) -> MacAgentDashboardActionResultV0 {
        switch outcome {
        case .completed:
            .completed(action: action, completion: completion)
        case .notCompleted:
            .failed(action: action, reason: .effectNotCompleted)
        case .outcomeUnknown:
            .outcomeUnknown(action: action)
        }
    }

    private func publish() async { await stateChanged(state) }
}
