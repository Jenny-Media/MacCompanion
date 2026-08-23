import CompanionClient
import CompanionClientNetworkPlatform
import CompanionInteractiveClient
import CompanionInteractiveWire
import CompanionStudy
import CompanionWire
import Combine
import Foundation

public enum ClientStage3StudyActJobProjectionV1 {
    public static let setAudioMutedCapabilityID =
        "maccompanion.system.setAudioMuted"

    public static func result(
        capabilityID: String,
        state: ClientOperationSessionStateV1
    ) -> Stage3StudyAttemptResultV1? {
        guard capabilityID == setAudioMutedCapabilityID else { return nil }
        return switch state {
        case let .terminal(value):
            switch value {
            case .succeeded: .completed
            case .denied: .denied
            case .expired, .cancelled: .notCompleted
            case .failed: .failed
            case .outcomeUnknown: .outcomeUnknown
            case .pending: nil
            }
        case .remoteRejected:
            .failed
        case .idle, .awaitingInvokeReply, .awaitingUserPresence,
             .awaitingApprovalReply, .observing, .awaitingStatusReply,
             .awaitingCancelReply, .deliveryUnknown, .invalidated:
            nil
        }
    }
}

public enum ClientStage3StudyControlJobProjectionV1 {
    public static func accepts(
        _ category: Stage3StudyJobCategoryV1
    ) -> Bool {
        switch category {
        case .controlUnexpectedDialog, .controlDevelopmentApp,
             .controlOtherOwnedApp:
            true
        case .observeLongRunningTask, .observeSystemHealth,
             .observeAvailability, .actSetAudioMuted:
            false
        }
    }
}

public enum ClientStage3StudyObserveJobProjectionV1 {
    public static func accepts(
        _ category: Stage3StudyJobCategoryV1
    ) -> Bool {
        switch category {
        case .observeLongRunningTask, .observeSystemHealth,
             .observeAvailability:
            true
        case .actSetAudioMuted, .controlUnexpectedDialog,
             .controlDevelopmentApp, .controlOtherOwnedApp:
            false
        }
    }
}

public enum ClientStage3StudyRouteProjectionV1 {
    public static func routeClass(
        _ value: NetworkClientAuthenticatedRouteClassV1
    ) -> Stage3StudyRouteClassV1 {
        switch value {
        case .lan: .lan
        case .privateDNS: .privateDNS
        case .privateNetwork: .privateNetwork
        }
    }
}

public enum ClientPrimaryWorkspaceStudyCaptureErrorV1:
    Error, Equatable, Sendable
{
    case unavailable
    case invalidJob
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class ClientPrimaryWorkspaceModelV0: ObservableObject {
    @Published public private(set) var projection:
        ClientPrimaryWorkspaceProjectionV0
    @Published public private(set) var projectionFailed = false

    private let macName: String
    private let primaryState:
        NetworkClientPrimaryApplicationStateV0
    private let monotonicNowMilliseconds:
        @Sendable () -> Int64
    private let updates: AsyncStream<
        NetworkClientPrimaryApplicationSnapshotV0
    >
    private let studyCapture: Stage3StudyLocalCaptureV1?
    private let studyCaptureFailure: @MainActor @Sendable () -> Void
    private var updateTask: Task<Void, Never>?

    public convenience init(
        macName: String,
        primaryState: NetworkClientPrimaryApplicationStateV0,
        monotonicNowMilliseconds: @escaping @Sendable () -> Int64,
        studyCapture: Stage3StudyLocalCaptureV1? = nil,
        studyCaptureFailure: @escaping @MainActor @Sendable () -> Void = {}
    ) throws {
        try self.init(
            macName: macName,
            primaryState: primaryState,
            initialSnapshot: primaryState.snapshot(),
            updates: primaryState.updates,
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            studyCapture: studyCapture,
            studyCaptureFailure: studyCaptureFailure
        )
    }

    package init(
        macName: String,
        primaryState: NetworkClientPrimaryApplicationStateV0,
        initialSnapshot: NetworkClientPrimaryApplicationSnapshotV0,
        updates: AsyncStream<NetworkClientPrimaryApplicationSnapshotV0>,
        monotonicNowMilliseconds: @escaping @Sendable () -> Int64,
        studyCapture: Stage3StudyLocalCaptureV1? = nil,
        studyCaptureFailure: @escaping @MainActor @Sendable () -> Void = {}
    ) throws {
        self.macName = macName
        self.primaryState = primaryState
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
        self.updates = updates
        self.studyCapture = studyCapture
        self.studyCaptureFailure = studyCaptureFailure
        projection = try ClientPrimaryWorkspaceProjectionV0(
            macName: macName,
            snapshot: initialSnapshot,
            monotonicNowMilliseconds: monotonicNowMilliseconds()
        )
    }

    public func start() {
        guard updateTask == nil else { return }
        captureTransitions(
            previousConnected: false,
            previousObserveState: nil,
            previousRouteClass: nil,
            current: projection
        )
        let updates = updates
        updateTask = Task { [weak self, updates] in
            for await snapshot in updates {
                guard !Task.isCancelled else { return }
                self?.apply(snapshot)
            }
        }
    }

    public func stop() {
        updateTask?.cancel()
        updateTask = nil
    }

    public func refreshStatus() async throws {
        try await primaryState.refreshStatus()
    }

    public func loadNextActivityPage(limit: UInt8 = 50) async throws {
        try await primaryState.loadNextActivityPage(limit: limit)
    }

    public func resetActivityTraversal() async throws {
        try await primaryState.resetActivityTraversal()
    }

    public func reloadApprovedActions() async throws {
        try await primaryState.reloadApprovedActions()
    }

    @discardableResult
    public func beginOperation(
        capabilityID: String,
        parameters: CanonicalJSONValue,
        operationID: WireUUID
    ) async throws -> ClientActChannelEventV1 {
        try await primaryState.beginOperation(
            capabilityID: capabilityID,
            parameters: parameters,
            operationID: operationID
        )
    }

    @discardableResult
    public func resumeOperationStatus(
        capabilityID: String,
        operationID: WireUUID
    ) async throws -> ClientActChannelEventV1 {
        try await primaryState.resumeOperationStatus(
            capabilityID: capabilityID,
            operationID: operationID
        )
    }

    @discardableResult
    public func queryOperation() async throws -> ClientActChannelEventV1 {
        try await primaryState.queryOperation()
    }

    @discardableResult
    public func cancelOperation() async throws -> ClientActChannelEventV1 {
        try await primaryState.cancelOperation()
    }

    public func finishOperation() async throws {
        try await primaryState.finishOperation()
    }

    @discardableResult
    public func recordSetAudioMutedStudyJob(
        capabilityID: String
    ) async throws -> Stage3StudyReportV1 {
        guard let studyCapture else {
            throw ClientPrimaryWorkspaceStudyCaptureErrorV1.unavailable
        }
        guard let operationState = projection.operationState,
              let result = ClientStage3StudyActJobProjectionV1.result(
                capabilityID: capabilityID,
                state: operationState
              ) else {
            throw ClientPrimaryWorkspaceStudyCaptureErrorV1.invalidJob
        }
        return try await studyCapture.recordJob(
            path: .act,
            category: .actSetAudioMuted,
            result: result
        )
    }

    @discardableResult
    public func recordObserveStudyJob(
        category: Stage3StudyJobCategoryV1
    ) async throws -> Stage3StudyReportV1 {
        guard let studyCapture else {
            throw ClientPrimaryWorkspaceStudyCaptureErrorV1.unavailable
        }
        guard projection.observe.status.state == .live,
              ClientStage3StudyObserveJobProjectionV1.accepts(category) else {
            throw ClientPrimaryWorkspaceStudyCaptureErrorV1.invalidJob
        }
        return try await studyCapture.recordJob(
            path: .observe,
            category: category,
            result: .completed
        )
    }

    @discardableResult
    public func recordControlStudyJob(
        category: Stage3StudyJobCategoryV1,
        snapshot: ClientStage3StudyControlSnapshotV1
    ) async throws -> Stage3StudyReportV1 {
        guard let studyCapture else {
            throw ClientPrimaryWorkspaceStudyCaptureErrorV1.unavailable
        }
        guard ClientStage3StudyControlJobProjectionV1.accepts(category) else {
            throw ClientPrimaryWorkspaceStudyCaptureErrorV1.invalidJob
        }
        return try await studyCapture.recordJob(
            path: .control,
            category: category,
            result: .completed,
            controlModesUsed: snapshot.modesUsed,
            controlDurationDelta: snapshot.durationDelta
        )
    }

    @discardableResult
    public func beginInteractiveControl(
        effects: Set<InteractiveControlEffect>
    ) async throws -> ClientInteractivePrimarySessionEventV0 {
        try await primaryState.beginInteractiveControl(effects: effects)
    }

    @discardableResult
    public func endInteractiveControl()
        async throws -> ClientInteractivePrimarySessionEventV0
    {
        try await primaryState.endInteractiveControl()
    }

    private func apply(_ snapshot: NetworkClientPrimaryApplicationSnapshotV0) {
        guard snapshot.revision > projection.revision else { return }
        do {
            let previous = projection
            let next = try ClientPrimaryWorkspaceProjectionV0(
                macName: macName,
                snapshot: snapshot,
                monotonicNowMilliseconds: monotonicNowMilliseconds()
            )
            projection = next
            projectionFailed = false
            captureTransitions(
                previousConnected: previous.connected,
                previousObserveState: previous.observe.status.state,
                previousRouteClass: previous.authenticatedRouteClass,
                current: next
            )
        } catch {
            projectionFailed = true
        }
    }

    private func captureTransitions(
        previousConnected: Bool,
        previousObserveState: ClientObserveStatusStateV0?,
        previousRouteClass: NetworkClientAuthenticatedRouteClassV1?,
        current: ClientPrimaryWorkspaceProjectionV0
    ) {
        guard let studyCapture else { return }
        let recordsConnection = !previousConnected && current.connected
        let recordsRoute = current.connected
            && current.authenticatedRouteClass != nil
            && current.authenticatedRouteClass != previousRouteClass
        if recordsConnection || recordsRoute {
            Task { [weak self, studyCapture] in
                do {
                    if recordsConnection {
                        _ = try await studyCapture.recordOperationalEvent(
                            kind: .connection,
                            initiator: .system,
                            result: .completed
                        )
                    }
                    if recordsRoute,
                       let value = current.authenticatedRouteClass {
                        _ = try await studyCapture.recordRouteClass(
                            ClientStage3StudyRouteProjectionV1.routeClass(
                                value
                            )
                        )
                    }
                } catch let error as Stage3StudyLocalCaptureErrorV1
                    where error == .noActiveSession
                        || error == .noEnrollment {
                    return
                } catch {
                    self?.studyCaptureFailure()
                }
            }
        }
        if previousObserveState != .live,
           current.observe.status.state == .live {
            Task { [weak self, studyCapture] in
                do {
                    guard let duration = await studyCapture
                        .elapsedSinceSessionStartMilliseconds() else {
                        return
                    }
                    _ = try await studyCapture.recordFirstFreshObserve(
                        .completed,
                        durationMilliseconds: duration
                    )
                } catch let error as Stage3StudyLocalCaptureErrorV1
                    where error == .noActiveSession
                        || error == .noEnrollment {
                    return
                } catch {
                    self?.studyCaptureFailure()
                }
            }
        }
    }

    deinit {
        updateTask?.cancel()
    }
}
