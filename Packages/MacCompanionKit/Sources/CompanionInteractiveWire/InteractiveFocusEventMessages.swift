import CompanionDomain
import CompanionInteractiveShared
import CompanionWire
import Foundation

public enum InteractiveFocusEventWireErrorV0:
    Error, Equatable, Sendable
{
    case invalidEvent
    case invalidTime
}

public struct InteractiveSurfaceFocusChangedBodyV0: WireBody {
    public static let kind = WireMessageKind.interactiveSurfaceFocusChanged
    public static let maximumValidityMilliseconds: Int64 = 2_000

    private enum CodingKeys: String, CodingKey {
        case interactiveSessionID, authorizationEpoch, currentSurfaceID
        case currentSurfaceRevision, currentCoordinateSpaceRevision
        case recommendedTargetKind, targetToken, focus, inputPaused, reason
        case validForMilliseconds, eventSequence
    }

    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let currentSurfaceID: WireUUID
    public let currentSurfaceRevision: SurfaceRevision
    public let currentCoordinateSpaceRevision: CoordinateSpaceRevision
    public let recommendedTargetKind: InteractiveSurfaceKind
    public let targetToken: WireUUID?
    public let focus: InteractiveSurfaceWireFocusV0?
    public let inputPaused: Bool
    public let reason: InteractiveFocusEventReasonV0
    public let validForMilliseconds: Int64
    public let eventSequence: Int64

    public init(
        interactiveSessionID: WireUUID,
        authorizationEpoch: AuthorizationEpoch,
        currentSurfaceID: WireUUID,
        currentSurfaceRevision: SurfaceRevision,
        currentCoordinateSpaceRevision: CoordinateSpaceRevision,
        recommendedTargetKind: InteractiveSurfaceKind,
        targetToken: WireUUID?,
        focus: InteractiveSurfaceWireFocusV0?,
        inputPaused: Bool,
        reason: InteractiveFocusEventReasonV0,
        validForMilliseconds: Int64,
        eventSequence: Int64
    ) throws {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.currentSurfaceID = currentSurfaceID
        self.currentSurfaceRevision = currentSurfaceRevision
        self.currentCoordinateSpaceRevision =
            currentCoordinateSpaceRevision
        self.recommendedTargetKind = recommendedTargetKind
        self.targetToken = targetToken
        self.focus = focus
        self.inputPaused = inputPaused
        self.reason = reason
        self.validForMilliseconds = validForMilliseconds
        self.eventSequence = eventSequence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [
            "interactiveSessionID", "authorizationEpoch", "currentSurfaceID",
            "currentSurfaceRevision", "currentCoordinateSpaceRevision",
            "recommendedTargetKind", "targetToken", "focus", "inputPaused",
            "reason", "validForMilliseconds", "eventSequence",
        ])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interactiveSessionID = try container.decode(
            WireUUID.self,
            forKey: .interactiveSessionID
        )
        authorizationEpoch = try container.decode(
            AuthorizationEpoch.self,
            forKey: .authorizationEpoch
        )
        currentSurfaceID = try container.decode(
            WireUUID.self,
            forKey: .currentSurfaceID
        )
        currentSurfaceRevision = try container.decode(
            SurfaceRevision.self,
            forKey: .currentSurfaceRevision
        )
        currentCoordinateSpaceRevision = try container.decode(
            CoordinateSpaceRevision.self,
            forKey: .currentCoordinateSpaceRevision
        )
        recommendedTargetKind = try container.decode(
            InteractiveSurfaceKind.self,
            forKey: .recommendedTargetKind
        )
        targetToken = try container.decodeIfPresent(
            WireUUID.self,
            forKey: .targetToken
        )
        focus = try container.decodeIfPresent(
            InteractiveSurfaceWireFocusV0.self,
            forKey: .focus
        )
        inputPaused = try container.decode(
            Bool.self,
            forKey: .inputPaused
        )
        reason = try container.decode(
            InteractiveFocusEventReasonV0.self,
            forKey: .reason
        )
        validForMilliseconds = try container.decode(
            Int64.self,
            forKey: .validForMilliseconds
        )
        eventSequence = try container.decode(
            Int64.self,
            forKey: .eventSequence
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            interactiveSessionID,
            forKey: .interactiveSessionID
        )
        try container.encode(authorizationEpoch, forKey: .authorizationEpoch)
        try container.encode(currentSurfaceID, forKey: .currentSurfaceID)
        try container.encode(
            currentSurfaceRevision,
            forKey: .currentSurfaceRevision
        )
        try container.encode(
            currentCoordinateSpaceRevision,
            forKey: .currentCoordinateSpaceRevision
        )
        try container.encode(
            recommendedTargetKind,
            forKey: .recommendedTargetKind
        )
        try container.encode(targetToken, forKey: .targetToken)
        try container.encode(focus, forKey: .focus)
        try container.encode(inputPaused, forKey: .inputPaused)
        try container.encode(reason, forKey: .reason)
        try container.encode(
            validForMilliseconds,
            forKey: .validForMilliseconds
        )
        try container.encode(eventSequence, forKey: .eventSequence)
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1,
              authorizationEpoch.rawValue
                <= UInt64(WireLimits.maximumSafeInteger),
              currentSurfaceRevision.rawValue >= 1,
              currentSurfaceRevision.rawValue
                <= UInt64(WireLimits.maximumSafeInteger),
              currentCoordinateSpaceRevision.rawValue >= 1,
              currentCoordinateSpaceRevision.rawValue
                <= UInt64(WireLimits.maximumSafeInteger),
              (1...Self.maximumValidityMilliseconds).contains(
                validForMilliseconds
              ),
              (1...WireLimits.maximumSafeInteger).contains(eventSequence)
        else {
            throw InteractiveFocusEventWireErrorV0.invalidEvent
        }
        switch recommendedTargetKind {
        case .focusedRegion:
            guard targetToken != nil, let focus,
                  reason == .verifiedFocus else {
                throw InteractiveFocusEventWireErrorV0.invalidEvent
            }
            do { _ = try focus.materialize() }
            catch {
                throw InteractiveFocusEventWireErrorV0.invalidEvent
            }
        case .desktop:
            guard targetToken == nil, focus == nil,
                  reason != .verifiedFocus else {
                throw InteractiveFocusEventWireErrorV0.invalidEvent
            }
        case .application, .window:
            throw InteractiveFocusEventWireErrorV0.invalidEvent
        }
    }

    public func clientExpiry(
        receivedAtMonotonicMilliseconds: Int64
    ) throws -> Int64 {
        guard receivedAtMonotonicMilliseconds >= 0,
              receivedAtMonotonicMilliseconds
                <= WireLimits.maximumSafeInteger - validForMilliseconds else {
            throw InteractiveFocusEventWireErrorV0.invalidTime
        }
        return receivedAtMonotonicMilliseconds + validForMilliseconds
    }
}
