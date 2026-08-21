import CompanionDomain
import CompanionInteractiveShared
import CompanionWire
import Foundation

public enum InteractiveInitialSurfaceMessageErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidSequence
    case invalidInitialDescriptor
    case bindingMismatch
    case inputNotResumed
}

public struct InteractiveInitialSurfaceRequestBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey {
        case interactiveSessionID, authorizationEpoch, sequence
    }

    public static let kind = WireMessageKind.interactiveInitialSurfaceRequest
    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let sequence: Int64

    public init(
        interactiveSessionID: WireUUID,
        authorizationEpoch: AuthorizationEpoch,
        sequence: Int64
    ) throws {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.sequence = sequence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            ["interactiveSessionID", "authorizationEpoch", "sequence"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interactiveSessionID = try container.decode(
            WireUUID.self,
            forKey: .interactiveSessionID
        )
        authorizationEpoch = try container.decode(
            AuthorizationEpoch.self,
            forKey: .authorizationEpoch
        )
        sequence = try container.decode(Int64.self, forKey: .sequence)
        try validate()
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1,
              sequence >= 1,
              sequence <= WireLimits.maximumSafeInteger else {
            throw InteractiveInitialSurfaceMessageErrorV0.invalidSequence
        }
    }
}

public struct InteractiveInitialSurfaceDescriptorBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey {
        case activationID, descriptor, mediaSequenceBeforeActivation, sequence
    }

    public static let kind = WireMessageKind.interactiveInitialSurfaceDescriptor
    public let activationID: WireUUID
    public let descriptor: InteractiveSurfaceWireDescriptorV0
    public let mediaSequenceBeforeActivation: Int64
    public let sequence: Int64

    public init(
        activationID: WireUUID,
        descriptor: InteractiveSurfaceWireDescriptorV0,
        mediaSequenceBeforeActivation: Int64 = 0,
        sequence: Int64
    ) throws {
        self.activationID = activationID
        self.descriptor = descriptor
        self.mediaSequenceBeforeActivation = mediaSequenceBeforeActivation
        self.sequence = sequence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "activationID", "descriptor",
                "mediaSequenceBeforeActivation", "sequence",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activationID = try container.decode(WireUUID.self, forKey: .activationID)
        descriptor = try container.decode(
            InteractiveSurfaceWireDescriptorV0.self,
            forKey: .descriptor
        )
        mediaSequenceBeforeActivation = try container.decode(
            Int64.self,
            forKey: .mediaSequenceBeforeActivation
        )
        sequence = try container.decode(Int64.self, forKey: .sequence)
        try validate()
    }

    public func validate() throws {
        try descriptor.validate()
        guard descriptor.kind == .desktop,
              descriptor.surfaceRevision.rawValue == 1,
              descriptor.coordinateSpaceRevision.rawValue == 1,
              descriptor.applicationToken == nil,
              descriptor.windowToken == nil,
              descriptor.focus == nil,
              descriptor.metadataFields.isEmpty,
              descriptor.privacyProfile == .visualOnly,
              mediaSequenceBeforeActivation == 0,
              sequence >= 1,
              sequence <= WireLimits.maximumSafeInteger else {
            throw InteractiveInitialSurfaceMessageErrorV0
                .invalidInitialDescriptor
        }
    }
}

public struct InteractiveInitialSurfaceAcknowledgementBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey {
        case interactiveSessionID, authorizationEpoch, activationID, surfaceID
        case surfaceRevision, coordinateSpaceRevision, readyMediaSequence, sequence
    }

    public static let kind = WireMessageKind
        .interactiveInitialSurfaceAcknowledgement
    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let activationID: WireUUID
    public let surfaceID: WireUUID
    public let surfaceRevision: SurfaceRevision
    public let coordinateSpaceRevision: CoordinateSpaceRevision
    public let readyMediaSequence: Int64
    public let sequence: Int64

    public init(
        interactiveSessionID: WireUUID,
        authorizationEpoch: AuthorizationEpoch,
        activationID: WireUUID,
        surfaceID: WireUUID,
        surfaceRevision: SurfaceRevision,
        coordinateSpaceRevision: CoordinateSpaceRevision,
        readyMediaSequence: Int64,
        sequence: Int64
    ) throws {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.activationID = activationID
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.coordinateSpaceRevision = coordinateSpaceRevision
        self.readyMediaSequence = readyMediaSequence
        self.sequence = sequence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "interactiveSessionID", "authorizationEpoch", "activationID",
                "surfaceID", "surfaceRevision", "coordinateSpaceRevision",
                "readyMediaSequence", "sequence",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interactiveSessionID = try container.decode(
            WireUUID.self,
            forKey: .interactiveSessionID
        )
        authorizationEpoch = try container.decode(
            AuthorizationEpoch.self,
            forKey: .authorizationEpoch
        )
        activationID = try container.decode(WireUUID.self, forKey: .activationID)
        surfaceID = try container.decode(WireUUID.self, forKey: .surfaceID)
        surfaceRevision = try container.decode(
            SurfaceRevision.self,
            forKey: .surfaceRevision
        )
        coordinateSpaceRevision = try container.decode(
            CoordinateSpaceRevision.self,
            forKey: .coordinateSpaceRevision
        )
        readyMediaSequence = try container.decode(
            Int64.self,
            forKey: .readyMediaSequence
        )
        sequence = try container.decode(Int64.self, forKey: .sequence)
        try validate()
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1,
              surfaceRevision.rawValue == 1,
              coordinateSpaceRevision.rawValue == 1,
              readyMediaSequence >= 1,
              readyMediaSequence <= WireLimits.maximumSafeInteger,
              sequence >= 1,
              sequence <= WireLimits.maximumSafeInteger else {
            throw InteractiveInitialSurfaceMessageErrorV0.bindingMismatch
        }
    }

    public func fence() -> SurfaceInputFence {
        SurfaceInputFence(
            interactiveSessionID: interactiveSessionID.rawValue,
            authorizationEpoch: authorizationEpoch,
            surfaceID: surfaceID.rawValue,
            surfaceRevision: surfaceRevision,
            coordinateSpaceRevision: coordinateSpaceRevision
        )
    }
}

public struct InteractiveInitialSurfaceAcknowledgedBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey {
        case interactiveSessionID, authorizationEpoch, activationID, surfaceID
        case surfaceRevision, coordinateSpaceRevision, readyMediaSequence
        case inputResumed, sequence
    }

    public static let kind = WireMessageKind
        .interactiveInitialSurfaceAcknowledged
    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let activationID: WireUUID
    public let surfaceID: WireUUID
    public let surfaceRevision: SurfaceRevision
    public let coordinateSpaceRevision: CoordinateSpaceRevision
    public let readyMediaSequence: Int64
    public let inputResumed: Bool
    public let sequence: Int64

    public init(
        acknowledgement: InteractiveInitialSurfaceAcknowledgementBodyV0,
        inputResumed: Bool,
        sequence: Int64
    ) throws {
        interactiveSessionID = acknowledgement.interactiveSessionID
        authorizationEpoch = acknowledgement.authorizationEpoch
        activationID = acknowledgement.activationID
        surfaceID = acknowledgement.surfaceID
        surfaceRevision = acknowledgement.surfaceRevision
        coordinateSpaceRevision = acknowledgement.coordinateSpaceRevision
        readyMediaSequence = acknowledgement.readyMediaSequence
        self.inputResumed = inputResumed
        self.sequence = sequence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "interactiveSessionID", "authorizationEpoch", "activationID",
                "surfaceID", "surfaceRevision", "coordinateSpaceRevision",
                "readyMediaSequence", "inputResumed", "sequence",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interactiveSessionID = try container.decode(WireUUID.self, forKey: .interactiveSessionID)
        authorizationEpoch = try container.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch)
        activationID = try container.decode(WireUUID.self, forKey: .activationID)
        surfaceID = try container.decode(WireUUID.self, forKey: .surfaceID)
        surfaceRevision = try container.decode(SurfaceRevision.self, forKey: .surfaceRevision)
        coordinateSpaceRevision = try container.decode(CoordinateSpaceRevision.self, forKey: .coordinateSpaceRevision)
        readyMediaSequence = try container.decode(Int64.self, forKey: .readyMediaSequence)
        inputResumed = try container.decode(Bool.self, forKey: .inputResumed)
        sequence = try container.decode(Int64.self, forKey: .sequence)
        try validate()
    }

    public func validate() throws {
        guard inputResumed,
              surfaceRevision.rawValue == 1,
              coordinateSpaceRevision.rawValue == 1,
              readyMediaSequence >= 1,
              readyMediaSequence <= WireLimits.maximumSafeInteger,
              sequence >= 1,
              sequence <= WireLimits.maximumSafeInteger else {
            throw InteractiveInitialSurfaceMessageErrorV0.inputNotResumed
        }
    }

    public func validate(
        against acknowledgement:
            InteractiveInitialSurfaceAcknowledgementBodyV0
    ) throws {
        try validate()
        guard interactiveSessionID == acknowledgement.interactiveSessionID,
              authorizationEpoch == acknowledgement.authorizationEpoch,
              activationID == acknowledgement.activationID,
              surfaceID == acknowledgement.surfaceID,
              surfaceRevision == acknowledgement.surfaceRevision,
              coordinateSpaceRevision
                == acknowledgement.coordinateSpaceRevision,
              readyMediaSequence == acknowledgement.readyMediaSequence else {
            throw InteractiveInitialSurfaceMessageErrorV0.bindingMismatch
        }
    }
}
