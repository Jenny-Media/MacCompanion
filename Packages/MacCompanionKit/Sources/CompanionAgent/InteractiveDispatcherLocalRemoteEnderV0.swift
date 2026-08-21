import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionIPC

/// Concrete Agent-side bridge from the local stop command to the sole remote
/// Interactive dispatcher for the authenticated primary session.
public struct InteractiveDispatcherLocalRemoteEnderV0:
    LocalInteractiveRemoteAuthorityEndingV0,
    Sendable
{
    private let dispatcher: InteractiveSessionWireDispatcherV0

    public init(dispatcher: InteractiveSessionWireDispatcherV0) {
        self.dispatcher = dispatcher
    }

    public func endRemoteAuthority(
        for command: LocalInteractiveStopCommandV0
    ) async throws -> LocalInteractiveRemoteEndProofV0 {
        let binding = InteractiveLocalAuthorityBindingV0(
            deviceID: command.deviceID,
            requestID: command.requestID,
            approvalID: command.approvalID,
            interactiveSessionID: command.interactiveSessionID
        )
        let ended = await dispatcher.endFromLocalAuthority(
            binding: binding,
            reason: Self.remoteReason(for: command.reason)
        )
        return LocalInteractiveRemoteEndProofV0(
            deviceID: command.deviceID,
            requestID: command.requestID,
            approvalID: command.approvalID,
            interactiveSessionID: command.interactiveSessionID,
            remoteAuthorityEnded: ended
        )
    }

    private static func remoteReason(
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
