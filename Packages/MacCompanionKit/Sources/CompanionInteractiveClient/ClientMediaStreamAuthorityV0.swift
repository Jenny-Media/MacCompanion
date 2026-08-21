import CompanionDomain
import CompanionInteractiveShared
import CompanionInteractiveWire
import Foundation

public enum ClientMediaStreamPhaseV0: String, Equatable, Sendable {
    case active
    case ended
    case closed
}

public enum ClientMediaStreamErrorV0: Error, Equatable, Sendable {
    case invalidState(ClientMediaStreamPhaseV0)
    case invalidDescriptor
    case transitionAlreadyPending
    case nonAdvancingDescriptor
    case fenceMismatch
    case sequenceNotIncreasing
    case presentationTimeWentBackward
    case payloadLengthMismatch
    case dimensionsMismatch
    case discontinuityRequired
    case decoderConfigurationRequired
    case cleanKeyframeRequired
    case acknowledgementNotReady
}

public enum ClientMediaAdmissionV0: Equatable, Sendable {
    case decoderConfiguration
    case videoAccessUnit(cleanKeyframe: Bool)
    case discontinuity
    case end
}

public struct ClientMediaAcknowledgementFenceV0: Equatable, Sendable {
    public let surface: SurfaceInputFence
    public let readyMediaSequence: UInt64

    public init(
        surface: SurfaceInputFence,
        readyMediaSequence: UInt64
    ) {
        self.surface = surface
        self.readyMediaSequence = readyMediaSequence
    }
}

/// Validates media framing and surface fences before any payload reaches a
/// decoder. The payload remains opaque; only its exact byte count is observed.
public struct ClientMediaStreamAuthorityV0: Sendable {
    public private(set) var phase: ClientMediaStreamPhaseV0 = .active
    public private(set) var currentDescriptor: AdaptiveSurfaceDescriptor
    public private(set) var pendingDescriptor: AdaptiveSurfaceDescriptor?
    public private(set) var lastMediaSequence: UInt64 = 0
    public private(set) var lastPresentationTimeNanoseconds: UInt64 = 0
    public private(set) var pendingAcknowledgementMediaSequence: UInt64?

    private var configuredDimensions: (UInt16, UInt16)?
    private var cleanKeyframeRequired = true
    private var acknowledgementReady = false

    public init(initialDescriptor: AdaptiveSurfaceDescriptor) throws {
        do {
            try initialDescriptor.validate()
        } catch {
            throw ClientMediaStreamErrorV0.invalidDescriptor
        }
        currentDescriptor = initialDescriptor
    }

    public mutating func beginSurfaceTransition(
        to descriptor: AdaptiveSurfaceDescriptor
    ) throws {
        do {
            guard phase == .active else {
                throw ClientMediaStreamErrorV0.invalidState(phase)
            }
            guard pendingDescriptor == nil else {
                throw ClientMediaStreamErrorV0.transitionAlreadyPending
            }
            do {
                try descriptor.validate()
            } catch {
                throw ClientMediaStreamErrorV0.invalidDescriptor
            }
            guard descriptor.interactiveSessionID
                    == currentDescriptor.interactiveSessionID,
                  descriptor.authorizationEpoch
                    == currentDescriptor.authorizationEpoch else {
                throw ClientMediaStreamErrorV0.fenceMismatch
            }
            guard descriptor.surfaceRevision.rawValue
                    > currentDescriptor.surfaceRevision.rawValue,
                  descriptor.coordinateSpaceRevision.rawValue
                    > currentDescriptor.coordinateSpaceRevision.rawValue else {
                throw ClientMediaStreamErrorV0.nonAdvancingDescriptor
            }
            pendingDescriptor = descriptor
            acknowledgementReady = false
            pendingAcknowledgementMediaSequence = nil
        } catch {
            close()
            throw error
        }
    }

    @discardableResult
    public mutating func admit(
        header: MediaRecordHeader,
        payloadByteCount: Int
    ) throws -> ClientMediaAdmissionV0 {
        do {
            guard phase == .active else {
                throw ClientMediaStreamErrorV0.invalidState(phase)
            }
            try header.validate()
            guard payloadByteCount >= 0,
                  UInt64(payloadByteCount) == UInt64(header.payloadLength) else {
                throw ClientMediaStreamErrorV0.payloadLengthMismatch
            }
            guard header.mediaSequence > lastMediaSequence else {
                throw ClientMediaStreamErrorV0.sequenceNotIncreasing
            }
            guard lastMediaSequence == 0
                    || header.presentationTimeNanoseconds
                        >= lastPresentationTimeNanoseconds else {
                throw ClientMediaStreamErrorV0.presentationTimeWentBackward
            }

            let result: ClientMediaAdmissionV0
            switch header.type {
            case .discontinuity:
                if let pendingDescriptor {
                    guard matches(header, descriptor: pendingDescriptor) else {
                        throw ClientMediaStreamErrorV0.fenceMismatch
                    }
                    currentDescriptor = pendingDescriptor
                    self.pendingDescriptor = nil
                } else {
                    guard matches(header, descriptor: currentDescriptor) else {
                        throw ClientMediaStreamErrorV0.fenceMismatch
                    }
                }
                configuredDimensions = nil
                cleanKeyframeRequired = true
                acknowledgementReady = false
                pendingAcknowledgementMediaSequence = nil
                result = .discontinuity

            case .decoderConfiguration:
                guard pendingDescriptor == nil else {
                    throw ClientMediaStreamErrorV0.discontinuityRequired
                }
                try requireCurrentFenceAndDimensions(header)
                configuredDimensions = (
                    header.encodedWidth,
                    header.encodedHeight
                )
                cleanKeyframeRequired = true
                acknowledgementReady = false
                pendingAcknowledgementMediaSequence = nil
                result = .decoderConfiguration

            case .videoAccessUnit:
                guard pendingDescriptor == nil else {
                    throw ClientMediaStreamErrorV0.discontinuityRequired
                }
                try requireCurrentFenceAndDimensions(header)
                guard configuredDimensions?.0 == header.encodedWidth,
                      configuredDimensions?.1 == header.encodedHeight else {
                    throw ClientMediaStreamErrorV0.decoderConfigurationRequired
                }
                if cleanKeyframeRequired {
                    guard header.flags.contains(.cleanKeyframe) else {
                        throw ClientMediaStreamErrorV0.cleanKeyframeRequired
                    }
                    cleanKeyframeRequired = false
                    acknowledgementReady = true
                    pendingAcknowledgementMediaSequence = header.mediaSequence
                }
                result = .videoAccessUnit(
                    cleanKeyframe: header.flags.contains(.cleanKeyframe)
                )

            case .end:
                guard pendingDescriptor == nil,
                      matches(header, descriptor: currentDescriptor) else {
                    throw ClientMediaStreamErrorV0.fenceMismatch
                }
                phase = .ended
                configuredDimensions = nil
                acknowledgementReady = false
                pendingAcknowledgementMediaSequence = nil
                result = .end
            }
            lastMediaSequence = header.mediaSequence
            lastPresentationTimeNanoseconds = header.presentationTimeNanoseconds
            return result
        } catch {
            close()
            throw error
        }
    }

    public mutating func takeAcknowledgementFence() throws
        -> ClientMediaAcknowledgementFenceV0
    {
        guard phase == .active, acknowledgementReady,
              pendingDescriptor == nil,
              let readyMediaSequence = pendingAcknowledgementMediaSequence else {
            throw ClientMediaStreamErrorV0.acknowledgementNotReady
        }
        acknowledgementReady = false
        pendingAcknowledgementMediaSequence = nil
        return ClientMediaAcknowledgementFenceV0(
            surface: SurfaceInputFence(
                interactiveSessionID: currentDescriptor.interactiveSessionID,
                authorizationEpoch: currentDescriptor.authorizationEpoch,
                surfaceID: currentDescriptor.surfaceID,
                surfaceRevision: currentDescriptor.surfaceRevision,
                coordinateSpaceRevision:
                    currentDescriptor.coordinateSpaceRevision,
                focusToken: currentDescriptor.focus?.token,
                focusRevision: currentDescriptor.focus?.revision
            ),
            readyMediaSequence: readyMediaSequence
        )
    }

    public mutating func close() {
        phase = .closed
        pendingDescriptor = nil
        configuredDimensions = nil
        cleanKeyframeRequired = true
        acknowledgementReady = false
        pendingAcknowledgementMediaSequence = nil
    }

    private func requireCurrentFenceAndDimensions(
        _ header: MediaRecordHeader
    ) throws {
        guard matches(header, descriptor: currentDescriptor) else {
            throw ClientMediaStreamErrorV0.fenceMismatch
        }
        guard header.encodedWidth == currentDescriptor.encodedWidth,
              header.encodedHeight == currentDescriptor.encodedHeight else {
            throw ClientMediaStreamErrorV0.dimensionsMismatch
        }
    }

    private func matches(
        _ header: MediaRecordHeader,
        descriptor: AdaptiveSurfaceDescriptor
    ) -> Bool {
        header.interactiveSessionID == descriptor.interactiveSessionID
            && header.authorizationEpoch == descriptor.authorizationEpoch
            && header.surfaceID == descriptor.surfaceID
            && header.surfaceRevision == descriptor.surfaceRevision
            && header.coordinateSpaceRevision
                == descriptor.coordinateSpaceRevision
    }
}
