import CompanionDomain
import CompanionInteractiveShared
import Foundation

public enum InteractiveRuntimeMessageErrorV0: Error, Equatable, Sendable {
    case invalidVersion
    case invalidTime
    case bindingMismatch
    case readinessIncomplete
    case teardownIncomplete
    case invalidRenewal
    case invalidSurfaceTransition
    case invalidSurfaceAcknowledgement
}

public struct InteractiveRuntimeInstallCommandV0: Codable, Equatable, Sendable {
    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let lease: InteractiveExecutionLease
    public let deviceDisplayName: DeviceDisplayName
    public let surfaceDescriptor: AdaptiveSurfaceDescriptor
    public let sessionDeadlineMonotonicNanoseconds: UInt64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        lease: InteractiveExecutionLease,
        deviceDisplayName: DeviceDisplayName,
        surfaceDescriptor: AdaptiveSurfaceDescriptor,
        sessionDeadlineMonotonicNanoseconds: UInt64
    ) throws {
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.lease = lease
        self.deviceDisplayName = deviceDisplayName
        self.surfaceDescriptor = surfaceDescriptor
        self.sessionDeadlineMonotonicNanoseconds = sessionDeadlineMonotonicNanoseconds
        try validate()
    }

    public func validate() throws {
        guard protocolVersion == .init() else {
            throw InteractiveRuntimeMessageErrorV0.invalidVersion
        }
        try surfaceDescriptor.validate()
        guard lease.interactiveSessionID
                == surfaceDescriptor.interactiveSessionID,
              lease.authorizationEpoch
                == surfaceDescriptor.authorizationEpoch,
              lease.surfaceID == surfaceDescriptor.surfaceID,
              lease.surfaceRevision.rawValue
                == surfaceDescriptor.surfaceRevision.rawValue,
              lease.coordinateRevision.rawValue
                == surfaceDescriptor.coordinateSpaceRevision.rawValue,
              lease.allowedInteractionClasses
                == surfaceDescriptor.interactionClasses else {
            throw InteractiveRuntimeMessageErrorV0.bindingMismatch
        }
        guard sessionDeadlineMonotonicNanoseconds
                > lease.issuedAtMonotonicNanoseconds,
              lease.expiresAtMonotonicNanoseconds
                <= sessionDeadlineMonotonicNanoseconds else {
            throw InteractiveRuntimeMessageErrorV0.invalidTime
        }
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case commandID
        case lease
        case deviceDisplayName
        case surfaceDescriptor
        case sessionDeadlineMonotonicNanoseconds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                protocolVersion: container.decode(
                    LocalIPCProtocolVersion.self,
                    forKey: .protocolVersion
                ),
                commandID: container.decode(UUID.self, forKey: .commandID),
                lease: container.decode(
                    InteractiveExecutionLease.self,
                    forKey: .lease
                ),
                deviceDisplayName: container.decode(
                    DeviceDisplayName.self,
                    forKey: .deviceDisplayName
                ),
                surfaceDescriptor: container.decode(
                    AdaptiveSurfaceDescriptor.self,
                    forKey: .surfaceDescriptor
                ),
                sessionDeadlineMonotonicNanoseconds: container.decode(
                    UInt64.self,
                    forKey: .sessionDeadlineMonotonicNanoseconds
                )
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "invalid Interactive runtime install command",
                    underlyingError: error
                )
            )
        }
    }
}

public struct InteractiveRuntimeInstallReceiptV0: Codable, Equatable, Sendable {
    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let leaseID: UUID
    public let interactiveSessionID: UUID
    public let selectedDisplayID: UUID
    public let menuAppGeneration: UUID
    public let menuAppRevision: UInt64
    public let readyInteractionClasses: [SurfaceInteractionClass]
    public let indicatorVisible: Bool

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        leaseID: UUID,
        interactiveSessionID: UUID,
        selectedDisplayID: UUID,
        menuAppGeneration: UUID,
        menuAppRevision: UInt64,
        readyInteractionClasses: Set<SurfaceInteractionClass>,
        indicatorVisible: Bool
    ) throws {
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.leaseID = leaseID
        self.interactiveSessionID = interactiveSessionID
        self.selectedDisplayID = selectedDisplayID
        self.menuAppGeneration = menuAppGeneration
        self.menuAppRevision = menuAppRevision
        self.readyInteractionClasses = readyInteractionClasses.sorted {
            $0.rawValue < $1.rawValue
        }
        self.indicatorVisible = indicatorVisible
        try validateShape()
    }

    public func validate(against command: InteractiveRuntimeInstallCommandV0) throws {
        try validateShape()
        guard correlationID == command.commandID,
              leaseID == command.lease.leaseID,
              interactiveSessionID == command.lease.interactiveSessionID,
              selectedDisplayID == command.lease.selectedDisplayID else {
            throw InteractiveRuntimeMessageErrorV0.bindingMismatch
        }
        guard Set(readyInteractionClasses).isSuperset(
            of: command.lease.allowedInteractionClasses
        ) else {
            throw InteractiveRuntimeMessageErrorV0.readinessIncomplete
        }
    }

    private func validateShape() throws {
        guard protocolVersion == .init() else {
            throw InteractiveRuntimeMessageErrorV0.invalidVersion
        }
        guard menuAppRevision >= 1,
              readyInteractionClasses == readyInteractionClasses.sorted(
                by: { $0.rawValue < $1.rawValue }
              ),
              Set(readyInteractionClasses).count
                == readyInteractionClasses.count,
              readyInteractionClasses.contains(.view),
              indicatorVisible else {
            throw InteractiveRuntimeMessageErrorV0.readinessIncomplete
        }
    }
}

public struct InteractiveRuntimeLeaseRenewalV0: Codable, Equatable, Sendable {
    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let previousLeaseID: UUID
    public let replacement: InteractiveExecutionLease

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        previousLeaseID: UUID,
        replacement: InteractiveExecutionLease
    ) throws {
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.previousLeaseID = previousLeaseID
        self.replacement = replacement
        guard protocolVersion == .init() else {
            throw InteractiveRuntimeMessageErrorV0.invalidVersion
        }
    }

    public func validate(current: InteractiveExecutionLease) throws {
        guard previousLeaseID == current.leaseID,
              replacement.leaseID != current.leaseID,
              replacement.hostID == current.hostID,
              replacement.deviceID == current.deviceID,
              replacement.interactiveSessionID == current.interactiveSessionID,
              replacement.authorizationEpoch == current.authorizationEpoch,
              replacement.selectedDisplayID == current.selectedDisplayID,
              replacement.surfaceID == current.surfaceID,
              replacement.surfaceRevision == current.surfaceRevision,
              replacement.coordinateRevision == current.coordinateRevision,
              replacement.allowedInteractionClasses
                == current.allowedInteractionClasses,
              current.renewalCounter
                < MonotonicRevision<AuthorizationEpochTag>.maximumWireValue,
              replacement.renewalCounter == current.renewalCounter + 1,
              replacement.issuedAtMonotonicNanoseconds
                >= current.issuedAtMonotonicNanoseconds,
              replacement.issuedAtMonotonicNanoseconds
                < current.expiresAtMonotonicNanoseconds else {
            throw InteractiveRuntimeMessageErrorV0.invalidRenewal
        }
    }
}

public struct InteractiveRuntimeSurfaceTransitionCommandV0:
    Codable,
    Equatable,
    Sendable
{
    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let previousLeaseID: UUID
    public let replacement: InteractiveExecutionLease
    public let descriptor: AdaptiveSurfaceDescriptor

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        previousLeaseID: UUID,
        replacement: InteractiveExecutionLease,
        descriptor: AdaptiveSurfaceDescriptor
    ) throws {
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.previousLeaseID = previousLeaseID
        self.replacement = replacement
        self.descriptor = descriptor
        try validateShape()
    }

    public func validate(
        current: InteractiveExecutionLease,
        sessionAllowedInteractionClasses: Set<SurfaceInteractionClass>
    ) throws {
        try validateShape()
        let expectedSurfaceRevision: SurfaceRevision
        let expectedCoordinateRevision: CoordinateRevision
        do {
            expectedSurfaceRevision = try current.surfaceRevision.advanced()
            expectedCoordinateRevision = try current.coordinateRevision.advanced()
        } catch {
            throw InteractiveRuntimeMessageErrorV0
                .invalidSurfaceTransition
        }
        guard previousLeaseID == current.leaseID,
              replacement.leaseID != current.leaseID,
              replacement.hostID == current.hostID,
              replacement.deviceID == current.deviceID,
              replacement.interactiveSessionID
                == current.interactiveSessionID,
              replacement.authorizationEpoch == current.authorizationEpoch,
              (replacement.selectedDisplayID == current.selectedDisplayID
                || descriptor.kind == .desktop),
              replacement.surfaceRevision == expectedSurfaceRevision,
              replacement.coordinateRevision == expectedCoordinateRevision,
              current.renewalCounter
                < MonotonicRevision<AuthorizationEpochTag>
                    .maximumWireValue,
              replacement.renewalCounter == current.renewalCounter + 1,
              replacement.issuedAtMonotonicNanoseconds
                >= current.issuedAtMonotonicNanoseconds,
              replacement.issuedAtMonotonicNanoseconds
                < current.expiresAtMonotonicNanoseconds,
              Set(replacement.allowedInteractionClasses)
                .isSubset(of: sessionAllowedInteractionClasses) else {
            throw InteractiveRuntimeMessageErrorV0
                .invalidSurfaceTransition
        }
    }

    private func validateShape() throws {
        guard protocolVersion == .init() else {
            throw InteractiveRuntimeMessageErrorV0.invalidVersion
        }
        do {
            try descriptor.validate()
        } catch {
            throw InteractiveRuntimeMessageErrorV0
                .invalidSurfaceTransition
        }
        guard previousLeaseID != replacement.leaseID,
              replacement.interactiveSessionID
                == descriptor.interactiveSessionID,
              replacement.authorizationEpoch
                == descriptor.authorizationEpoch,
              replacement.surfaceID == descriptor.surfaceID,
              replacement.surfaceRevision.rawValue
                == descriptor.surfaceRevision.rawValue,
              replacement.coordinateRevision.rawValue
                == descriptor.coordinateSpaceRevision.rawValue,
              replacement.allowedInteractionClasses
                == descriptor.interactionClasses else {
            throw InteractiveRuntimeMessageErrorV0
                .invalidSurfaceTransition
        }
    }
}

public struct InteractiveRuntimeSurfaceTransitionReceiptV0:
    Codable,
    Equatable,
    Sendable
{
    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let previousLeaseID: UUID
    public let replacementLeaseID: UUID
    public let interactiveSessionID: UUID
    public let surfaceID: UUID
    public let surfaceRevision: SurfaceRevision
    public let coordinateRevision: CoordinateRevision
    public let mediaSequenceBeforeTransition: UInt64
    public let inputReleased: Bool
    public let captureSourcePrepared: Bool

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        previousLeaseID: UUID,
        replacementLeaseID: UUID,
        interactiveSessionID: UUID,
        surfaceID: UUID,
        surfaceRevision: SurfaceRevision,
        coordinateRevision: CoordinateRevision,
        mediaSequenceBeforeTransition: UInt64,
        inputReleased: Bool,
        captureSourcePrepared: Bool
    ) throws {
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.previousLeaseID = previousLeaseID
        self.replacementLeaseID = replacementLeaseID
        self.interactiveSessionID = interactiveSessionID
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.coordinateRevision = coordinateRevision
        self.mediaSequenceBeforeTransition = mediaSequenceBeforeTransition
        self.inputReleased = inputReleased
        self.captureSourcePrepared = captureSourcePrepared
        try validateShape()
    }

    public func validate(
        against command: InteractiveRuntimeSurfaceTransitionCommandV0
    ) throws {
        try validateShape()
        guard correlationID == command.commandID,
              previousLeaseID == command.previousLeaseID,
              replacementLeaseID == command.replacement.leaseID,
              interactiveSessionID
                == command.replacement.interactiveSessionID,
              surfaceID == command.replacement.surfaceID,
              surfaceRevision == command.replacement.surfaceRevision,
              coordinateRevision == command.replacement.coordinateRevision
        else {
            throw InteractiveRuntimeMessageErrorV0.bindingMismatch
        }
    }

    private func validateShape() throws {
        guard protocolVersion == .init() else {
            throw InteractiveRuntimeMessageErrorV0.invalidVersion
        }
        guard surfaceRevision.rawValue > 0,
              coordinateRevision.rawValue > 0,
              inputReleased,
              captureSourcePrepared else {
            throw InteractiveRuntimeMessageErrorV0
                .invalidSurfaceTransition
        }
    }
}

public struct InteractiveRuntimeSurfaceAcknowledgementCommandV0:
    Codable,
    Equatable,
    Sendable
{
    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let transitionCommandID: UUID
    public let leaseID: UUID
    public let interactiveSessionID: UUID
    public let surfaceID: UUID
    public let surfaceRevision: SurfaceRevision
    public let coordinateRevision: CoordinateRevision
    public let focusToken: UUID?
    public let focusRevision: CompanionInteractiveShared.FocusRevision?
    public let readyMediaSequence: UInt64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        transitionCommandID: UUID,
        leaseID: UUID,
        interactiveSessionID: UUID,
        surfaceID: UUID,
        surfaceRevision: SurfaceRevision,
        coordinateRevision: CoordinateRevision,
        focusToken: UUID? = nil,
        focusRevision: CompanionInteractiveShared.FocusRevision? = nil,
        readyMediaSequence: UInt64
    ) throws {
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.transitionCommandID = transitionCommandID
        self.leaseID = leaseID
        self.interactiveSessionID = interactiveSessionID
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.coordinateRevision = coordinateRevision
        self.focusToken = focusToken
        self.focusRevision = focusRevision
        self.readyMediaSequence = readyMediaSequence
        try validateShape()
    }

    public func validate(
        current: InteractiveExecutionLease,
        expectedTransitionCommandID: UUID,
        expectedReadyMediaSequence: UInt64,
        expectedFocusToken: UUID?,
        expectedFocusRevision: CompanionInteractiveShared.FocusRevision?
    ) throws {
        try validateShape()
        guard transitionCommandID == expectedTransitionCommandID,
              leaseID == current.leaseID,
              interactiveSessionID == current.interactiveSessionID,
              surfaceID == current.surfaceID,
              surfaceRevision == current.surfaceRevision,
              coordinateRevision == current.coordinateRevision,
              focusToken == expectedFocusToken,
              focusRevision == expectedFocusRevision,
              readyMediaSequence == expectedReadyMediaSequence else {
            throw InteractiveRuntimeMessageErrorV0
                .invalidSurfaceAcknowledgement
        }
    }

    private func validateShape() throws {
        guard protocolVersion == .init() else {
            throw InteractiveRuntimeMessageErrorV0.invalidVersion
        }
        guard surfaceRevision.rawValue > 0,
              coordinateRevision.rawValue > 0,
              (focusToken == nil) == (focusRevision == nil),
              focusRevision?.rawValue ?? 1 > 0,
              readyMediaSequence > 0 else {
            throw InteractiveRuntimeMessageErrorV0
                .invalidSurfaceAcknowledgement
        }
    }
}

public struct InteractiveRuntimeSurfaceAcknowledgementReceiptV0:
    Codable,
    Equatable,
    Sendable
{
    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let transitionCommandID: UUID
    public let leaseID: UUID
    public let interactiveSessionID: UUID
    public let surfaceID: UUID
    public let surfaceRevision: SurfaceRevision
    public let coordinateRevision: CoordinateRevision
    public let focusToken: UUID?
    public let focusRevision: CompanionInteractiveShared.FocusRevision?
    public let readyMediaSequence: UInt64
    public let inputResumed: Bool

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        transitionCommandID: UUID,
        leaseID: UUID,
        interactiveSessionID: UUID,
        surfaceID: UUID,
        surfaceRevision: SurfaceRevision,
        coordinateRevision: CoordinateRevision,
        focusToken: UUID? = nil,
        focusRevision: CompanionInteractiveShared.FocusRevision? = nil,
        readyMediaSequence: UInt64,
        inputResumed: Bool
    ) throws {
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.transitionCommandID = transitionCommandID
        self.leaseID = leaseID
        self.interactiveSessionID = interactiveSessionID
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.coordinateRevision = coordinateRevision
        self.focusToken = focusToken
        self.focusRevision = focusRevision
        self.readyMediaSequence = readyMediaSequence
        self.inputResumed = inputResumed
        try validateShape()
    }

    public func validate(
        against command: InteractiveRuntimeSurfaceAcknowledgementCommandV0
    ) throws {
        try validateShape()
        guard correlationID == command.commandID,
              transitionCommandID == command.transitionCommandID,
              leaseID == command.leaseID,
              interactiveSessionID == command.interactiveSessionID,
              surfaceID == command.surfaceID,
              surfaceRevision == command.surfaceRevision,
              coordinateRevision == command.coordinateRevision,
              focusToken == command.focusToken,
              focusRevision == command.focusRevision,
              readyMediaSequence == command.readyMediaSequence else {
            throw InteractiveRuntimeMessageErrorV0.bindingMismatch
        }
    }

    private func validateShape() throws {
        guard protocolVersion == .init() else {
            throw InteractiveRuntimeMessageErrorV0.invalidVersion
        }
        guard surfaceRevision.rawValue > 0,
              coordinateRevision.rawValue > 0,
              (focusToken == nil) == (focusRevision == nil),
              focusRevision?.rawValue ?? 1 > 0,
              readyMediaSequence > 0,
              inputResumed else {
            throw InteractiveRuntimeMessageErrorV0
                .invalidSurfaceAcknowledgement
        }
    }
}

public struct InteractiveRuntimeRevokeCommandV0: Codable, Equatable, Sendable {
    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let leaseID: UUID
    public let interactiveSessionID: UUID
    public let reason: InteractiveSessionEndReason

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        leaseID: UUID,
        interactiveSessionID: UUID,
        reason: InteractiveSessionEndReason
    ) throws {
        guard protocolVersion == .init() else {
            throw InteractiveRuntimeMessageErrorV0.invalidVersion
        }
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.leaseID = leaseID
        self.interactiveSessionID = interactiveSessionID
        self.reason = reason
    }
}

public struct InteractiveRuntimeRevokedReceiptV0: Codable, Equatable, Sendable {
    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let leaseID: UUID
    public let interactiveSessionID: UUID
    public let inputReleased: Bool
    public let captureStopped: Bool
    public let lastFrameBlanked: Bool
    public let indicatorCleared: Bool

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        leaseID: UUID,
        interactiveSessionID: UUID,
        inputReleased: Bool,
        captureStopped: Bool,
        lastFrameBlanked: Bool,
        indicatorCleared: Bool
    ) throws {
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.leaseID = leaseID
        self.interactiveSessionID = interactiveSessionID
        self.inputReleased = inputReleased
        self.captureStopped = captureStopped
        self.lastFrameBlanked = lastFrameBlanked
        self.indicatorCleared = indicatorCleared
        try validateShape()
    }

    public func validate(against command: InteractiveRuntimeRevokeCommandV0) throws {
        try validateShape()
        guard correlationID == command.commandID,
              leaseID == command.leaseID,
              interactiveSessionID == command.interactiveSessionID else {
            throw InteractiveRuntimeMessageErrorV0.bindingMismatch
        }
    }

    private func validateShape() throws {
        guard protocolVersion == .init() else {
            throw InteractiveRuntimeMessageErrorV0.invalidVersion
        }
        guard inputReleased, captureStopped, lastFrameBlanked,
              indicatorCleared else {
            throw InteractiveRuntimeMessageErrorV0.teardownIncomplete
        }
    }
}
