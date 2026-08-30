#if os(macOS)
import CompanionDomain
import CompanionInteractiveRuntime
import CompanionLifecycle
import Foundation
import Observation

@available(macOS 26.0, *)
public enum MacInteractiveActivityIndicatorErrorV1:
    Error,
    Equatable,
    Sendable
{
    case alreadyVisible
    case stopUnavailable
    case revisionExhausted
}

@available(macOS 26.0, *)
public enum MacInteractiveActivityIndicatorPhaseV1:
    Equatable,
    Sendable
{
    case inactive
    case active
    case stopping
}

/// Process-lifetime, menu-visible Control activity state. The runtime owns all
/// show/clear mutations; UI may only request the installed local stop action.
/// Stopping remains visibly active until runtime cleanup clears it.
@available(macOS 26.0, *)
@MainActor
@Observable
public final class MacInteractiveActivityIndicatorV1:
    InteractiveRuntimeIndicatorControllingV0
{
    public private(set) var phase:
        MacInteractiveActivityIndicatorPhaseV1 = .inactive
    public private(set) var deviceDisplayName: String?
    public private(set) var interactiveSessionID: UUID?

    @ObservationIgnored
    private let menuAppGeneration: UUID
    @ObservationIgnored
    private var revision: UInt64 = 0
    @ObservationIgnored
    private var stopAction: (@MainActor @Sendable () async throws -> Void)?

    public init(menuAppGeneration: UUID = UUID()) {
        self.menuAppGeneration = menuAppGeneration
    }

    /// The authenticated admission publication and the later visible-runtime
    /// receipt must identify the same process-lifetime menu generation.
    package var admissionMenuAppGeneration: UUID { menuAppGeneration }

    public var isVisible: Bool { phase != .inactive }

    public var updateControlState: MacUpdateControlStateV0 {
        switch phase {
        case .inactive:
            return .inactive
        case .active:
            return .active
        case .stopping:
            return .cleanupUncertain
        }
    }

    public func showInteractiveIndicator(
        deviceDisplayName: DeviceDisplayName,
        interactiveSessionID: UUID
    ) async throws -> InteractiveRuntimeIndicatorSnapshotV0 {
        if phase == .active,
           self.deviceDisplayName == deviceDisplayName.rawValue,
           self.interactiveSessionID == interactiveSessionID {
            return try currentRuntimeSnapshot()
        }
        guard phase == .inactive else {
            throw MacInteractiveActivityIndicatorErrorV1.alreadyVisible
        }
        try advanceRevision()
        self.deviceDisplayName = deviceDisplayName.rawValue
        self.interactiveSessionID = interactiveSessionID
        phase = .active
        return try currentRuntimeSnapshot()
    }

    public func clearInteractiveIndicator() async throws {
        guard phase != .inactive else { return }
        try advanceRevision()
        phase = .inactive
        deviceDisplayName = nil
        interactiveSessionID = nil
    }

    public func requestStop() async throws {
        guard phase == .active, let stopAction else {
            throw MacInteractiveActivityIndicatorErrorV1.stopUnavailable
        }
        phase = .stopping
        do {
            try await stopAction()
        } catch {
            if phase == .stopping { phase = .active }
            throw error
        }
    }

    func installStopAction(
        _ action: @escaping @MainActor @Sendable () async throws -> Void
    ) {
        stopAction = action
    }

    private func currentRuntimeSnapshot() throws
        -> InteractiveRuntimeIndicatorSnapshotV0
    {
        try InteractiveRuntimeIndicatorSnapshotV0(
            menuAppGeneration: menuAppGeneration,
            menuAppRevision: revision
        )
    }

    private func advanceRevision() throws {
        guard revision
                < MonotonicRevision<AuthorizationEpochTag>.maximumWireValue else {
            throw MacInteractiveActivityIndicatorErrorV1.revisionExhausted
        }
        revision += 1
    }
}
#endif
