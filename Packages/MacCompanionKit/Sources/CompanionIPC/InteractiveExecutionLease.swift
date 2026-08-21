import CompanionDomain
import CompanionInteractiveShared
import Foundation

public enum SurfaceRevisionTag: Sendable {}
public enum CoordinateRevisionTag: Sendable {}

public typealias SurfaceRevision = MonotonicRevision<SurfaceRevisionTag>
public typealias CoordinateRevision = MonotonicRevision<CoordinateRevisionTag>

public struct InteractiveExecutionLease: Codable, Equatable, Sendable {
    public static let maximumLifetimeNanoseconds: UInt64 = 10_000_000_000

    public let leaseID: UUID
    public let hostID: UUID
    public let deviceID: UUID
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let selectedDisplayID: UUID
    public let surfaceID: UUID
    public let surfaceRevision: SurfaceRevision
    public let coordinateRevision: CoordinateRevision
    public let allowedInteractionClasses: [SurfaceInteractionClass]
    public let renewalCounter: UInt64
    public let issuedAtMonotonicNanoseconds: UInt64
    public let expiresAtMonotonicNanoseconds: UInt64

    public init(
        leaseID: UUID,
        hostID: UUID,
        deviceID: UUID,
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        selectedDisplayID: UUID,
        surfaceID: UUID,
        surfaceRevision: SurfaceRevision,
        coordinateRevision: CoordinateRevision,
        allowedInteractionClasses: Set<SurfaceInteractionClass>,
        renewalCounter: UInt64,
        issuedAtMonotonicNanoseconds: UInt64,
        expiresAtMonotonicNanoseconds: UInt64
    ) throws {
        let classes = allowedInteractionClasses.sorted { $0.rawValue < $1.rawValue }
        guard authorizationEpoch.rawValue > 0,
              surfaceRevision.rawValue > 0,
              coordinateRevision.rawValue > 0,
              renewalCounter <= MonotonicRevision<AuthorizationEpochTag>.maximumWireValue,
              expiresAtMonotonicNanoseconds > issuedAtMonotonicNanoseconds,
              expiresAtMonotonicNanoseconds - issuedAtMonotonicNanoseconds
                <= Self.maximumLifetimeNanoseconds,
              classes.contains(.view),
              !classes.contains(.text) || classes.contains(.keyboard) else {
            throw InteractiveLeaseError.invalidLease
        }
        self.leaseID = leaseID
        self.hostID = hostID
        self.deviceID = deviceID
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.selectedDisplayID = selectedDisplayID
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.coordinateRevision = coordinateRevision
        self.allowedInteractionClasses = classes
        self.renewalCounter = renewalCounter
        self.issuedAtMonotonicNanoseconds = issuedAtMonotonicNanoseconds
        self.expiresAtMonotonicNanoseconds = expiresAtMonotonicNanoseconds
    }

    private enum CodingKeys: String, CodingKey {
        case leaseID
        case hostID
        case deviceID
        case interactiveSessionID
        case authorizationEpoch
        case selectedDisplayID
        case surfaceID
        case surfaceRevision
        case coordinateRevision
        case allowedInteractionClasses
        case renewalCounter
        case issuedAtMonotonicNanoseconds
        case expiresAtMonotonicNanoseconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let classes = try container.decode(
            [SurfaceInteractionClass].self,
            forKey: .allowedInteractionClasses
        )
        let canonicalClasses = classes.sorted { $0.rawValue < $1.rawValue }
        guard classes == canonicalClasses,
              Set(classes).count == classes.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .allowedInteractionClasses,
                in: container,
                debugDescription: "interaction classes must be sorted and unique"
            )
        }

        do {
            try self.init(
                leaseID: container.decode(UUID.self, forKey: .leaseID),
                hostID: container.decode(UUID.self, forKey: .hostID),
                deviceID: container.decode(UUID.self, forKey: .deviceID),
                interactiveSessionID: container.decode(
                    UUID.self,
                    forKey: .interactiveSessionID
                ),
                authorizationEpoch: container.decode(
                    AuthorizationEpoch.self,
                    forKey: .authorizationEpoch
                ),
                selectedDisplayID: container.decode(
                    UUID.self,
                    forKey: .selectedDisplayID
                ),
                surfaceID: container.decode(UUID.self, forKey: .surfaceID),
                surfaceRevision: container.decode(
                    SurfaceRevision.self,
                    forKey: .surfaceRevision
                ),
                coordinateRevision: container.decode(
                    CoordinateRevision.self,
                    forKey: .coordinateRevision
                ),
                allowedInteractionClasses: Set(classes),
                renewalCounter: container.decode(
                    UInt64.self,
                    forKey: .renewalCounter
                ),
                issuedAtMonotonicNanoseconds: container.decode(
                    UInt64.self,
                    forKey: .issuedAtMonotonicNanoseconds
                ),
                expiresAtMonotonicNanoseconds: container.decode(
                    UInt64.self,
                    forKey: .expiresAtMonotonicNanoseconds
                )
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "invalid interactive execution lease",
                    underlyingError: error
                )
            )
        }
    }

    public func validate(
        fence: InteractiveCommandFence,
        nowMonotonicNanoseconds: UInt64
    ) throws {
        guard nowMonotonicNanoseconds >= issuedAtMonotonicNanoseconds,
              nowMonotonicNanoseconds < expiresAtMonotonicNanoseconds else {
            throw InteractiveLeaseError.expired
        }
        guard fence.leaseID == leaseID else {
            throw InteractiveLeaseError.staleLease
        }
        guard fence.deviceID == deviceID,
              fence.interactiveSessionID == interactiveSessionID else {
            throw InteractiveLeaseError.wrongSession
        }
        guard fence.hostID == hostID else {
            throw InteractiveLeaseError.wrongHost
        }
        guard fence.authorizationEpoch == authorizationEpoch else {
            throw InteractiveLeaseError.staleAuthorizationEpoch
        }
        guard fence.selectedDisplayID == selectedDisplayID else {
            throw InteractiveLeaseError.wrongDisplay
        }
        guard fence.surfaceID == surfaceID else {
            throw InteractiveLeaseError.wrongSurface
        }
        guard fence.surfaceRevision == surfaceRevision else {
            throw InteractiveLeaseError.staleSurfaceRevision
        }
        guard fence.coordinateRevision == coordinateRevision else {
            throw InteractiveLeaseError.staleCoordinateRevision
        }
    }

    public func admits(_ interactionClass: SurfaceInteractionClass) -> Bool {
        allowedInteractionClasses.contains(interactionClass)
    }
}

public struct InteractiveCommandFence: Codable, Equatable, Sendable {
    public let leaseID: UUID
    public let hostID: UUID
    public let deviceID: UUID
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let selectedDisplayID: UUID
    public let surfaceID: UUID
    public let surfaceRevision: SurfaceRevision
    public let coordinateRevision: CoordinateRevision

    public init(
        leaseID: UUID,
        hostID: UUID,
        deviceID: UUID,
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        selectedDisplayID: UUID,
        surfaceID: UUID,
        surfaceRevision: SurfaceRevision,
        coordinateRevision: CoordinateRevision
    ) {
        self.leaseID = leaseID
        self.hostID = hostID
        self.deviceID = deviceID
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.selectedDisplayID = selectedDisplayID
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.coordinateRevision = coordinateRevision
    }
}

public enum InteractiveLeaseError: Error, Equatable, Sendable {
    case invalidLease
    case expired
    case staleLease
    case wrongSession
    case wrongHost
    case staleAuthorizationEpoch
    case wrongDisplay
    case wrongSurface
    case staleSurfaceRevision
    case staleCoordinateRevision
}
