import CompanionDomain
import CompanionInteractiveShared
import Foundation

public enum LocalInteractiveSurfaceRuntimeErrorV1:
    Error, Equatable, Sendable
{
    case invalidCommand
    case invalidReceipt
}

public struct LocalInteractiveSurfaceTargetsCommandV1:
    Codable, Equatable, Sendable
{
    public let commandID: UUID
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch

    public init(
        commandID: UUID,
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch
    ) throws {
        guard authorizationEpoch.rawValue >= 1 else {
            throw LocalInteractiveSurfaceRuntimeErrorV1.invalidCommand
        }
        self.commandID = commandID
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
    }
}

public struct LocalInteractiveSurfaceTargetCandidateV1:
    Codable, Equatable, Sendable
{
    public let targetToken: UUID
    public let kind: InteractiveSurfaceKind
    public let applicationToken: UUID
    public let applicationName: String
    public let windowOrdinal: UInt8?
    public let currentWindowAvailable: Bool

    public init(_ candidate: AdaptiveSurfaceTargetCandidateV0) {
        targetToken = candidate.targetToken
        kind = candidate.kind
        applicationToken = candidate.applicationToken
        applicationName = candidate.applicationName
        windowOrdinal = candidate.windowOrdinal
        currentWindowAvailable = candidate.currentWindowAvailable
    }

    public func materialize() throws -> AdaptiveSurfaceTargetCandidateV0 {
        try AdaptiveSurfaceTargetCandidateV0(
            targetToken: targetToken,
            kind: kind,
            applicationToken: applicationToken,
            applicationName: applicationName,
            windowOrdinal: windowOrdinal,
            currentWindowAvailable: currentWindowAvailable
        )
    }
}

public struct LocalInteractiveSurfaceTargetsReceiptV1:
    Codable, Equatable, Sendable
{
    /// Keeps the complete canonical reply below the authenticated local-XPC
    /// 4 KiB bound even when every allowed application name is maximal.
    public static let maximumCandidates = 8

    public let correlationID: UUID
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let revision: UInt64
    public let createdAtMonotonicMilliseconds: Int64
    public let expiresAtMonotonicMilliseconds: Int64
    public let candidates: [LocalInteractiveSurfaceTargetCandidateV1]

    public init(
        correlationID: UUID,
        snapshot: AdaptiveSurfaceTargetInventorySnapshotV0
    ) throws {
        self.correlationID = correlationID
        interactiveSessionID = snapshot.interactiveSessionID
        authorizationEpoch = snapshot.authorizationEpoch
        revision = snapshot.revision
        createdAtMonotonicMilliseconds =
            snapshot.createdAtMonotonicMilliseconds
        expiresAtMonotonicMilliseconds =
            snapshot.expiresAtMonotonicMilliseconds
        candidates = snapshot.candidates.prefix(Self.maximumCandidates)
            .map(LocalInteractiveSurfaceTargetCandidateV1.init)
        _ = try materialize()
    }

    public func validate(
        against command: LocalInteractiveSurfaceTargetsCommandV1
    ) throws {
        guard correlationID == command.commandID,
              interactiveSessionID == command.interactiveSessionID,
              authorizationEpoch == command.authorizationEpoch else {
            throw LocalInteractiveSurfaceRuntimeErrorV1.invalidReceipt
        }
        _ = try materialize()
    }

    public func materialize()
        throws -> AdaptiveSurfaceTargetInventorySnapshotV0
    {
        guard candidates.count <= Self.maximumCandidates else {
            throw LocalInteractiveSurfaceRuntimeErrorV1.invalidReceipt
        }
        return try AdaptiveSurfaceTargetInventorySnapshotV0(
            interactiveSessionID: interactiveSessionID,
            authorizationEpoch: authorizationEpoch,
            revision: revision,
            createdAtMonotonicMilliseconds:
                createdAtMonotonicMilliseconds,
            expiresAtMonotonicMilliseconds:
                expiresAtMonotonicMilliseconds,
            candidates: try candidates.map { try $0.materialize() }
        )
    }
}

public struct LocalInteractiveSurfaceResolveCommandV1:
    Codable, Equatable, Sendable
{
    public let commandID: UUID
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let currentSurfaceID: UUID
    public let expectedSurfaceRevision:
        CompanionInteractiveShared.SurfaceRevision
    public let expectedCoordinateSpaceRevision: CoordinateSpaceRevision
    public let targetKind: InteractiveSurfaceKind
    public let targetToken: UUID?

    public init(
        commandID: UUID,
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        currentSurfaceID: UUID,
        expectedSurfaceRevision:
            CompanionInteractiveShared.SurfaceRevision,
        expectedCoordinateSpaceRevision: CoordinateSpaceRevision,
        targetKind: InteractiveSurfaceKind,
        targetToken: UUID?
    ) throws {
        guard authorizationEpoch.rawValue >= 1,
              expectedSurfaceRevision.rawValue >= 1,
              expectedCoordinateSpaceRevision.rawValue >= 1,
              (targetKind == .desktop) == (targetToken == nil) else {
            throw LocalInteractiveSurfaceRuntimeErrorV1.invalidCommand
        }
        self.commandID = commandID
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.currentSurfaceID = currentSurfaceID
        self.expectedSurfaceRevision = expectedSurfaceRevision
        self.expectedCoordinateSpaceRevision =
            expectedCoordinateSpaceRevision
        self.targetKind = targetKind
        self.targetToken = targetToken
    }
}

public struct LocalInteractiveSurfaceResolvedReceiptV1:
    Codable, Equatable, Sendable
{
    public let correlationID: UUID
    public let descriptor: AdaptiveSurfaceDescriptor

    public init(
        correlationID: UUID,
        descriptor: AdaptiveSurfaceDescriptor
    ) throws {
        try descriptor.validate()
        self.correlationID = correlationID
        self.descriptor = descriptor
    }

    public func validate(
        against command: LocalInteractiveSurfaceResolveCommandV1
    ) throws {
        try descriptor.validate()
        guard correlationID == command.commandID,
              descriptor.interactiveSessionID
                == command.interactiveSessionID,
              descriptor.authorizationEpoch
                == command.authorizationEpoch,
              descriptor.kind == command.targetKind else {
            throw LocalInteractiveSurfaceRuntimeErrorV1.invalidReceipt
        }
    }
}

public struct LocalInteractiveSurfaceFailureCommandV1:
    Codable, Equatable, Sendable
{
    public let commandID: UUID
    public let interactiveSessionID: UUID
    public let reason: InteractiveSessionEndReason

    public init(
        commandID: UUID,
        interactiveSessionID: UUID,
        reason: InteractiveSessionEndReason
    ) {
        self.commandID = commandID
        self.interactiveSessionID = interactiveSessionID
        self.reason = reason
    }
}

public struct LocalInteractiveSurfaceFailureReceiptV1:
    Codable, Equatable, Sendable
{
    public let correlationID: UUID
    public let interactiveSessionID: UUID
    public let terminated: Bool

    public init(
        correlationID: UUID,
        interactiveSessionID: UUID,
        terminated: Bool
    ) throws {
        guard terminated else {
            throw LocalInteractiveSurfaceRuntimeErrorV1.invalidReceipt
        }
        self.correlationID = correlationID
        self.interactiveSessionID = interactiveSessionID
        self.terminated = terminated
    }

    public func validate(
        against command: LocalInteractiveSurfaceFailureCommandV1
    ) throws {
        guard correlationID == command.commandID,
              interactiveSessionID == command.interactiveSessionID,
              terminated else {
            throw LocalInteractiveSurfaceRuntimeErrorV1.invalidReceipt
        }
    }
}
