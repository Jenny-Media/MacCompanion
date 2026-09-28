import Foundation

/// Reuses the existing authenticated media binding without introducing a
/// second identity or approval representation. No native endpoint is trusted
/// by constructing this value; the current Control authority supplies it.
public typealias InteractiveNativeVideoBindingV0 = InteractiveWebRTCMediaBindingV0

public struct InteractiveNativeVideoSurfaceV0: Equatable, Sendable {
    public let surfaceID: UUID
    public let surfaceRevision: Int64
    public let coordinateSpaceRevision: Int64
    public let encodedWidth: Int
    public let encodedHeight: Int

    public init(surfaceID: UUID, surfaceRevision: Int64,
                coordinateSpaceRevision: Int64, encodedWidth: Int,
                encodedHeight: Int) throws {
        guard surfaceRevision > 0, coordinateSpaceRevision > 0,
              (320...8192).contains(encodedWidth),
              (240...8192).contains(encodedHeight) else {
            throw InteractiveNativeVideoFailureV0.invalidSurface
        }
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.coordinateSpaceRevision = coordinateSpaceRevision
        self.encodedWidth = encodedWidth
        self.encodedHeight = encodedHeight
    }
}

public enum InteractiveNativeVideoFailureV0: Error, Equatable, Sendable {
    case invalidSurface
    case authorizationLost
    case expired
    case connectionFailed
    case incompatibleFrame
    case generationExhausted
}

public enum InteractiveNativeVideoPhaseV0: String, Sendable {
    case idle, connecting, connected, displaying, failed, draining, retired
}

/// Local lifecycle only. A displayed frame never creates an input grant or
/// substitutes for the existing host's clean-frame acknowledgement.
public struct InteractiveNativeVideoLifecycleV0: Sendable {
    public let binding: InteractiveNativeVideoBindingV0
    public let surface: InteractiveNativeVideoSurfaceV0
    public private(set) var generation: UInt64 = 0
    public private(set) var phase: InteractiveNativeVideoPhaseV0 = .idle
    public private(set) var failure: InteractiveNativeVideoFailureV0?
    public private(set) var requiresDrain = false
    public private(set) var isTerminal = false

    private var inputAdmitted = false
    public var allowsInput: Bool { inputAdmitted && phase == .displaying && !isTerminal }

    /// Local current-owner handoff after the correlated host receipt and
    /// geometry have been verified. A frame alone never calls this method.
    @discardableResult
    public mutating func admitInput(generation candidate: UInt64, surface candidateSurface: InteractiveNativeVideoSurfaceV0,
        current: InteractiveNativeVideoBindingV0, nowMonotonicMilliseconds now: UInt64) -> Bool {
        guard phase == .displaying, candidateSurface == surface,
              admit(candidate, current: current, now: now) else { return false }
        inputAdmitted = true
        return true
    }

    public init(binding: InteractiveNativeVideoBindingV0,
                surface: InteractiveNativeVideoSurfaceV0) {
        self.binding = binding
        self.surface = surface
    }

    /// A connection failure permits an explicit retry only after native drain,
    /// under the original approval/deadline. Stop and authority loss do not.
    public mutating func begin(current: InteractiveNativeVideoBindingV0,
                               nowMonotonicMilliseconds now: UInt64) -> UInt64? {
        guard revalidate(current: current, nowMonotonicMilliseconds: now),
              !requiresDrain, phase == .idle || phase == .retired else { return nil }
        guard generation < UInt64.max else {
            retire(.generationExhausted)
            return nil
        }
        inputAdmitted = false
        generation += 1
        requiresDrain = true
        phase = .connecting
        failure = nil
        return generation
    }

    @discardableResult
    public mutating func connected(generation candidate: UInt64,
                                  current: InteractiveNativeVideoBindingV0,
                                  nowMonotonicMilliseconds now: UInt64) -> Bool {
        guard admit(candidate, current: current, now: now), phase == .connecting else { return false }
        phase = .connected
        return true
    }

    @discardableResult
    public mutating func frame(generation candidate: UInt64,
                              surface candidateSurface: InteractiveNativeVideoSurfaceV0,
                              current: InteractiveNativeVideoBindingV0,
                              nowMonotonicMilliseconds now: UInt64) -> Bool {
        guard admit(candidate, current: current, now: now),
              phase == .connected || phase == .displaying else { return false }
        guard candidateSurface == surface else {
            retire(.incompatibleFrame)
            return false
        }
        phase = .displaying
        return true
    }

    @discardableResult
    public mutating func connectionFailed(generation candidate: UInt64,
                                         current: InteractiveNativeVideoBindingV0,
                                         nowMonotonicMilliseconds now: UInt64) -> Bool {
        guard admit(candidate, current: current, now: now) else { return false }
        inputAdmitted = false
        phase = .failed
        failure = .connectionFailed
        return true
    }

    /// Call before revealing video or while waiting without callbacks. The
    /// caller must fetch `current` from its authoritative owner every time.
    @discardableResult
    public mutating func revalidate(current: InteractiveNativeVideoBindingV0,
                                    nowMonotonicMilliseconds now: UInt64) -> Bool {
        guard !isTerminal else { return false }
        guard current == binding else { retire(.authorizationLost); return false }
        guard now < binding.expiresAtMonotonicMilliseconds else { retire(.expired); return false }
        return true
    }

    public mutating func stop() {
        inputAdmitted = false
        isTerminal = true
        phase = requiresDrain ? .draining : .retired
    }

    public mutating func authorizationLost() { retire(.authorizationLost) }

    /// Only the native owner calls this after sockets and callbacks have
    /// drained. A stale completion cannot release a replacement generation.
    @discardableResult
    public mutating func drained(generation candidate: UInt64) -> Bool {
        guard candidate == generation, requiresDrain,
              phase == .failed || phase == .draining else { return false }
        inputAdmitted = false
        requiresDrain = false
        phase = .retired
        return true
    }

    private mutating func admit(_ candidate: UInt64,
                               current: InteractiveNativeVideoBindingV0,
                               now: UInt64) -> Bool {
        // Old callbacks must not mutate or retire the new generation.
        guard candidate == generation, requiresDrain,
              phase == .connecting || phase == .connected || phase == .displaying else { return false }
        return revalidate(current: current, nowMonotonicMilliseconds: now)
    }

    private mutating func retire(_ reason: InteractiveNativeVideoFailureV0) {
        inputAdmitted = false
        isTerminal = true
        failure = reason
        phase = .failed
    }
}
