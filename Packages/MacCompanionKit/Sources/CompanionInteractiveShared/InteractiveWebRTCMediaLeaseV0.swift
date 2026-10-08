import Foundation

/// A local admission fence for a candidate WebRTC media peer. The caller must
/// obtain `current` from the authenticated primary and Control authorities on
/// every call; peer or signaling data is never an authority source.
public struct InteractiveWebRTCMediaBindingV0: Equatable, Sendable {
    public let hostID: UUID
    public let hostFingerprint: Data
    public let clientID: UUID
    public let primaryConnectionID: Data
    public let interactiveSessionID: UUID
    public let authorizationEpoch: Int64
    public let grantRevision: Int64
    public let policyRevision: Int64
    public let controlGeneration: UUID
    public let expiresAtMonotonicMilliseconds: UInt64

    public init(
        hostID: UUID, hostFingerprint: Data, clientID: UUID,
        primaryConnectionID: Data, interactiveSessionID: UUID,
        authorizationEpoch: Int64, grantRevision: Int64,
        policyRevision: Int64, controlGeneration: UUID,
        expiresAtMonotonicMilliseconds: UInt64
    ) throws {
        guard hostFingerprint.count == 32, primaryConnectionID.count == 16,
              authorizationEpoch > 0, grantRevision > 0, policyRevision > 0,
              expiresAtMonotonicMilliseconds > 0 else {
            throw InteractiveWebRTCMediaLeaseErrorV0.invalidBinding
        }
        self.hostID = hostID
        self.hostFingerprint = hostFingerprint
        self.clientID = clientID
        self.primaryConnectionID = primaryConnectionID
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.controlGeneration = controlGeneration
        self.expiresAtMonotonicMilliseconds = expiresAtMonotonicMilliseconds
    }
}

public enum InteractiveWebRTCMediaLeaseErrorV0: Error, Equatable, Sendable {
    case invalidBinding
}

public struct InteractiveWebRTCMediaSurfaceFenceV0: Equatable, Sendable {
    public let surfaceID: UUID
    public let surfaceRevision: Int64
    public let coordinateSpaceRevision: Int64

    public init(surfaceID: UUID, surfaceRevision: Int64,
                coordinateSpaceRevision: Int64) throws {
        guard surfaceRevision > 0, coordinateSpaceRevision > 0 else {
            throw InteractiveWebRTCMediaLeaseErrorV0.invalidBinding
        }
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.coordinateSpaceRevision = coordinateSpaceRevision
    }
}

/// No WebRTC dependency or network transport is admitted by this state owner.
/// The generation is local and is never supplied by an SDP or ICE payload.
public struct InteractiveWebRTCMediaLeaseV0: Sendable {
    public let binding: InteractiveWebRTCMediaBindingV0
    public private(set) var peerGeneration: UInt64 = 0
    public private(set) var isClosed = false
    public private(set) var isPresenting = false
    public private(set) var currentSurface: InteractiveWebRTCMediaSurfaceFenceV0?

    private var offerID: UUID?
    private var answerID: UUID?
    private var iceIDs: Set<UUID> = []

    public init(binding: InteractiveWebRTCMediaBindingV0) {
        self.binding = binding
    }

    @discardableResult
    public mutating func beginPeer(
        current: InteractiveWebRTCMediaBindingV0,
        nowMonotonicMilliseconds: UInt64
    ) -> UInt64? {
        guard revalidate(current: current, now: nowMonotonicMilliseconds),
              peerGeneration < UInt64.max else {
            close()
            return nil
        }
        peerGeneration += 1
        clearPeer()
        return peerGeneration
    }

    public mutating func admitOffer(
        _ messageID: UUID, peer: UInt64,
        current: InteractiveWebRTCMediaBindingV0,
        nowMonotonicMilliseconds: UInt64
    ) -> Bool {
        guard admit(peer: peer, current: current, now: nowMonotonicMilliseconds),
              offerID == nil else { return false }
        offerID = messageID
        return true
    }

    public mutating func admitAnswer(
        _ messageID: UUID, respondingTo offeredID: UUID, peer: UInt64,
        current: InteractiveWebRTCMediaBindingV0,
        nowMonotonicMilliseconds: UInt64
    ) -> Bool {
        guard admit(peer: peer, current: current, now: nowMonotonicMilliseconds),
              offerID == offeredID, answerID == nil,
              messageID != offeredID else { return false }
        answerID = messageID
        return true
    }

    public mutating func admitICE(
        _ messageID: UUID, peer: UInt64,
        current: InteractiveWebRTCMediaBindingV0,
        nowMonotonicMilliseconds: UInt64
    ) -> Bool {
        guard admit(peer: peer, current: current, now: nowMonotonicMilliseconds),
              offerID != nil, iceIDs.count < 256,
              !iceIDs.contains(messageID),
              messageID != offerID, messageID != answerID else { return false }
        iceIDs.insert(messageID)
        return true
    }

    public mutating func admitFrame(
        peer: UInt64, surface: InteractiveWebRTCMediaSurfaceFenceV0,
        current: InteractiveWebRTCMediaBindingV0,
        nowMonotonicMilliseconds: UInt64
    ) -> Bool {
        guard admit(peer: peer, current: current, now: nowMonotonicMilliseconds),
              answerID != nil, surface == currentSurface else { return false }
        isPresenting = true
        return true
    }

    /// `surface` must come from the current acknowledged Control descriptor.
    /// A replacement surface blanks output until its own frames arrive.
    public mutating func setCurrentSurface(
        _ surface: InteractiveWebRTCMediaSurfaceFenceV0,
        current: InteractiveWebRTCMediaBindingV0,
        nowMonotonicMilliseconds: UInt64
    ) -> Bool {
        guard revalidate(current: current, now: nowMonotonicMilliseconds) else {
            return false
        }
        if surface != currentSurface { isPresenting = false }
        currentSurface = surface
        return true
    }

    /// Backgrounding invalidates callbacks from the old peer. Foreground
    /// return must explicitly call `beginPeer` under the original deadline.
    public mutating func background() {
        guard !isClosed else { return }
        if peerGeneration == UInt64.max { close(); return }
        peerGeneration += 1
        clearPeer()
    }

    /// Stop, expiry, revocation, and primary loss all end the same lease.
    public mutating func close() {
        isClosed = true
        clearPeer()
        currentSurface = nil
    }

    private mutating func admit(
        peer: UInt64, current: InteractiveWebRTCMediaBindingV0,
        now: UInt64
    ) -> Bool {
        guard revalidate(current: current, now: now) else { return false }
        return peer > 0 && peer == peerGeneration
    }

    private mutating func revalidate(
        current: InteractiveWebRTCMediaBindingV0, now: UInt64
    ) -> Bool {
        guard !isClosed else { return false }
        guard current == binding,
              now < binding.expiresAtMonotonicMilliseconds else {
            close()
            return false
        }
        return true
    }

    private mutating func clearPeer() {
        offerID = nil
        answerID = nil
        iceIDs.removeAll()
        isPresenting = false
    }
}
