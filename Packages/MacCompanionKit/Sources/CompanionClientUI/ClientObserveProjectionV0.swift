import CompanionClient
import CompanionDomain
import CompanionObservation
import CompanionWire
import Foundation

public enum ClientObserveStatusStateV0: String, Equatable, Sendable {
    case waitingForStatus
    case live
    case stale
    case unreachable
    case unavailable
}

public struct ClientObserveSystemProjectionV0: Equatable, Sendable {
    public let operatingSystem: String
    public let hostState: String
    public let uptimeSeconds: Int64
    public let cpuUtilizationBasisPoints: UInt16
    public let memoryUsedBytes: Int64
    public let memoryTotalBytes: Int64
    public let storageAvailableBytes: Int64
    public let storageTotalBytes: Int64
    public let power: String

    fileprivate init(snapshot: StatusSnapshotBody) {
        let system = snapshot.system
        operatingSystem = "\(system.osName) \(system.osVersion) (\(system.osBuild))"
        hostState = Self.hostState(snapshot.hostState)
        uptimeSeconds = system.uptimeSeconds
        cpuUtilizationBasisPoints = system.cpuUtilizationBasisPoints
        memoryUsedBytes = system.memoryUsedBytes
        memoryTotalBytes = system.memoryTotalBytes
        storageAvailableBytes = system.storageAvailableBytes
        storageTotalBytes = system.storageTotalBytes
        switch (system.powerSource, system.batteryLevelPercent) {
        case let (.battery, level?): power = "Battery, \(level)%"
        case (.battery, nil): power = "Battery"
        case let (.ac, level?): power = "Power adapter, \(level)%"
        case (.ac, nil): power = "Power adapter"
        case let (.unknown, level?): power = "Power source unknown, \(level)%"
        case (.unknown, nil): power = "Power source unknown"
        }
    }

    private static func hostState(_ state: HostState) -> String {
        switch state {
        case .userSessionActive: "User session active"
        case .userSessionLocked: "Mac locked"
        case .otherConsoleUserActive: "Another user is active"
        case .serviceStoppingForLogout: "Signing out"
        case .hostPreparingForSleep: "Preparing for sleep"
        }
    }
}

public struct ClientObserveStatusProjectionV0: Equatable, Sendable {
    public let state: ClientObserveStatusStateV0
    public let title: String
    public let detail: String
    public let systemImage: String
    public let canRefresh: Bool
    public let observedAt: Date?
    public let estimatedAgeMilliseconds: Int64?
    public let system: ClientObserveSystemProjectionV0?

    public init(
        status: ClientObservedStatusV0?,
        reachability: ClientReachabilityState,
        monotonicNowMilliseconds: Int64
    ) throws {
        canRefresh = reachability == .reachable
        guard let status else {
            observedAt = nil
            estimatedAgeMilliseconds = nil
            system = nil
            if reachability == .reachable {
                state = .waitingForStatus
                title = "Waiting for status"
                detail = "The Mac is connected, but no validated status has arrived yet."
                systemImage = "clock"
            } else {
                state = .unavailable
                title = "Mac unavailable"
                detail = "No validated status is available. Reconnect to request current information."
                systemImage = "exclamationmark.triangle"
            }
            return
        }

        let assessment = try status.freshness.assess(
            reachability: reachability,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        observedAt = Date(
            timeIntervalSince1970:
                TimeInterval(assessment.observedAtUnixMilliseconds) / 1_000
        )
        estimatedAgeMilliseconds = assessment.estimatedAgeMilliseconds
        system = ClientObserveSystemProjectionV0(snapshot: status.snapshot)
        switch assessment.state {
        case .live:
            state = .live
            title = "Live status"
            detail = "This information is within the Mac's validated freshness window."
            systemImage = "checkmark.circle"
        case .stale:
            state = .stale
            title = "Status is out of date"
            detail = "This is the last validated status. Refresh before relying on it."
            systemImage = "clock.badge.exclamationmark"
        case .unreachable:
            state = .unreachable
            title = "Mac unreachable"
            detail = "Showing the last validated status. It is not current or live."
            systemImage = "wifi.exclamationmark"
        }
    }
}

public struct ClientObserveIssueProjectionV0: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let diagnosticCode: String

    public init(
        request: ClientObserveRequestKindV0,
        error: ClientObserveRemoteErrorV0
    ) {
        title = request == .status
            ? "Status could not be refreshed"
            : "Activity could not be loaded"
        diagnosticCode = error.code
        detail = switch error.retry {
        case .never: "This request is not available for the paired device."
        case .afterUserAction: "Review the Mac or device settings, then try again."
        case .afterReconnect: "Reconnect to the Mac, then try again."
        case .afterApproval: "Approve the required access on the Mac, then try again."
        case .backoff: "Wait briefly before trying again."
        }
    }
}

public struct ClientObserveWorkspaceProjectionV0: Equatable, Sendable {
    public let macName: String
    public let status: ClientObserveStatusProjectionV0
    public let activity: ClientAuditHistoryProjectionV1?
    public let issue: ClientObserveIssueProjectionV0?

    public init(
        macName: String,
        observedStatus: ClientObservedStatusV0?,
        reachability: ClientReachabilityState,
        monotonicNowMilliseconds: Int64,
        latestActivityPage: AuditListResponseBodyV1? = nil,
        issue: ClientObserveIssueProjectionV0? = nil
    ) throws {
        self.macName = macName
        status = try ClientObserveStatusProjectionV0(
            status: observedStatus,
            reachability: reachability,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        activity = latestActivityPage.map(ClientAuditHistoryProjectionV1.init)
        self.issue = issue
    }
}
