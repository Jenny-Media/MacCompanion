import Foundation
import CompanionDomain
import CompanionWire
import CompanionInteractiveShared

public typealias InteractiveNativeVideoRequestFenceV0 = InteractiveWebRTCNegotiationFenceV0
public enum InteractiveNativeVideoWireErrorV0: Error, Equatable, Sendable { case invalidMaterial }

@discardableResult private func nativeBytes(_ text: String, count: ClosedRange<Int>) throws -> Data {
    guard text.utf8.count <= ((count.upperBound + 2) / 3) * 4,
          let data = Data(base64Encoded: text), count.contains(data.count), data.base64EncodedString() == text else {
        throw InteractiveNativeVideoWireErrorV0.invalidMaterial
    }
    return data
}


private struct NativeOptionalCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private func nativeKeys(_ decoder: Decoder, required: Set<String>, optional: Set<String>) throws {
    let c = try decoder.container(keyedBy: NativeOptionalCodingKey.self)
    let actual = Set(c.allKeys.map(\.stringValue))
    guard required.isSubset(of: actual), actual.isSubset(of: required.union(optional)) else {
        throw InteractiveNativeVideoWireErrorV0.invalidMaterial
    }
}
private func nativeTrue(_ c: KeyedDecodingContainer<NativeOptionalCodingKey>, key: String) throws -> Bool? {
    let k = NativeOptionalCodingKey(stringValue: key)!
    guard c.contains(k) else { return nil }
    guard try c.decode(Bool.self, forKey: k) else { throw InteractiveNativeVideoWireErrorV0.invalidMaterial }
    return true
}

public struct InteractiveNativeVideoEnrollmentRequestBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey { case fence, clientCertificateDERBase64, previousFence, streamContinuity }
    public static let kind = WireMessageKind.nativeEnrollRequest
    public let fence: InteractiveNativeVideoRequestFenceV0
    public let previousFence: InteractiveNativeVideoRequestFenceV0?
    public let streamContinuity: Bool?
    public let clientCertificateDERBase64: String

    public init(fence: InteractiveNativeVideoRequestFenceV0, clientCertificateDERBase64: String,
                previousFence: InteractiveNativeVideoRequestFenceV0? = nil, streamContinuity: Bool? = nil) throws {
        self.previousFence = previousFence
        self.streamContinuity = streamContinuity
        self.fence = fence
        self.clientCertificateDERBase64 = clientCertificateDERBase64
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try nativeKeys(decoder, required: ["fence", "clientCertificateDERBase64"], optional: ["previousFence", "streamContinuity"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fence = try c.decode(InteractiveNativeVideoRequestFenceV0.self, forKey: .fence)
        clientCertificateDERBase64 = try c.decode(String.self, forKey: .clientCertificateDERBase64)
        previousFence = c.contains(.previousFence) ? try c.decode(InteractiveNativeVideoRequestFenceV0.self, forKey: .previousFence) : nil
        streamContinuity = try nativeTrue(decoder.container(keyedBy: NativeOptionalCodingKey.self), key: "streamContinuity")
        try validate()
    }

    public func validate() throws {
        try fence.validate()
        guard streamContinuity == nil || streamContinuity == true else { throw InteractiveNativeVideoWireErrorV0.invalidMaterial }
        if let previousFence {
            try previousFence.validate()
            guard streamContinuity == true, previousFence.interactiveSessionID == fence.interactiveSessionID,
                  previousFence.authorizationEpoch == fence.authorizationEpoch,
                  previousFence.negotiationID != fence.negotiationID,
                  previousFence.peerGeneration < fence.peerGeneration else {
                throw InteractiveNativeVideoWireErrorV0.invalidMaterial
            }
        }
        try nativeBytes(clientCertificateDERBase64, count: 1...4096)
    }
}

public struct InteractiveNativeVideoEnrollmentChallengeBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey { case fence, controlGeneration, encodedWidth, encodedHeight, hostCertificateDERBase64, hostChallengeBase64, signingInputBase64, issuedAtUnixMilliseconds, expiresAtUnixMilliseconds }
    public static let kind = WireMessageKind.nativeEnrollChallenge
    public let fence: InteractiveNativeVideoRequestFenceV0
    public let controlGeneration: WireUUID
    public let encodedWidth: UInt16
    public let encodedHeight: UInt16
    public let hostCertificateDERBase64: String
    public let hostChallengeBase64: String
    public let signingInputBase64: String
    public let issuedAtUnixMilliseconds: UInt64
    public let expiresAtUnixMilliseconds: UInt64

    public init(fence: InteractiveNativeVideoRequestFenceV0, controlGeneration: WireUUID, encodedWidth: UInt16, encodedHeight: UInt16, hostCertificateDERBase64: String, hostChallengeBase64: String, signingInputBase64: String, issuedAtUnixMilliseconds: UInt64, expiresAtUnixMilliseconds: UInt64) throws {
        self.fence = fence
        self.controlGeneration = controlGeneration
        self.encodedWidth = encodedWidth
        self.encodedHeight = encodedHeight
        self.hostCertificateDERBase64 = hostCertificateDERBase64
        self.hostChallengeBase64 = hostChallengeBase64
        self.signingInputBase64 = signingInputBase64
        self.issuedAtUnixMilliseconds = issuedAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["fence", "controlGeneration", "encodedWidth", "encodedHeight", "hostCertificateDERBase64", "hostChallengeBase64", "signingInputBase64", "issuedAtUnixMilliseconds", "expiresAtUnixMilliseconds"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fence = try c.decode(InteractiveNativeVideoRequestFenceV0.self, forKey: .fence)
        controlGeneration = try c.decode(WireUUID.self, forKey: .controlGeneration)
        encodedWidth = try c.decode(UInt16.self, forKey: .encodedWidth)
        encodedHeight = try c.decode(UInt16.self, forKey: .encodedHeight)
        hostCertificateDERBase64 = try c.decode(String.self, forKey: .hostCertificateDERBase64)
        hostChallengeBase64 = try c.decode(String.self, forKey: .hostChallengeBase64)
        signingInputBase64 = try c.decode(String.self, forKey: .signingInputBase64)
        issuedAtUnixMilliseconds = try c.decode(UInt64.self, forKey: .issuedAtUnixMilliseconds)
        expiresAtUnixMilliseconds = try c.decode(UInt64.self, forKey: .expiresAtUnixMilliseconds)
        try validate()
    }

    public func validate() throws {
        try fence.validate()
        try nativeBytes(hostCertificateDERBase64, count: 1...4096)
        try nativeBytes(hostChallengeBase64, count: 32...32)
        try nativeBytes(signingInputBase64, count: 1...1024)
        guard (320...8192).contains(encodedWidth), (240...8192).contains(encodedHeight), issuedAtUnixMilliseconds > 0, expiresAtUnixMilliseconds <= UInt64(WireLimits.maximumSafeInteger), expiresAtUnixMilliseconds > issuedAtUnixMilliseconds, expiresAtUnixMilliseconds - issuedAtUnixMilliseconds <= 15_000 else { throw InteractiveNativeVideoWireErrorV0.invalidMaterial }
    }

    public func preparation() throws -> InteractiveNativeVideoEnrollmentPreparationV0 {
        try validate()
        return try .init(hostCertificateDER: nativeBytes(hostCertificateDERBase64, count: 1...4096),
            signingInput: nativeBytes(signingInputBase64, count: 1...1024),
            hostChallenge: nativeBytes(hostChallengeBase64, count: 32...32),
            issuedAtUnixMilliseconds: issuedAtUnixMilliseconds, expiresAtUnixMilliseconds: expiresAtUnixMilliseconds)
    }
}

public struct InteractiveNativeVideoEnrollmentProofBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey { case fence, challengeMessageID, signatureBase64 }
    public static let kind = WireMessageKind.nativeEnrollProof
    public let fence: InteractiveNativeVideoRequestFenceV0
    public let challengeMessageID: WireUUID
    public let signatureBase64: String

    public init(fence: InteractiveNativeVideoRequestFenceV0, challengeMessageID: WireUUID, signatureBase64: String) throws {
        self.fence = fence
        self.challengeMessageID = challengeMessageID
        self.signatureBase64 = signatureBase64
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["fence", "challengeMessageID", "signatureBase64"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fence = try c.decode(InteractiveNativeVideoRequestFenceV0.self, forKey: .fence)
        challengeMessageID = try c.decode(WireUUID.self, forKey: .challengeMessageID)
        signatureBase64 = try c.decode(String.self, forKey: .signatureBase64)
        try validate()
    }

    public func validate() throws {
        try fence.validate()
        try nativeBytes(signatureBase64, count: 64...64)
    }
}

public struct InteractiveNativeVideoReadyBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey { case fence, challengeMessageID, portBase, streamContinuity }
    public static let kind = WireMessageKind.nativeReady
    public let streamContinuity: Bool?
    public let fence: InteractiveNativeVideoRequestFenceV0
    public let challengeMessageID: WireUUID
    public let portBase: UInt16

    public init(fence: InteractiveNativeVideoRequestFenceV0, challengeMessageID: WireUUID, portBase: UInt16, streamContinuity: Bool? = nil) throws {
        self.streamContinuity = streamContinuity
        self.fence = fence
        self.challengeMessageID = challengeMessageID
        self.portBase = portBase
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try nativeKeys(decoder, required: ["fence", "challengeMessageID", "portBase"], optional: ["streamContinuity"])
        let values = try decoder.container(keyedBy: NativeOptionalCodingKey.self)
        streamContinuity = try nativeTrue(values, key: "streamContinuity")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fence = try c.decode(InteractiveNativeVideoRequestFenceV0.self, forKey: .fence)
        challengeMessageID = try c.decode(WireUUID.self, forKey: .challengeMessageID)
        portBase = try c.decode(UInt16.self, forKey: .portBase)
        try validate()
    }

    public func validate() throws {
        try fence.validate()
        guard streamContinuity == nil || streamContinuity == true else { throw InteractiveNativeVideoWireErrorV0.invalidMaterial }
        guard portBase > 1029, portBase < 65500 else { throw InteractiveNativeVideoWireErrorV0.invalidMaterial }
    }
}

public struct InteractiveNativeVideoCancelBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey { case fence, retainStream }
    public static let kind = WireMessageKind.nativeCancel
    public let retainStream: Bool?
    public let fence: InteractiveNativeVideoRequestFenceV0

    public init(fence: InteractiveNativeVideoRequestFenceV0, retainStream: Bool? = nil) throws {
        self.retainStream = retainStream
        self.fence = fence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try nativeKeys(decoder, required: ["fence"], optional: ["retainStream"])
        let values = try decoder.container(keyedBy: NativeOptionalCodingKey.self)
        retainStream = try nativeTrue(values, key: "retainStream")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fence = try c.decode(InteractiveNativeVideoRequestFenceV0.self, forKey: .fence)
        try validate()
    }

    public func validate() throws {
        try fence.validate()
        guard retainStream == nil || retainStream == true else { throw InteractiveNativeVideoWireErrorV0.invalidMaterial }
    }
}

public struct InteractiveNativeVideoCancelledBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey { case fence, streamRetained }
    public static let kind = WireMessageKind.nativeCancelled
    public let streamRetained: Bool?
    public let fence: InteractiveNativeVideoRequestFenceV0

    public init(fence: InteractiveNativeVideoRequestFenceV0, streamRetained: Bool? = nil) throws {
        self.streamRetained = streamRetained
        self.fence = fence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try nativeKeys(decoder, required: ["fence"], optional: ["streamRetained"])
        let values = try decoder.container(keyedBy: NativeOptionalCodingKey.self)
        streamRetained = try nativeTrue(values, key: "streamRetained")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fence = try c.decode(InteractiveNativeVideoRequestFenceV0.self, forKey: .fence)
        try validate()
    }

    public func validate() throws {
        try fence.validate()
        guard streamRetained == nil || streamRetained == true else { throw InteractiveNativeVideoWireErrorV0.invalidMaterial }
    }
}


public struct InteractiveNativeVideoPresentationRequestBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey { case fence, challengeMessageID, nativeGeneration, encodedWidth, encodedHeight }
    public static let kind = WireMessageKind.nativePresentRequest
    public let fence: InteractiveNativeVideoRequestFenceV0
    public let challengeMessageID: WireUUID
    public let nativeGeneration: Int64
    public let encodedWidth: UInt16
    public let encodedHeight: UInt16

    public init(fence: InteractiveNativeVideoRequestFenceV0, challengeMessageID: WireUUID, nativeGeneration: Int64, encodedWidth: UInt16, encodedHeight: UInt16) throws {
        self.fence = fence
        self.challengeMessageID = challengeMessageID
        self.nativeGeneration = nativeGeneration
        self.encodedWidth = encodedWidth
        self.encodedHeight = encodedHeight
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["fence", "challengeMessageID", "nativeGeneration", "encodedWidth", "encodedHeight"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fence = try c.decode(InteractiveNativeVideoRequestFenceV0.self, forKey: .fence)
        challengeMessageID = try c.decode(WireUUID.self, forKey: .challengeMessageID)
        nativeGeneration = try c.decode(Int64.self, forKey: .nativeGeneration)
        encodedWidth = try c.decode(UInt16.self, forKey: .encodedWidth)
        encodedHeight = try c.decode(UInt16.self, forKey: .encodedHeight)
        try validate()
    }

    public func validate() throws {
        try fence.validate()
        guard (1...WireLimits.maximumSafeInteger).contains(nativeGeneration),
              (320...8192).contains(encodedWidth), (240...8192).contains(encodedHeight) else {
            throw InteractiveNativeVideoWireErrorV0.invalidMaterial
        }
    }
}

public struct InteractiveNativeVideoPresentationReceiptBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey { case fence, challengeMessageID, nativeGeneration, encodedWidth, encodedHeight, capturePixelWidth, capturePixelHeight, logicalWidthPoints, logicalHeightPoints, inputAdmitted }
    public static let kind = WireMessageKind.nativePresentReceipt
    public let fence: InteractiveNativeVideoRequestFenceV0
    public let challengeMessageID: WireUUID
    public let nativeGeneration: Int64
    public let encodedWidth: UInt16
    public let encodedHeight: UInt16
    public let capturePixelWidth: UInt32
    public let capturePixelHeight: UInt32
    public let logicalWidthPoints: UInt32
    public let logicalHeightPoints: UInt32
    public let inputAdmitted: Bool

    public init(fence: InteractiveNativeVideoRequestFenceV0, challengeMessageID: WireUUID, nativeGeneration: Int64, encodedWidth: UInt16, encodedHeight: UInt16, capturePixelWidth: UInt32, capturePixelHeight: UInt32, logicalWidthPoints: UInt32, logicalHeightPoints: UInt32, inputAdmitted: Bool = false) throws {
        self.fence = fence
        self.challengeMessageID = challengeMessageID
        self.nativeGeneration = nativeGeneration
        self.encodedWidth = encodedWidth
        self.encodedHeight = encodedHeight
        self.capturePixelWidth = capturePixelWidth
        self.capturePixelHeight = capturePixelHeight
        self.logicalWidthPoints = logicalWidthPoints
        self.logicalHeightPoints = logicalHeightPoints
        self.inputAdmitted = inputAdmitted
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["fence", "challengeMessageID", "nativeGeneration", "encodedWidth", "encodedHeight", "capturePixelWidth", "capturePixelHeight", "logicalWidthPoints", "logicalHeightPoints", "inputAdmitted"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fence = try c.decode(InteractiveNativeVideoRequestFenceV0.self, forKey: .fence)
        challengeMessageID = try c.decode(WireUUID.self, forKey: .challengeMessageID)
        nativeGeneration = try c.decode(Int64.self, forKey: .nativeGeneration)
        encodedWidth = try c.decode(UInt16.self, forKey: .encodedWidth)
        encodedHeight = try c.decode(UInt16.self, forKey: .encodedHeight)
        capturePixelWidth = try c.decode(UInt32.self, forKey: .capturePixelWidth)
        capturePixelHeight = try c.decode(UInt32.self, forKey: .capturePixelHeight)
        logicalWidthPoints = try c.decode(UInt32.self, forKey: .logicalWidthPoints)
        logicalHeightPoints = try c.decode(UInt32.self, forKey: .logicalHeightPoints)
        inputAdmitted = try c.decode(Bool.self, forKey: .inputAdmitted)
        try validate()
    }

    public func validate() throws {
        try fence.validate()
        guard (1...WireLimits.maximumSafeInteger).contains(nativeGeneration),
              (320...8192).contains(encodedWidth), (240...8192).contains(encodedHeight),
              (1...32768).contains(capturePixelWidth), (1...32768).contains(capturePixelHeight),
              logicalWidthPoints > 0, logicalHeightPoints > 0 else {
            throw InteractiveNativeVideoWireErrorV0.invalidMaterial
        }
    }
}
