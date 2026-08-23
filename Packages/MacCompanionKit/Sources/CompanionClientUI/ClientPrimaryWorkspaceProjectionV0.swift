import CompanionClient
import CompanionClientNetworkPlatform
import CompanionInteractiveClient
import CompanionObservation
import Foundation

public struct ClientActIssueProjectionV0: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let diagnosticCode: String

    public init(_ error: ClientOperationRemoteErrorV1) {
        title = "Approved Action could not continue"
        diagnosticCode = error.code
        detail = switch error.retry {
        case .never: "This action is not available for the paired device."
        case .afterUserAction: "Review the Mac or device settings, then try again."
        case .afterReconnect: "Reconnect to the Mac, then review the action again."
        case .afterApproval: "Approve the required access, then try again."
        case .backoff: "Wait briefly before trying again."
        }
    }
}

public enum ClientControlWorkspaceModeV0: Equatable, Sendable {
    case unavailable
    case ready
    case requesting
    case awaitingAcceptance
    case acceptedPreparingChannels
    case channelsReady
    case preparingInitialSurface
    case active
    case ending
    case endFailed
    case preparationFailed
    case rejected
}

public enum ClientControlWorkspaceEntryV0: Equatable, Sendable {
    case unavailable
    case requestFullControl
    case wait
    case openLiveControl
    case retryStop
    case stopFailedSession
}

public struct ClientControlWorkspaceProjectionV0: Equatable, Sendable {
    public let mode: ClientControlWorkspaceModeV0
    public let detail: String
    public let diagnosticCode: String?

    public init(
        connected: Bool,
        state: NetworkClientPrimaryControlStateV0
    ) {
        guard connected else {
            mode = .unavailable
            detail = "Reconnect before starting Remote Control."
            diagnosticCode = nil
            return
        }
        switch state {
        case .inactive:
            mode = .ready
            detail = "Starting Remote Control requires separate device approval."
            diagnosticCode = nil
        case .requestSubmitted:
            mode = .requesting
            detail = "Waiting for the Mac to request device approval."
            diagnosticCode = nil
        case .approvalSubmitted:
            mode = .awaitingAcceptance
            detail = "Device approval was sent; the Mac is creating the session."
            diagnosticCode = nil
        case .accepted:
            mode = .acceptedPreparingChannels
            detail = "Session approved; secure screen and input channels are still starting."
            diagnosticCode = nil
        case let .preparing(_, _, _, phase):
            switch phase {
            case .roleChannelsConnecting:
                mode = .acceptedPreparingChannels
                detail = "Session approved; connecting secure screen and input channels."
            case .roleChannelsReady:
                mode = .channelsReady
                detail = "Secure channels are ready; open Remote Control to start the live surface."
            case .initialSurface:
                mode = .preparingInitialSurface
                detail = "Waiting for the first verified frame before enabling input."
            }
            diagnosticCode = nil
        case .active:
            mode = .active
            detail = "Remote Control is live; screen, pointer, and keyboard input use the approved session."
            diagnosticCode = nil
        case .ending:
            mode = .ending
            detail = "Stopping Remote Control and waiting for the Mac to finish safety cleanup."
            diagnosticCode = nil
        case let .endFailed(_, _, error):
            mode = .endFailed
            detail = switch error.retry {
            case .never:
                "The Mac could not confirm that Remote Control stopped."
            case .afterUserAction:
                "Check the Mac, then try stopping Remote Control again."
            case .afterReconnect:
                "Reconnect to confirm Remote Control is no longer active."
            case .afterApproval:
                "Approve the required access, then try stopping again."
            case .backoff:
                "Wait briefly, then try stopping Remote Control again."
            }
            diagnosticCode = error.code
        case let .preparationFailed(_, _, phase):
            mode = .preparationFailed
            detail = switch phase {
            case .roleChannelsConnecting:
                "Secure screen and input channels could not be connected."
            case .roleChannelsReady, .initialSurface:
                "The live surface could not be verified; input remains disabled."
            }
            diagnosticCode = "interactive.preparationFailed"
        case let .remoteRejected(error):
            mode = .rejected
            detail = switch error.retry {
            case .never: "Remote Control is not available for this device."
            case .afterUserAction: "Review the Mac or device settings, then try again."
            case .afterReconnect: "Reconnect to the Mac, then try again."
            case .afterApproval: "Approve the required access, then try again."
            case .backoff: "Wait briefly before trying again."
            }
            diagnosticCode = error.code
        }
    }

    public func entry(
        hasLocalLiveProduct: Bool
    ) -> ClientControlWorkspaceEntryV0 {
        switch mode {
        case .ready, .rejected:
            .requestFullControl
        case .channelsReady, .active:
            .openLiveControl
        case .preparingInitialSurface where hasLocalLiveProduct:
            .openLiveControl
        case .endFailed:
            .retryStop
        case .preparationFailed:
            .stopFailedSession
        case .unavailable:
            .unavailable
        case .requesting, .awaitingAcceptance,
             .acceptedPreparingChannels, .preparingInitialSurface, .ending:
            .wait
        }
    }
}

/// Value-only projection of the selected primary product. It deliberately
/// omits command channels, connection identifiers, endpoints, and route
/// records while retaining one closed authenticated provenance class.
public struct ClientPrimaryWorkspaceProjectionV0: Sendable {
    public let revision: UInt64
    public let connected: Bool
    public let authenticatedRouteClass:
        NetworkClientAuthenticatedRouteClassV1?
    public let observe: ClientObserveWorkspaceProjectionV0
    public let approvedActions: GrantedCapabilityCatalogV1?
    public let operationState: ClientOperationSessionStateV1?
    public let approvalPrompt: ClientOperationApprovalPromptV1?
    public let actIssue: ClientActIssueProjectionV0?
    public let control: ClientControlWorkspaceProjectionV0

    public init(
        macName: String,
        snapshot: NetworkClientPrimaryApplicationSnapshotV0,
        monotonicNowMilliseconds: Int64
    ) throws {
        revision = snapshot.revision
        connected = snapshot.availability == .connected
        authenticatedRouteClass = connected
            ? snapshot.authenticatedRouteClass : nil
        let observeIssue: ClientObserveIssueProjectionV0?
        switch snapshot.latestObserveErrorRequest {
        case .status:
            observeIssue = snapshot.statusError.map {
                ClientObserveIssueProjectionV0(request: .status, error: $0)
            }
        case .audit:
            observeIssue = snapshot.auditError.map {
                ClientObserveIssueProjectionV0(request: .audit, error: $0)
            }
        case nil:
            observeIssue = nil
        }
        observe = try ClientObserveWorkspaceProjectionV0(
            macName: macName,
            observedStatus: snapshot.observedStatus,
            reachability: connected ? .reachable : .unreachable,
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            latestActivityPage: snapshot.latestAuditPage,
            issue: observeIssue
        )
        approvedActions = connected ? snapshot.catalog : nil
        operationState = connected ? snapshot.operationState : nil
        approvalPrompt = connected ? snapshot.approvalPrompt : nil
        if connected {
            actIssue = switch snapshot.latestActErrorRequest {
            case .catalog:
                snapshot.catalogRemoteError.map(ClientActIssueProjectionV0.init)
            case .operation:
                snapshot.operationRemoteError.map(ClientActIssueProjectionV0.init)
            case nil: nil
            }
        } else {
            actIssue = nil
        }
        control = ClientControlWorkspaceProjectionV0(
            connected: connected,
            state: snapshot.controlState
        )
    }
}
