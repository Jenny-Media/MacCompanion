import CompanionDomain
import CompanionInteractiveShared
import CompanionInteractiveWire
import Foundation

public enum ClientDecoderRenderPhaseV0: String, Equatable, Sendable {
    case awaitingConfiguration
    case awaitingCleanKeyframe
    case decoding
    case ended
    case closed
}

public enum ClientDecoderRenderErrorV0: Error, Equatable, Sendable {
    case invalidPhase(ClientDecoderRenderPhaseV0)
    case admissionMismatch
    case payloadLengthMismatch
    case fenceMismatch
    case sequenceMismatch
    case presentationTimeOutOfRange
    case generationExhausted
}

public struct ClientDecoderFenceV0: Equatable, Sendable {
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let surfaceID: UUID
    public let surfaceRevision: SurfaceRevision
    public let coordinateSpaceRevision: CoordinateSpaceRevision
    public let encodedWidth: UInt16
    public let encodedHeight: UInt16

    public init(header: MediaRecordHeader) {
        interactiveSessionID = header.interactiveSessionID
        authorizationEpoch = header.authorizationEpoch
        surfaceID = header.surfaceID
        surfaceRevision = header.surfaceRevision
        coordinateSpaceRevision = header.coordinateSpaceRevision
        encodedWidth = header.encodedWidth
        encodedHeight = header.encodedHeight
    }
}

public struct ClientDecoderConfigurationCommandV0: Equatable, Sendable {
    public let generation: UInt64
    public let fence: ClientDecoderFenceV0
    public let configuration: Data
}

public struct ClientDecodeAccessUnitCommandV0: Equatable, Sendable {
    public let generation: UInt64
    public let fence: ClientDecoderFenceV0
    public let mediaSequence: UInt64
    public let presentationTimeNanoseconds: UInt64
    public let cleanKeyframe: Bool
    public let accessUnit: Data
}

public enum ClientDecoderActionV0: Equatable, Sendable {
    case configure(ClientDecoderConfigurationCommandV0)
    case decode(ClientDecodeAccessUnitCommandV0)
    case reset(generation: UInt64, fence: ClientDecoderFenceV0)
    case end
}

public struct ClientDecodedFrameReceiptV0: Equatable, Sendable {
    public let generation: UInt64
    public let fence: ClientDecoderFenceV0
    public let mediaSequence: UInt64
    public let presentationTimeNanoseconds: UInt64
    public let frameReference: UUID

    public init(
        generation: UInt64,
        fence: ClientDecoderFenceV0,
        mediaSequence: UInt64,
        presentationTimeNanoseconds: UInt64,
        frameReference: UUID
    ) {
        self.generation = generation
        self.fence = fence
        self.mediaSequence = mediaSequence
        self.presentationTimeNanoseconds = presentationTimeNanoseconds
        self.frameReference = frameReference
    }
}

public enum ClientDecodedFrameAdmissionV0: Equatable, Sendable {
    case accepted
    case replaced(previousFrameReference: UUID)
    case discardedStale
}

public struct ClientDecoderRenderAuthorityV0: Sendable {
    public private(set) var phase:
        ClientDecoderRenderPhaseV0 = .awaitingConfiguration
    public private(set) var generation: UInt64 = 0
    public private(set) var fence: ClientDecoderFenceV0?
    public private(set) var lastSubmittedMediaSequence: UInt64 = 0
    public private(set) var latestFrame: ClientDecodedFrameReceiptV0?

    public init() {}

    public mutating func process(
        header: MediaRecordHeader,
        payload: Data,
        admission: ClientMediaAdmissionV0
    ) throws -> ClientDecoderActionV0 {
        do {
            guard phase != .closed, phase != .ended else {
                throw ClientDecoderRenderErrorV0.invalidPhase(phase)
            }
            guard payload.count == Int(header.payloadLength) else {
                throw ClientDecoderRenderErrorV0.payloadLengthMismatch
            }
            switch admission {
            case .decoderConfiguration:
                guard header.type == .decoderConfiguration else {
                    throw ClientDecoderRenderErrorV0.admissionMismatch
                }
                try AVCCPayloadValidatorV0.validateDecoderConfiguration(payload)
                let nextFence = ClientDecoderFenceV0(header: header)
                if phase == .awaitingConfiguration, generation > 0 {
                    guard fence?.sameSurface(as: nextFence) == true else {
                        throw ClientDecoderRenderErrorV0.fenceMismatch
                    }
                    fence = nextFence
                } else {
                    try advanceGeneration()
                    fence = nextFence
                }
                latestFrame = nil
                lastSubmittedMediaSequence = 0
                phase = .awaitingCleanKeyframe
                return .configure(ClientDecoderConfigurationCommandV0(
                    generation: generation,
                    fence: nextFence,
                    configuration: payload
                ))

            case let .videoAccessUnit(cleanKeyframe):
                guard header.type == .videoAccessUnit,
                      phase == .awaitingCleanKeyframe || phase == .decoding,
                      fence == ClientDecoderFenceV0(header: header),
                      header.mediaSequence > lastSubmittedMediaSequence else {
                    throw ClientDecoderRenderErrorV0.admissionMismatch
                }
                guard header.presentationTimeNanoseconds
                        <= UInt64(Int64.max) else {
                    throw ClientDecoderRenderErrorV0
                        .presentationTimeOutOfRange
                }
                if phase == .awaitingCleanKeyframe, !cleanKeyframe {
                    throw ClientDecoderRenderErrorV0.admissionMismatch
                }
                try AVCCPayloadValidatorV0.validateAccessUnit(
                    payload,
                    cleanKeyframe: cleanKeyframe
                )
                lastSubmittedMediaSequence = header.mediaSequence
                phase = .decoding
                return .decode(ClientDecodeAccessUnitCommandV0(
                    generation: generation,
                    fence: ClientDecoderFenceV0(header: header),
                    mediaSequence: header.mediaSequence,
                    presentationTimeNanoseconds:
                        header.presentationTimeNanoseconds,
                    cleanKeyframe: cleanKeyframe,
                    accessUnit: payload
                ))

            case .discontinuity:
                guard header.type == .discontinuity, payload.isEmpty else {
                    throw ClientDecoderRenderErrorV0.admissionMismatch
                }
                var nextFence = ClientDecoderFenceV0(header: header)
                nextFence = ClientDecoderFenceV0(
                    interactiveSessionID: nextFence.interactiveSessionID,
                    authorizationEpoch: nextFence.authorizationEpoch,
                    surfaceID: nextFence.surfaceID,
                    surfaceRevision: nextFence.surfaceRevision,
                    coordinateSpaceRevision:
                        nextFence.coordinateSpaceRevision,
                    encodedWidth: 0,
                    encodedHeight: 0
                )
                if let fence,
                   !fence.allowsDiscontinuity(to: nextFence) {
                    throw ClientDecoderRenderErrorV0.fenceMismatch
                }
                try advanceGeneration()
                fence = nextFence
                latestFrame = nil
                lastSubmittedMediaSequence = 0
                phase = .awaitingConfiguration
                return .reset(generation: generation, fence: nextFence)

            case .end:
                let endFence = ClientDecoderFenceV0(header: header)
                guard header.type == .end,
                      payload.isEmpty else {
                    throw ClientDecoderRenderErrorV0.admissionMismatch
                }
                guard fence?.sameSurface(as: endFence) == true else {
                    throw ClientDecoderRenderErrorV0.fenceMismatch
                }
                latestFrame = nil
                fence = nil
                phase = .ended
                return .end
            }
        } catch {
            close()
            throw error
        }
    }

    public mutating func admitDecodedFrame(
        _ receipt: ClientDecodedFrameReceiptV0
    ) -> ClientDecodedFrameAdmissionV0 {
        guard phase == .decoding,
              receipt.generation == generation,
              receipt.fence == fence,
              receipt.mediaSequence <= lastSubmittedMediaSequence,
              latestFrame.map({
                  receipt.mediaSequence > $0.mediaSequence
              }) ?? true else {
            return .discardedStale
        }
        let previous = latestFrame?.frameReference
        latestFrame = receipt
        if let previous {
            return .replaced(previousFrameReference: previous)
        }
        return .accepted
    }

    public mutating func blank() -> UUID? {
        defer { latestFrame = nil }
        return latestFrame?.frameReference
    }

    public mutating func close() {
        phase = .closed
        fence = nil
        latestFrame = nil
        lastSubmittedMediaSequence = 0
    }

    private mutating func advanceGeneration() throws {
        guard generation < UInt64.max else {
            throw ClientDecoderRenderErrorV0.generationExhausted
        }
        generation += 1
    }
}

private extension ClientDecoderFenceV0 {
    func sameSurface(as other: ClientDecoderFenceV0) -> Bool {
        interactiveSessionID == other.interactiveSessionID
            && authorizationEpoch == other.authorizationEpoch
            && surfaceID == other.surfaceID
            && surfaceRevision == other.surfaceRevision
            && coordinateSpaceRevision == other.coordinateSpaceRevision
    }

    func allowsDiscontinuity(to other: ClientDecoderFenceV0) -> Bool {
        guard interactiveSessionID == other.interactiveSessionID,
              authorizationEpoch == other.authorizationEpoch else {
            return false
        }
        if surfaceID == other.surfaceID {
            return surfaceRevision == other.surfaceRevision
                && coordinateSpaceRevision
                    == other.coordinateSpaceRevision
        }
        return other.surfaceRevision.rawValue > surfaceRevision.rawValue
            && other.coordinateSpaceRevision.rawValue
                > coordinateSpaceRevision.rawValue
    }

    init(
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        surfaceID: UUID,
        surfaceRevision: SurfaceRevision,
        coordinateSpaceRevision: CoordinateSpaceRevision,
        encodedWidth: UInt16,
        encodedHeight: UInt16
    ) {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.coordinateSpaceRevision = coordinateSpaceRevision
        self.encodedWidth = encodedWidth
        self.encodedHeight = encodedHeight
    }
}
