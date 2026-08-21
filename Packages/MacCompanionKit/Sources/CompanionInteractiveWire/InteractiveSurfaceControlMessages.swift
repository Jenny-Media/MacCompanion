import CompanionDomain
import CompanionInteractiveShared
import CompanionWire
import Foundation

public enum InteractiveSurfaceWireErrorV0: Error, Equatable, Sendable {
    case invalidDescriptor
    case invalidSelection
    case invalidAcknowledgement
    case bindingMismatch
    case invalidTime
}

public struct InteractiveSurfaceWireRectV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case x, y, width, height
    }

    public let x: UInt16
    public let y: UInt16
    public let width: UInt16
    public let height: UInt16

    public init(_ value: NormalizedSurfaceRect) {
        x = value.x
        y = value.y
        width = value.width
        height = value.height
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["x", "y", "width", "height"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(UInt16.self, forKey: .x)
        y = try container.decode(UInt16.self, forKey: .y)
        width = try container.decode(UInt16.self, forKey: .width)
        height = try container.decode(UInt16.self, forKey: .height)
        _ = try materialize()
    }

    public func materialize() throws -> NormalizedSurfaceRect {
        do {
            return try NormalizedSurfaceRect(
                x: x,
                y: y,
                width: width,
                height: height
            )
        } catch {
            throw InteractiveSurfaceWireErrorV0.invalidDescriptor
        }
    }
}

public struct InteractiveSurfaceWireFocusV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case token, revision, category, bounds, editable, secure
    }

    public let token: WireUUID
    public let revision: FocusRevision
    public let category: FocusElementCategory
    public let bounds: InteractiveSurfaceWireRectV0
    public let editable: Bool
    public let secure: Bool

    public init(_ value: SurfaceFocus) {
        token = WireUUID(value.token)
        revision = value.revision
        category = value.category
        bounds = InteractiveSurfaceWireRectV0(value.bounds)
        editable = value.editable
        secure = value.secure
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            ["token", "revision", "category", "bounds", "editable", "secure"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(WireUUID.self, forKey: .token)
        revision = try container.decode(FocusRevision.self, forKey: .revision)
        category = try container.decode(FocusElementCategory.self, forKey: .category)
        bounds = try container.decode(InteractiveSurfaceWireRectV0.self, forKey: .bounds)
        editable = try container.decode(Bool.self, forKey: .editable)
        secure = try container.decode(Bool.self, forKey: .secure)
        _ = try materialize()
    }

    public func materialize() throws -> SurfaceFocus {
        guard revision.rawValue <= UInt64(WireLimits.maximumSafeInteger) else {
            throw InteractiveSurfaceWireErrorV0.invalidDescriptor
        }
        do {
            return try SurfaceFocus(
                token: token.rawValue,
                revision: revision,
                category: category,
                bounds: bounds.materialize(),
                editable: editable,
                secure: secure
            )
        } catch {
            throw InteractiveSurfaceWireErrorV0.invalidDescriptor
        }
    }
}

public struct InteractiveSurfaceWireDescriptorV0: Codable, Equatable, Sendable {
    public static let maximumValidityMilliseconds: Int64 = 10_000

    private enum CodingKeys: String, CodingKey {
        case interactiveSessionID, authorizationEpoch, surfaceID, kind
        case surfaceRevision, coordinateSpaceRevision
        case applicationToken, windowToken, parentSurfaceID, fallbackSurfaceID
        case encodedWidth, encodedHeight, logicalWidthPoints, logicalHeightPoints
        case rotation, interactionClasses, privacyProfile, metadataFields, focus
        case validForMilliseconds
    }

    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let surfaceID: WireUUID
    public let kind: InteractiveSurfaceKind
    public let surfaceRevision: CompanionInteractiveShared.SurfaceRevision
    public let coordinateSpaceRevision: CoordinateSpaceRevision
    public let applicationToken: WireUUID?
    public let windowToken: WireUUID?
    public let parentSurfaceID: WireUUID?
    public let fallbackSurfaceID: WireUUID?
    public let encodedWidth: UInt16
    public let encodedHeight: UInt16
    public let logicalWidthPoints: UInt32
    public let logicalHeightPoints: UInt32
    public let rotation: SurfaceRotation
    public let interactionClasses: [SurfaceInteractionClass]
    public let privacyProfile: SurfacePrivacyProfile
    public let metadataFields: [SurfaceMetadataField]
    public let focus: InteractiveSurfaceWireFocusV0?
    public let validForMilliseconds: Int64

    public init(
        descriptor: AdaptiveSurfaceDescriptor,
        validForMilliseconds: Int64
    ) throws {
        try descriptor.validate()
        interactiveSessionID = WireUUID(descriptor.interactiveSessionID)
        authorizationEpoch = descriptor.authorizationEpoch
        surfaceID = WireUUID(descriptor.surfaceID)
        kind = descriptor.kind
        surfaceRevision = descriptor.surfaceRevision
        coordinateSpaceRevision = descriptor.coordinateSpaceRevision
        applicationToken = descriptor.applicationToken.map(WireUUID.init)
        windowToken = descriptor.windowToken.map(WireUUID.init)
        parentSurfaceID = descriptor.parentSurfaceID.map(WireUUID.init)
        fallbackSurfaceID = descriptor.fallbackSurfaceID.map(WireUUID.init)
        encodedWidth = descriptor.encodedWidth
        encodedHeight = descriptor.encodedHeight
        logicalWidthPoints = descriptor.logicalWidthPoints
        logicalHeightPoints = descriptor.logicalHeightPoints
        rotation = descriptor.rotation
        interactionClasses = descriptor.interactionClasses
        privacyProfile = descriptor.privacyProfile
        metadataFields = descriptor.metadataFields
        focus = descriptor.focus.map(InteractiveSurfaceWireFocusV0.init)
        self.validForMilliseconds = validForMilliseconds
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [
            "interactiveSessionID", "authorizationEpoch", "surfaceID", "kind",
            "surfaceRevision", "coordinateSpaceRevision", "applicationToken",
            "windowToken", "parentSurfaceID", "fallbackSurfaceID", "encodedWidth",
            "encodedHeight", "logicalWidthPoints", "logicalHeightPoints", "rotation",
            "interactionClasses", "privacyProfile", "metadataFields", "focus",
            "validForMilliseconds",
        ])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interactiveSessionID = try container.decode(WireUUID.self, forKey: .interactiveSessionID)
        authorizationEpoch = try container.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch)
        surfaceID = try container.decode(WireUUID.self, forKey: .surfaceID)
        kind = try container.decode(InteractiveSurfaceKind.self, forKey: .kind)
        surfaceRevision = try container.decode(
            CompanionInteractiveShared.SurfaceRevision.self,
            forKey: .surfaceRevision
        )
        coordinateSpaceRevision = try container.decode(
            CoordinateSpaceRevision.self,
            forKey: .coordinateSpaceRevision
        )
        applicationToken = try container.decodeIfPresent(WireUUID.self, forKey: .applicationToken)
        windowToken = try container.decodeIfPresent(WireUUID.self, forKey: .windowToken)
        parentSurfaceID = try container.decodeIfPresent(WireUUID.self, forKey: .parentSurfaceID)
        fallbackSurfaceID = try container.decodeIfPresent(WireUUID.self, forKey: .fallbackSurfaceID)
        encodedWidth = try container.decode(UInt16.self, forKey: .encodedWidth)
        encodedHeight = try container.decode(UInt16.self, forKey: .encodedHeight)
        logicalWidthPoints = try container.decode(UInt32.self, forKey: .logicalWidthPoints)
        logicalHeightPoints = try container.decode(UInt32.self, forKey: .logicalHeightPoints)
        rotation = try container.decode(SurfaceRotation.self, forKey: .rotation)
        interactionClasses = try container.decode(
            [SurfaceInteractionClass].self,
            forKey: .interactionClasses
        )
        privacyProfile = try container.decode(SurfacePrivacyProfile.self, forKey: .privacyProfile)
        metadataFields = try container.decode([SurfaceMetadataField].self, forKey: .metadataFields)
        focus = try container.decodeIfPresent(InteractiveSurfaceWireFocusV0.self, forKey: .focus)
        validForMilliseconds = try container.decode(Int64.self, forKey: .validForMilliseconds)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(interactiveSessionID, forKey: .interactiveSessionID)
        try container.encode(authorizationEpoch, forKey: .authorizationEpoch)
        try container.encode(surfaceID, forKey: .surfaceID)
        try container.encode(kind, forKey: .kind)
        try container.encode(surfaceRevision, forKey: .surfaceRevision)
        try container.encode(coordinateSpaceRevision, forKey: .coordinateSpaceRevision)
        try container.encode(applicationToken, forKey: .applicationToken)
        try container.encode(windowToken, forKey: .windowToken)
        try container.encode(parentSurfaceID, forKey: .parentSurfaceID)
        try container.encode(fallbackSurfaceID, forKey: .fallbackSurfaceID)
        try container.encode(encodedWidth, forKey: .encodedWidth)
        try container.encode(encodedHeight, forKey: .encodedHeight)
        try container.encode(logicalWidthPoints, forKey: .logicalWidthPoints)
        try container.encode(logicalHeightPoints, forKey: .logicalHeightPoints)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(interactionClasses, forKey: .interactionClasses)
        try container.encode(privacyProfile, forKey: .privacyProfile)
        try container.encode(metadataFields, forKey: .metadataFields)
        try container.encode(focus, forKey: .focus)
        try container.encode(validForMilliseconds, forKey: .validForMilliseconds)
    }

    public func materialize(
        clientMonotonicNowMilliseconds: Int64
    ) throws -> AdaptiveSurfaceDescriptor {
        guard clientMonotonicNowMilliseconds >= 0,
              validForMilliseconds >= 1,
              validForMilliseconds <= Self.maximumValidityMilliseconds,
              clientMonotonicNowMilliseconds
                <= WireLimits.maximumSafeInteger - validForMilliseconds,
              authorizationEpoch.rawValue <= UInt64(WireLimits.maximumSafeInteger),
              surfaceRevision.rawValue <= UInt64(WireLimits.maximumSafeInteger),
              coordinateSpaceRevision.rawValue <= UInt64(WireLimits.maximumSafeInteger),
              interactionClasses == interactionClasses.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(interactionClasses).count == interactionClasses.count,
              metadataFields == metadataFields.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(metadataFields).count == metadataFields.count else {
            throw InteractiveSurfaceWireErrorV0.invalidDescriptor
        }
        do {
            return try AdaptiveSurfaceDescriptor(
                interactiveSessionID: interactiveSessionID.rawValue,
                authorizationEpoch: authorizationEpoch,
                surfaceID: surfaceID.rawValue,
                kind: kind,
                surfaceRevision: surfaceRevision,
                coordinateSpaceRevision: coordinateSpaceRevision,
                applicationToken: applicationToken?.rawValue,
                windowToken: windowToken?.rawValue,
                parentSurfaceID: parentSurfaceID?.rawValue,
                fallbackSurfaceID: fallbackSurfaceID?.rawValue,
                encodedWidth: encodedWidth,
                encodedHeight: encodedHeight,
                logicalWidthPoints: logicalWidthPoints,
                logicalHeightPoints: logicalHeightPoints,
                rotation: rotation,
                interactionClasses: Set(interactionClasses),
                privacyProfile: privacyProfile,
                metadataFields: Set(metadataFields),
                focus: try focus?.materialize(),
                createdAtMonotonicMilliseconds: clientMonotonicNowMilliseconds,
                expiresAtMonotonicMilliseconds:
                    clientMonotonicNowMilliseconds + validForMilliseconds
            )
        } catch let error as InteractiveSurfaceWireErrorV0 {
            throw error
        } catch {
            throw InteractiveSurfaceWireErrorV0.invalidDescriptor
        }
    }

    public func validate() throws {
        _ = try materialize(clientMonotonicNowMilliseconds: 0)
    }
}

public struct InteractiveSurfaceSelectBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey {
        case interactiveSessionID, authorizationEpoch, currentSurfaceID
        case expectedSurfaceRevision, expectedCoordinateSpaceRevision
        case targetKind, targetToken, sequence
    }

    public static let kind = WireMessageKind.interactiveSurfaceSelect
    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let currentSurfaceID: WireUUID
    public let expectedSurfaceRevision: CompanionInteractiveShared.SurfaceRevision
    public let expectedCoordinateSpaceRevision: CoordinateSpaceRevision
    public let targetKind: InteractiveSurfaceKind
    public let targetToken: WireUUID?
    public let sequence: Int64

    public init(
        interactiveSessionID: WireUUID,
        authorizationEpoch: AuthorizationEpoch,
        currentSurfaceID: WireUUID,
        expectedSurfaceRevision: CompanionInteractiveShared.SurfaceRevision,
        expectedCoordinateSpaceRevision: CoordinateSpaceRevision,
        targetKind: InteractiveSurfaceKind,
        targetToken: WireUUID?,
        sequence: Int64
    ) throws {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.currentSurfaceID = currentSurfaceID
        self.expectedSurfaceRevision = expectedSurfaceRevision
        self.expectedCoordinateSpaceRevision = expectedCoordinateSpaceRevision
        self.targetKind = targetKind
        self.targetToken = targetToken
        self.sequence = sequence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [
            "interactiveSessionID", "authorizationEpoch", "currentSurfaceID",
            "expectedSurfaceRevision", "expectedCoordinateSpaceRevision",
            "targetKind", "targetToken", "sequence",
        ])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interactiveSessionID = try container.decode(WireUUID.self, forKey: .interactiveSessionID)
        authorizationEpoch = try container.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch)
        currentSurfaceID = try container.decode(WireUUID.self, forKey: .currentSurfaceID)
        expectedSurfaceRevision = try container.decode(
            CompanionInteractiveShared.SurfaceRevision.self,
            forKey: .expectedSurfaceRevision
        )
        expectedCoordinateSpaceRevision = try container.decode(
            CoordinateSpaceRevision.self,
            forKey: .expectedCoordinateSpaceRevision
        )
        targetKind = try container.decode(InteractiveSurfaceKind.self, forKey: .targetKind)
        targetToken = try container.decodeIfPresent(WireUUID.self, forKey: .targetToken)
        sequence = try container.decode(Int64.self, forKey: .sequence)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(interactiveSessionID, forKey: .interactiveSessionID)
        try container.encode(authorizationEpoch, forKey: .authorizationEpoch)
        try container.encode(currentSurfaceID, forKey: .currentSurfaceID)
        try container.encode(expectedSurfaceRevision, forKey: .expectedSurfaceRevision)
        try container.encode(expectedCoordinateSpaceRevision, forKey: .expectedCoordinateSpaceRevision)
        try container.encode(targetKind, forKey: .targetKind)
        try container.encode(targetToken, forKey: .targetToken)
        try container.encode(sequence, forKey: .sequence)
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1,
              authorizationEpoch.rawValue <= UInt64(WireLimits.maximumSafeInteger),
              expectedSurfaceRevision.rawValue >= 1,
              expectedSurfaceRevision.rawValue <= UInt64(WireLimits.maximumSafeInteger),
              expectedCoordinateSpaceRevision.rawValue >= 1,
              expectedCoordinateSpaceRevision.rawValue <= UInt64(WireLimits.maximumSafeInteger),
              sequence >= 1, sequence <= WireLimits.maximumSafeInteger,
              (targetKind == .desktop) == (targetToken == nil) else {
            throw InteractiveSurfaceWireErrorV0.invalidSelection
        }
    }
}

public struct InteractiveSurfaceSelectedBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey {
        case transitionID, descriptor, mediaSequenceBeforeTransition, sequence
    }

    public static let kind = WireMessageKind.interactiveSurfaceSelected
    public let transitionID: WireUUID
    public let descriptor: InteractiveSurfaceWireDescriptorV0
    public let mediaSequenceBeforeTransition: Int64
    public let sequence: Int64

    public init(
        transitionID: WireUUID,
        descriptor: InteractiveSurfaceWireDescriptorV0,
        mediaSequenceBeforeTransition: Int64,
        sequence: Int64
    ) throws {
        self.transitionID = transitionID
        self.descriptor = descriptor
        self.mediaSequenceBeforeTransition = mediaSequenceBeforeTransition
        self.sequence = sequence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            ["transitionID", "descriptor", "mediaSequenceBeforeTransition", "sequence"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transitionID = try container.decode(WireUUID.self, forKey: .transitionID)
        descriptor = try container.decode(InteractiveSurfaceWireDescriptorV0.self, forKey: .descriptor)
        mediaSequenceBeforeTransition = try container.decode(
            Int64.self,
            forKey: .mediaSequenceBeforeTransition
        )
        sequence = try container.decode(Int64.self, forKey: .sequence)
        try validate()
    }

    public func validate() throws {
        try descriptor.validate()
        guard mediaSequenceBeforeTransition >= 0,
              mediaSequenceBeforeTransition <= WireLimits.maximumSafeInteger,
              sequence >= 1, sequence <= WireLimits.maximumSafeInteger else {
            throw InteractiveSurfaceWireErrorV0.invalidSelection
        }
    }
}

public struct InteractiveSurfaceAcknowledgementBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey {
        case interactiveSessionID, authorizationEpoch, transitionID, surfaceID
        case surfaceRevision, coordinateSpaceRevision, focusToken, focusRevision
        case readyMediaSequence, sequence
    }

    public static let kind = WireMessageKind.interactiveSurfaceAcknowledgement
    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let transitionID: WireUUID
    public let surfaceID: WireUUID
    public let surfaceRevision: CompanionInteractiveShared.SurfaceRevision
    public let coordinateSpaceRevision: CoordinateSpaceRevision
    public let focusToken: WireUUID?
    public let focusRevision: FocusRevision?
    public let readyMediaSequence: Int64
    public let sequence: Int64

    public init(
        interactiveSessionID: WireUUID,
        authorizationEpoch: AuthorizationEpoch,
        transitionID: WireUUID,
        surfaceID: WireUUID,
        surfaceRevision: CompanionInteractiveShared.SurfaceRevision,
        coordinateSpaceRevision: CoordinateSpaceRevision,
        focusToken: WireUUID? = nil,
        focusRevision: FocusRevision? = nil,
        readyMediaSequence: Int64,
        sequence: Int64
    ) throws {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.transitionID = transitionID
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.coordinateSpaceRevision = coordinateSpaceRevision
        self.focusToken = focusToken
        self.focusRevision = focusRevision
        self.readyMediaSequence = readyMediaSequence
        self.sequence = sequence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [
            "interactiveSessionID", "authorizationEpoch", "transitionID", "surfaceID",
            "surfaceRevision", "coordinateSpaceRevision", "focusToken", "focusRevision",
            "readyMediaSequence", "sequence",
        ])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interactiveSessionID = try container.decode(WireUUID.self, forKey: .interactiveSessionID)
        authorizationEpoch = try container.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch)
        transitionID = try container.decode(WireUUID.self, forKey: .transitionID)
        surfaceID = try container.decode(WireUUID.self, forKey: .surfaceID)
        surfaceRevision = try container.decode(
            CompanionInteractiveShared.SurfaceRevision.self,
            forKey: .surfaceRevision
        )
        coordinateSpaceRevision = try container.decode(
            CoordinateSpaceRevision.self,
            forKey: .coordinateSpaceRevision
        )
        focusToken = try container.decodeIfPresent(WireUUID.self, forKey: .focusToken)
        focusRevision = try container.decodeIfPresent(FocusRevision.self, forKey: .focusRevision)
        readyMediaSequence = try container.decode(Int64.self, forKey: .readyMediaSequence)
        sequence = try container.decode(Int64.self, forKey: .sequence)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(interactiveSessionID, forKey: .interactiveSessionID)
        try container.encode(authorizationEpoch, forKey: .authorizationEpoch)
        try container.encode(transitionID, forKey: .transitionID)
        try container.encode(surfaceID, forKey: .surfaceID)
        try container.encode(surfaceRevision, forKey: .surfaceRevision)
        try container.encode(coordinateSpaceRevision, forKey: .coordinateSpaceRevision)
        try container.encode(focusToken, forKey: .focusToken)
        try container.encode(focusRevision, forKey: .focusRevision)
        try container.encode(readyMediaSequence, forKey: .readyMediaSequence)
        try container.encode(sequence, forKey: .sequence)
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1,
              authorizationEpoch.rawValue <= UInt64(WireLimits.maximumSafeInteger),
              surfaceRevision.rawValue >= 1,
              surfaceRevision.rawValue <= UInt64(WireLimits.maximumSafeInteger),
              coordinateSpaceRevision.rawValue >= 1,
              coordinateSpaceRevision.rawValue <= UInt64(WireLimits.maximumSafeInteger),
              (focusToken == nil) == (focusRevision == nil),
              (focusRevision?.rawValue ?? 1) >= 1,
              (focusRevision?.rawValue ?? 1)
                <= UInt64(WireLimits.maximumSafeInteger),
              readyMediaSequence >= 1,
              readyMediaSequence <= WireLimits.maximumSafeInteger,
              sequence >= 1, sequence <= WireLimits.maximumSafeInteger else {
            throw InteractiveSurfaceWireErrorV0.invalidAcknowledgement
        }
    }

    public func fence() -> SurfaceInputFence {
        SurfaceInputFence(
            interactiveSessionID: interactiveSessionID.rawValue,
            authorizationEpoch: authorizationEpoch,
            surfaceID: surfaceID.rawValue,
            surfaceRevision: surfaceRevision,
            coordinateSpaceRevision: coordinateSpaceRevision,
            focusToken: focusToken?.rawValue,
            focusRevision: focusRevision
        )
    }
}

public struct InteractiveSurfaceAcknowledgedBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey {
        case interactiveSessionID, authorizationEpoch, transitionID, surfaceID
        case surfaceRevision, coordinateSpaceRevision, focusToken, focusRevision
        case readyMediaSequence, inputResumed, sequence
    }

    public static let kind = WireMessageKind.interactiveSurfaceAcknowledged
    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let transitionID: WireUUID
    public let surfaceID: WireUUID
    public let surfaceRevision: CompanionInteractiveShared.SurfaceRevision
    public let coordinateSpaceRevision: CoordinateSpaceRevision
    public let focusToken: WireUUID?
    public let focusRevision: FocusRevision?
    public let readyMediaSequence: Int64
    public let inputResumed: Bool
    public let sequence: Int64

    public init(
        acknowledgement: InteractiveSurfaceAcknowledgementBodyV0,
        inputResumed: Bool,
        sequence: Int64
    ) throws {
        interactiveSessionID = acknowledgement.interactiveSessionID
        authorizationEpoch = acknowledgement.authorizationEpoch
        transitionID = acknowledgement.transitionID
        surfaceID = acknowledgement.surfaceID
        surfaceRevision = acknowledgement.surfaceRevision
        coordinateSpaceRevision = acknowledgement.coordinateSpaceRevision
        focusToken = acknowledgement.focusToken
        focusRevision = acknowledgement.focusRevision
        readyMediaSequence = acknowledgement.readyMediaSequence
        self.inputResumed = inputResumed
        self.sequence = sequence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [
            "interactiveSessionID", "authorizationEpoch", "transitionID", "surfaceID",
            "surfaceRevision", "coordinateSpaceRevision", "focusToken", "focusRevision",
            "readyMediaSequence", "inputResumed", "sequence",
        ])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interactiveSessionID = try container.decode(WireUUID.self, forKey: .interactiveSessionID)
        authorizationEpoch = try container.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch)
        transitionID = try container.decode(WireUUID.self, forKey: .transitionID)
        surfaceID = try container.decode(WireUUID.self, forKey: .surfaceID)
        surfaceRevision = try container.decode(
            CompanionInteractiveShared.SurfaceRevision.self,
            forKey: .surfaceRevision
        )
        coordinateSpaceRevision = try container.decode(
            CoordinateSpaceRevision.self,
            forKey: .coordinateSpaceRevision
        )
        focusToken = try container.decodeIfPresent(WireUUID.self, forKey: .focusToken)
        focusRevision = try container.decodeIfPresent(FocusRevision.self, forKey: .focusRevision)
        readyMediaSequence = try container.decode(Int64.self, forKey: .readyMediaSequence)
        inputResumed = try container.decode(Bool.self, forKey: .inputResumed)
        sequence = try container.decode(Int64.self, forKey: .sequence)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(interactiveSessionID, forKey: .interactiveSessionID)
        try container.encode(authorizationEpoch, forKey: .authorizationEpoch)
        try container.encode(transitionID, forKey: .transitionID)
        try container.encode(surfaceID, forKey: .surfaceID)
        try container.encode(surfaceRevision, forKey: .surfaceRevision)
        try container.encode(coordinateSpaceRevision, forKey: .coordinateSpaceRevision)
        try container.encode(focusToken, forKey: .focusToken)
        try container.encode(focusRevision, forKey: .focusRevision)
        try container.encode(readyMediaSequence, forKey: .readyMediaSequence)
        try container.encode(inputResumed, forKey: .inputResumed)
        try container.encode(sequence, forKey: .sequence)
    }

    public func validate() throws {
        let request = try InteractiveSurfaceAcknowledgementBodyV0(
            interactiveSessionID: interactiveSessionID,
            authorizationEpoch: authorizationEpoch,
            transitionID: transitionID,
            surfaceID: surfaceID,
            surfaceRevision: surfaceRevision,
            coordinateSpaceRevision: coordinateSpaceRevision,
            focusToken: focusToken,
            focusRevision: focusRevision,
            readyMediaSequence: readyMediaSequence,
            sequence: 1
        )
        try request.validate()
        guard inputResumed,
              sequence >= 1, sequence <= WireLimits.maximumSafeInteger else {
            throw InteractiveSurfaceWireErrorV0.invalidAcknowledgement
        }
    }

    public func validate(
        against acknowledgement: InteractiveSurfaceAcknowledgementBodyV0
    ) throws {
        try validate()
        guard interactiveSessionID == acknowledgement.interactiveSessionID,
              authorizationEpoch == acknowledgement.authorizationEpoch,
              transitionID == acknowledgement.transitionID,
              surfaceID == acknowledgement.surfaceID,
              surfaceRevision == acknowledgement.surfaceRevision,
              coordinateSpaceRevision == acknowledgement.coordinateSpaceRevision,
              focusToken == acknowledgement.focusToken,
              focusRevision == acknowledgement.focusRevision,
              readyMediaSequence == acknowledgement.readyMediaSequence else {
            throw InteractiveSurfaceWireErrorV0.bindingMismatch
        }
    }
}
