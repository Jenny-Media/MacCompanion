import CompanionInteractiveShared
import CompanionInteractiveWire
import Foundation

public enum LocalInteractiveNativeSnapshotErrorV1: Error, Equatable, Sendable {
    case unavailable
    case bindingMismatch
}

public struct LocalInteractiveNativeSnapshotCommandV1: Codable, Equatable, Sendable {
    public let commandID: UUID
    public let fence: InteractiveNativeVideoRequestFenceV0
    public init(commandID: UUID, fence: InteractiveNativeVideoRequestFenceV0) throws {
        try fence.validate()
        self.commandID = commandID
        self.fence = fence
    }
}

/// Atomic projection of one acknowledged menu runtime. No physical display ID,
/// key, name, content or pixel is exposed. A receipt alone grants no authority.
public struct LocalInteractiveNativeRuntimeSnapshotV1: Codable, Equatable, Sendable {
    public let hostID: UUID
    public let deviceID: UUID
    public let fence: InteractiveNativeVideoRequestFenceV0
    public let selectedDisplayID: UUID
    public let controlGeneration: UUID
    public let menuAppGeneration: UUID
    public let menuAppRevision: UInt64
    public let encodedWidth: Int
    public let encodedHeight: Int
    public let surfaceKind: InteractiveSurfaceKind
    public let logicalWidthPoints: UInt32
    public let logicalHeightPoints: UInt32
    public let rotation: SurfaceRotation
    public let leaseExpiresAtMonotonicNanoseconds: UInt64
    public let sessionDeadlineMonotonicNanoseconds: UInt64

    public init(command: InteractiveRuntimeInstallCommandV0,
                receipt: InteractiveRuntimeInstallReceiptV0, fence: InteractiveNativeVideoRequestFenceV0) throws {
        try command.validate()
        try receipt.validate(against: command)
        guard command.surfaceDescriptor.kind != .focusedRegion, receipt.indicatorVisible else {
            throw LocalInteractiveNativeSnapshotErrorV1.unavailable
        }
        hostID = command.lease.hostID
        deviceID = command.lease.deviceID
        try fence.validate()
        guard fence.interactiveSessionID.rawValue == command.lease.interactiveSessionID,
              fence.authorizationEpoch == command.lease.authorizationEpoch,
              fence.surfaceID.rawValue == command.lease.surfaceID,
              fence.surfaceRevision == Int64(command.lease.surfaceRevision.rawValue),
              fence.coordinateSpaceRevision == Int64(command.lease.coordinateRevision.rawValue) else {
            throw LocalInteractiveNativeSnapshotErrorV1.bindingMismatch
        }
        self.fence = fence
        selectedDisplayID = command.lease.selectedDisplayID
        controlGeneration = command.commandID
        menuAppGeneration = receipt.menuAppGeneration
        menuAppRevision = receipt.menuAppRevision
        encodedWidth = Int(command.surfaceDescriptor.encodedWidth)
        encodedHeight = Int(command.surfaceDescriptor.encodedHeight)
        surfaceKind = command.surfaceDescriptor.kind
        logicalWidthPoints = command.surfaceDescriptor.logicalWidthPoints
        logicalHeightPoints = command.surfaceDescriptor.logicalHeightPoints
        rotation = command.surfaceDescriptor.rotation
        leaseExpiresAtMonotonicNanoseconds = command.lease.expiresAtMonotonicNanoseconds
        sessionDeadlineMonotonicNanoseconds = command.sessionDeadlineMonotonicNanoseconds
        try validate()
    }

    public func validate() throws {
        try fence.validate()
        guard menuAppRevision > 0, menuAppRevision <= UInt64(Int64.max),
              (320...8192).contains(encodedWidth), (240...8192).contains(encodedHeight),
              surfaceKind == .desktop || surfaceKind == .application || surfaceKind == .window,
              logicalWidthPoints > 0, logicalHeightPoints > 0,
              leaseExpiresAtMonotonicNanoseconds > 0,
              leaseExpiresAtMonotonicNanoseconds <= sessionDeadlineMonotonicNanoseconds else {
            throw LocalInteractiveNativeSnapshotErrorV1.bindingMismatch
        }
    }

    public func isCurrent(nowMonotonicNanoseconds: UInt64) -> Bool {
        nowMonotonicNanoseconds < leaseExpiresAtMonotonicNanoseconds
            && nowMonotonicNanoseconds < sessionDeadlineMonotonicNanoseconds
    }
}

public struct LocalInteractiveNativeSnapshotReceiptV1: Codable, Equatable, Sendable {
    public let correlationID: UUID
    public let snapshot: LocalInteractiveNativeRuntimeSnapshotV1
    public init(correlationID: UUID, snapshot: LocalInteractiveNativeRuntimeSnapshotV1) throws {
        try snapshot.validate()
        self.correlationID = correlationID
        self.snapshot = snapshot
    }
    public func validate(against command: LocalInteractiveNativeSnapshotCommandV1) throws {
        try command.fence.validate()
        try snapshot.validate()
        guard correlationID == command.commandID, snapshot.fence == command.fence else {
            throw LocalInteractiveNativeSnapshotErrorV1.bindingMismatch
        }
    }
}
