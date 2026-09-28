import CompanionDomain
import CompanionWire
import Foundation

public enum InteractiveWebRTCSignalingErrorV0: Error, Equatable, Sendable {
    case invalidFence
    case invalidSDP
}

public struct InteractiveWebRTCNegotiationFenceV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case interactiveSessionID, authorizationEpoch, negotiationID
        case peerGeneration, surfaceID, surfaceRevision
        case coordinateSpaceRevision
    }

    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let negotiationID: WireUUID
    public let peerGeneration: Int64
    public let surfaceID: WireUUID
    public let surfaceRevision: Int64
    public let coordinateSpaceRevision: Int64

    public init(
        interactiveSessionID: WireUUID,
        authorizationEpoch: AuthorizationEpoch,
        negotiationID: WireUUID,
        peerGeneration: Int64,
        surfaceID: WireUUID,
        surfaceRevision: Int64,
        coordinateSpaceRevision: Int64
    ) throws {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.negotiationID = negotiationID
        self.peerGeneration = peerGeneration
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.coordinateSpaceRevision = coordinateSpaceRevision
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [
            "interactiveSessionID", "authorizationEpoch", "negotiationID",
            "peerGeneration", "surfaceID", "surfaceRevision",
            "coordinateSpaceRevision",
        ])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        interactiveSessionID = try c.decode(WireUUID.self, forKey: .interactiveSessionID)
        authorizationEpoch = try c.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch)
        negotiationID = try c.decode(WireUUID.self, forKey: .negotiationID)
        peerGeneration = try c.decode(Int64.self, forKey: .peerGeneration)
        surfaceID = try c.decode(WireUUID.self, forKey: .surfaceID)
        surfaceRevision = try c.decode(Int64.self, forKey: .surfaceRevision)
        coordinateSpaceRevision = try c.decode(Int64.self, forKey: .coordinateSpaceRevision)
        try validate()
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue > 0,
              peerGeneration > 0,
              peerGeneration <= WireLimits.maximumSafeInteger,
              surfaceRevision > 0,
              surfaceRevision <= WireLimits.maximumSafeInteger,
              coordinateSpaceRevision > 0,
              coordinateSpaceRevision <= WireLimits.maximumSafeInteger else {
            throw InteractiveWebRTCSignalingErrorV0.invalidFence
        }
    }
}

public struct InteractiveWebRTCOfferRequestBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey { case fence }
    public static let kind = WireMessageKind.interactiveMediaOfferRequest
    public let fence: InteractiveWebRTCNegotiationFenceV0

    public init(fence: InteractiveWebRTCNegotiationFenceV0) throws {
        self.fence = fence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["fence"])
        fence = try decoder.container(keyedBy: CodingKeys.self)
            .decode(InteractiveWebRTCNegotiationFenceV0.self, forKey: .fence)
        try validate()
    }

    public func validate() throws { try fence.validate() }
}

public struct InteractiveWebRTCOfferBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey {
        case fence, sdp, dtlsFingerprintHex
    }
    public static let kind = WireMessageKind.interactiveMediaOffer
    public let fence: InteractiveWebRTCNegotiationFenceV0
    public let sdp: String
    public let dtlsFingerprintHex: String

    public init(fence: InteractiveWebRTCNegotiationFenceV0,
                sdp: String, dtlsFingerprintHex: String) throws {
        self.fence = fence
        self.sdp = sdp
        self.dtlsFingerprintHex = dtlsFingerprintHex
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["fence", "sdp", "dtlsFingerprintHex"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fence = try c.decode(InteractiveWebRTCNegotiationFenceV0.self, forKey: .fence)
        sdp = try c.decode(String.self, forKey: .sdp)
        dtlsFingerprintHex = try c.decode(String.self, forKey: .dtlsFingerprintHex)
        try validate()
    }

    public func validate() throws {
        try fence.validate()
        try InteractiveWebRTCSDPV0.validate(sdp, fingerprintHex: dtlsFingerprintHex)
    }
}

public struct InteractiveWebRTCAnswerBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey {
        case fence, offerMessageID, sdp, dtlsFingerprintHex
    }
    public static let kind = WireMessageKind.interactiveMediaAnswer
    public let fence: InteractiveWebRTCNegotiationFenceV0
    public let offerMessageID: WireUUID
    public let sdp: String
    public let dtlsFingerprintHex: String

    public init(fence: InteractiveWebRTCNegotiationFenceV0,
                offerMessageID: WireUUID, sdp: String,
                dtlsFingerprintHex: String) throws {
        self.fence = fence
        self.offerMessageID = offerMessageID
        self.sdp = sdp
        self.dtlsFingerprintHex = dtlsFingerprintHex
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [
            "fence", "offerMessageID", "sdp", "dtlsFingerprintHex",
        ])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fence = try c.decode(InteractiveWebRTCNegotiationFenceV0.self, forKey: .fence)
        offerMessageID = try c.decode(WireUUID.self, forKey: .offerMessageID)
        sdp = try c.decode(String.self, forKey: .sdp)
        dtlsFingerprintHex = try c.decode(String.self, forKey: .dtlsFingerprintHex)
        try validate()
    }

    public func validate() throws {
        try fence.validate()
        try InteractiveWebRTCSDPV0.validate(sdp, fingerprintHex: dtlsFingerprintHex)
    }
}

public struct InteractiveWebRTCReadyBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey { case fence, offerMessageID }
    public static let kind = WireMessageKind.interactiveMediaReady
    public let fence: InteractiveWebRTCNegotiationFenceV0
    public let offerMessageID: WireUUID

    public init(fence: InteractiveWebRTCNegotiationFenceV0,
                offerMessageID: WireUUID) throws {
        self.fence = fence
        self.offerMessageID = offerMessageID
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["fence", "offerMessageID"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fence = try c.decode(InteractiveWebRTCNegotiationFenceV0.self, forKey: .fence)
        offerMessageID = try c.decode(WireUUID.self, forKey: .offerMessageID)
        try validate()
    }

    public func validate() throws { try fence.validate() }
}

private enum InteractiveWebRTCSDPV0 {
    static func validate(_ sdp: String, fingerprintHex: String) throws {
        let bytes = Array(sdp.utf8)
        guard !bytes.isEmpty, bytes.count <= 48_000,
              bytes.allSatisfy({ $0 == 13 || $0 == 10 || (32...126).contains($0) }),
              sdp.hasSuffix("\r\n"),
              fingerprintHex.utf8.count == 64,
              fingerprintHex.utf8.allSatisfy({
                  (48...57).contains($0) || (97...102).contains($0)
              }) else {
            throw InteractiveWebRTCSignalingErrorV0.invalidSDP
        }
        let lines = sdp.components(separatedBy: "\r\n")
        guard lines.first == "v=0", lines.last == "",
              lines.dropLast().allSatisfy({ !$0.isEmpty && !$0.contains("\r") && !$0.contains("\n") }),
              lines.contains(where: { $0.hasPrefix("a=candidate:") }) else {
            throw InteractiveWebRTCSignalingErrorV0.invalidSDP
        }
        let fingerprints = lines.filter { $0.hasPrefix("a=fingerprint:") }
        guard !fingerprints.isEmpty else {
            throw InteractiveWebRTCSignalingErrorV0.invalidSDP
        }
        let expected = "a=fingerprint:sha-256 " + stride(from: 0, to: 64, by: 2)
            .map { index in
                let start = fingerprintHex.index(fingerprintHex.startIndex, offsetBy: index)
                let end = fingerprintHex.index(start, offsetBy: 2)
                return fingerprintHex[start..<end].uppercased()
            }.joined(separator: ":")
        guard fingerprints.allSatisfy({ $0 == expected }) else {
            throw InteractiveWebRTCSignalingErrorV0.invalidSDP
        }
    }
}
