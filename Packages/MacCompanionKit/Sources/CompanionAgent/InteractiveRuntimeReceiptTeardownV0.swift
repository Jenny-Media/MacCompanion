import CompanionInteractiveShared
import CompanionIPC
import Foundation

/// Result of the Agent's authenticated Agent-to-menu runtime route. An active
/// session carries the exact revoke command and complete menu safety receipt;
/// a pending approval carries an explicit proof that no runtime was installed.
public struct LocalInteractiveRuntimeRevocationRouteV0: Equatable, Sendable {
    public let deviceID: UUID
    public let requestID: UUID
    public let approvalID: UUID
    public let noRuntimeInstalled: Bool
    public let revokeCommand: InteractiveRuntimeRevokeCommandV0?
    public let revokedReceipt: InteractiveRuntimeRevokedReceiptV0?
    public let completedAtUnixMilliseconds: Int64

    public init(
        deviceID: UUID,
        requestID: UUID,
        approvalID: UUID,
        noRuntimeInstalled: Bool,
        revokeCommand: InteractiveRuntimeRevokeCommandV0?,
        revokedReceipt: InteractiveRuntimeRevokedReceiptV0?,
        completedAtUnixMilliseconds: Int64
    ) {
        self.deviceID = deviceID
        self.requestID = requestID
        self.approvalID = approvalID
        self.noRuntimeInstalled = noRuntimeInstalled
        self.revokeCommand = revokeCommand
        self.revokedReceipt = revokedReceipt
        self.completedAtUnixMilliseconds = completedAtUnixMilliseconds
    }
}

public protocol LocalInteractiveRuntimeRevocationRoutingV0: Sendable {
    /// Looks up the exact Agent-owned request/session-to-lease binding and
    /// invokes authenticated menu IPC. Implementations are idempotent for the
    /// same local command identifier.
    func revokeRuntime(
        for command: LocalInteractiveStopCommandV0
    ) async throws -> LocalInteractiveRuntimeRevocationRouteV0
}

/// Converts the existing four-effect menu runtime receipt into the stricter
/// local-authority teardown proof consumed by `LocalInteractiveStopHandlerV0`.
public struct InteractiveRuntimeReceiptTeardownV0:
    LocalInteractiveRuntimeTearingDownV0,
    Sendable
{
    private let router: any LocalInteractiveRuntimeRevocationRoutingV0

    public init(router: any LocalInteractiveRuntimeRevocationRoutingV0) {
        self.router = router
    }

    public func teardownRuntime(
        for command: LocalInteractiveStopCommandV0,
        after remoteEnd: LocalInteractiveRemoteEndProofV0
    ) async throws -> LocalInteractiveRuntimeTeardownProofV0 {
        guard remoteEnd.remoteAuthorityEnded,
              remoteEnd.deviceID == command.deviceID,
              remoteEnd.requestID == command.requestID,
              remoteEnd.approvalID == command.approvalID,
              remoteEnd.interactiveSessionID
                == command.interactiveSessionID else {
            throw LocalInteractiveStopHandlerErrorV0.commandMismatch
        }
        let route = try await router.revokeRuntime(for: command)
        guard route.deviceID == command.deviceID,
              route.requestID == command.requestID,
              route.approvalID == command.approvalID,
              route.completedAtUnixMilliseconds
                >= command.occurredAtUnixMilliseconds else {
            throw LocalInteractiveStopHandlerErrorV0.commandMismatch
        }

        if let sessionID = command.interactiveSessionID {
            guard !route.noRuntimeInstalled,
                  let revoke = route.revokeCommand,
                  let receipt = route.revokedReceipt,
                  revoke.interactiveSessionID == sessionID,
                  revoke.reason == Self.runtimeReason(for: command.reason) else {
                throw LocalInteractiveStopHandlerErrorV0
                    .runtimeTeardownIncomplete
            }
            do {
                try receipt.validate(against: revoke)
            } catch {
                throw LocalInteractiveStopHandlerErrorV0
                    .runtimeTeardownIncomplete
            }
        } else {
            guard route.noRuntimeInstalled,
                  route.revokeCommand == nil,
                  route.revokedReceipt == nil else {
                throw LocalInteractiveStopHandlerErrorV0
                    .runtimeTeardownIncomplete
            }
        }

        return LocalInteractiveRuntimeTeardownProofV0(
            deviceID: command.deviceID,
            requestID: command.requestID,
            approvalID: command.approvalID,
            interactiveSessionID: command.interactiveSessionID,
            runtimeTeardownComplete: true,
            completedAtUnixMilliseconds: route.completedAtUnixMilliseconds
        )
    }

    private static func runtimeReason(
        for reason: LocalInteractiveStopReasonV0
    ) -> InteractiveSessionEndReason {
        switch reason {
        case .userRequested, .controlDisabled:
            .localSuspension
        case .deviceSuspended, .deviceRevoked:
            .authorizationChanged
        }
    }
}
