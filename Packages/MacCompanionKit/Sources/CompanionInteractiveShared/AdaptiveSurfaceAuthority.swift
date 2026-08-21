import CompanionDomain
import Foundation

public enum SurfaceRevisionTag: Sendable {}
public enum CoordinateSpaceRevisionTag: Sendable {}
public enum FocusRevisionTag: Sendable {}

public typealias SurfaceRevision = MonotonicRevision<SurfaceRevisionTag>
public typealias CoordinateSpaceRevision = MonotonicRevision<CoordinateSpaceRevisionTag>
public typealias FocusRevision = MonotonicRevision<FocusRevisionTag>

public enum InteractiveSurfaceKind: String, Codable, CaseIterable, Sendable {
    case desktop
    case application
    case window
    case focusedRegion
}

public enum SurfaceInteractionClass: String, Codable, CaseIterable, Sendable {
    case view
    case pointer
    case keyboard
    case text
}

public enum SurfacePrivacyProfile: String, Codable, CaseIterable, Sendable {
    case visualOnly
    case assistedVisual
    case secureOpaque
}

public enum SurfaceMetadataField: String, Codable, CaseIterable, Sendable {
    case applicationName
    case applicationIcon
    case windowCount
    case genericWindowOrdinal
    case currentWindowAvailable
    case focusCategory
    case focusBounds
    case editable
    case secure
}

public enum FocusElementCategory: String, Codable, CaseIterable, Sendable {
    case text
    case button
    case list
    case dialog
    case unknown
}

public enum SurfaceRotation: UInt16, Codable, CaseIterable, Sendable {
    case degrees0 = 0
    case degrees90 = 90
    case degrees180 = 180
    case degrees270 = 270
}

public struct NormalizedSurfaceRect: Codable, Equatable, Sendable {
    public let x: UInt16
    public let y: UInt16
    public let width: UInt16
    public let height: UInt16

    public init(x: UInt16, y: UInt16, width: UInt16, height: UInt16) throws {
        guard width > 0, height > 0,
              UInt32(x) + UInt32(width) <= UInt32(UInt16.max),
              UInt32(y) + UInt32(height) <= UInt32(UInt16.max) else {
            throw AdaptiveSurfaceError.invalidDescriptor
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct SurfaceFocus: Codable, Equatable, Sendable {
    public let token: UUID
    public let revision: FocusRevision
    public let category: FocusElementCategory
    public let bounds: NormalizedSurfaceRect
    public let editable: Bool
    public let secure: Bool

    public init(
        token: UUID,
        revision: FocusRevision,
        category: FocusElementCategory,
        bounds: NormalizedSurfaceRect,
        editable: Bool,
        secure: Bool
    ) throws {
        guard revision.rawValue >= 1 else { throw AdaptiveSurfaceError.invalidDescriptor }
        self.token = token
        self.revision = revision
        self.category = category
        self.bounds = bounds
        self.editable = editable
        self.secure = secure
    }
}

public struct AdaptiveSurfaceDescriptor: Codable, Equatable, Sendable {
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let surfaceID: UUID
    public let kind: InteractiveSurfaceKind
    public let surfaceRevision: SurfaceRevision
    public let coordinateSpaceRevision: CoordinateSpaceRevision
    public let applicationToken: UUID?
    public let windowToken: UUID?
    public let parentSurfaceID: UUID?
    public let fallbackSurfaceID: UUID?
    public let encodedWidth: UInt16
    public let encodedHeight: UInt16
    public let logicalWidthPoints: UInt32
    public let logicalHeightPoints: UInt32
    public let rotation: SurfaceRotation
    public let interactionClasses: [SurfaceInteractionClass]
    public let privacyProfile: SurfacePrivacyProfile
    public let metadataFields: [SurfaceMetadataField]
    public let focus: SurfaceFocus?
    public let createdAtMonotonicMilliseconds: Int64
    public let expiresAtMonotonicMilliseconds: Int64

    public init(
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        surfaceID: UUID,
        kind: InteractiveSurfaceKind,
        surfaceRevision: SurfaceRevision,
        coordinateSpaceRevision: CoordinateSpaceRevision,
        applicationToken: UUID? = nil,
        windowToken: UUID? = nil,
        parentSurfaceID: UUID? = nil,
        fallbackSurfaceID: UUID? = nil,
        encodedWidth: UInt16,
        encodedHeight: UInt16,
        logicalWidthPoints: UInt32,
        logicalHeightPoints: UInt32,
        rotation: SurfaceRotation = .degrees0,
        interactionClasses: Set<SurfaceInteractionClass>,
        privacyProfile: SurfacePrivacyProfile,
        metadataFields: Set<SurfaceMetadataField>,
        focus: SurfaceFocus? = nil,
        createdAtMonotonicMilliseconds: Int64,
        expiresAtMonotonicMilliseconds: Int64
    ) throws {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.surfaceID = surfaceID
        self.kind = kind
        self.surfaceRevision = surfaceRevision
        self.coordinateSpaceRevision = coordinateSpaceRevision
        self.applicationToken = applicationToken
        self.windowToken = windowToken
        self.parentSurfaceID = parentSurfaceID
        self.fallbackSurfaceID = fallbackSurfaceID
        self.encodedWidth = encodedWidth
        self.encodedHeight = encodedHeight
        self.logicalWidthPoints = logicalWidthPoints
        self.logicalHeightPoints = logicalHeightPoints
        self.rotation = rotation
        self.interactionClasses = interactionClasses.sorted { $0.rawValue < $1.rawValue }
        self.privacyProfile = privacyProfile
        self.metadataFields = metadataFields.sorted { $0.rawValue < $1.rawValue }
        self.focus = focus
        self.createdAtMonotonicMilliseconds = createdAtMonotonicMilliseconds
        self.expiresAtMonotonicMilliseconds = expiresAtMonotonicMilliseconds
        try validate()
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1,
              surfaceRevision.rawValue >= 1,
              coordinateSpaceRevision.rawValue >= 1,
              encodedWidth > 0, encodedWidth <= 1_920,
              encodedHeight > 0, encodedHeight <= 1_200,
              UInt64(encodedWidth) * UInt64(encodedHeight) <= 2_304_000,
              logicalWidthPoints > 0, logicalHeightPoints > 0,
              interactionClasses.contains(.view),
              interactionClasses == interactionClasses.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(interactionClasses).count == interactionClasses.count,
              metadataFields == metadataFields.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(metadataFields).count == metadataFields.count,
              createdAtMonotonicMilliseconds >= 0,
              expiresAtMonotonicMilliseconds > createdAtMonotonicMilliseconds,
              parentSurfaceID != surfaceID,
              fallbackSurfaceID != surfaceID else {
            throw AdaptiveSurfaceError.invalidDescriptor
        }

        let allowedMetadata: Set<SurfaceMetadataField>
        switch kind {
        case .desktop:
            guard applicationToken == nil, windowToken == nil,
                  parentSurfaceID == nil, fallbackSurfaceID == nil,
                  focus == nil, privacyProfile == .visualOnly else {
                throw AdaptiveSurfaceError.invalidDescriptor
            }
            allowedMetadata = []
        case .application:
            guard applicationToken != nil, windowToken == nil, focus == nil,
                  privacyProfile == .visualOnly else {
                throw AdaptiveSurfaceError.invalidDescriptor
            }
            allowedMetadata = [.applicationName, .applicationIcon, .windowCount, .currentWindowAvailable]
        case .window:
            guard applicationToken != nil, windowToken != nil, focus == nil,
                  privacyProfile == .visualOnly else {
                throw AdaptiveSurfaceError.invalidDescriptor
            }
            allowedMetadata = [.applicationName, .applicationIcon, .genericWindowOrdinal]
        case .focusedRegion:
            guard applicationToken != nil, parentSurfaceID != nil,
                  fallbackSurfaceID != nil, let focus else {
                throw AdaptiveSurfaceError.invalidDescriptor
            }
            if focus.secure {
                guard privacyProfile == .secureOpaque else {
                    throw AdaptiveSurfaceError.invalidDescriptor
                }
            } else {
                guard privacyProfile == .assistedVisual else {
                    throw AdaptiveSurfaceError.invalidDescriptor
                }
            }
            allowedMetadata = [.focusCategory, .focusBounds, .editable, .secure]
        }
        guard Set(metadataFields).isSubset(of: allowedMetadata) else {
            throw AdaptiveSurfaceError.forbiddenMetadata
        }
    }
}

public struct SurfaceInputFence: Equatable, Sendable {
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let surfaceID: UUID
    public let surfaceRevision: SurfaceRevision
    public let coordinateSpaceRevision: CoordinateSpaceRevision
    public let focusToken: UUID?
    public let focusRevision: FocusRevision?

    public init(
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        surfaceID: UUID,
        surfaceRevision: SurfaceRevision,
        coordinateSpaceRevision: CoordinateSpaceRevision,
        focusToken: UUID? = nil,
        focusRevision: FocusRevision? = nil
    ) {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.coordinateSpaceRevision = coordinateSpaceRevision
        self.focusToken = focusToken
        self.focusRevision = focusRevision
    }
}

public enum SurfaceFallbackReason: String, Codable, CaseIterable, Sendable {
    case sourceUnavailable
    case modalRelationshipAmbiguous
    case accessibilityUnavailable
    case focusStale
    case transformInconsistent
}

public enum AdaptiveSurfacePhase: Equatable, Sendable {
    case active(AdaptiveSurfaceDescriptor)
    case switching(from: AdaptiveSurfaceDescriptor, target: AdaptiveSurfaceDescriptor)
    case fallbackPending(
        from: AdaptiveSurfaceDescriptor,
        target: AdaptiveSurfaceDescriptor,
        reason: SurfaceFallbackReason
    )
    case awaitingAcknowledgement(AdaptiveSurfaceDescriptor)
    case suspended
    case ended
}

public enum AdaptiveSurfaceEffect: String, Codable, CaseIterable, Sendable {
    case pauseInput
    case releaseAllInput
    case applyCaptureSource
    case emitVideoDiscontinuity
    case publishDescriptor
    case requestCleanKeyframe
    case resumeInput
    case invalidateAllTokens
    case stopCapture
}

public enum AdaptiveSurfaceError: Error, Equatable, Sendable {
    case invalidDescriptor
    case forbiddenMetadata
    case staleSurface
    case staleCoordinateSpace
    case staleFocus
    case authorizationChanged
    case wrongSession
    case transitionInProgress
    case notActive
    case expired
}

public struct AdaptiveSurfaceAuthority: Equatable, Sendable {
    public private(set) var phase: AdaptiveSurfacePhase

    public init(
        desktop: AdaptiveSurfaceDescriptor,
        monotonicNowMilliseconds: Int64
    ) throws {
        try desktop.validate()
        guard desktop.kind == .desktop else { throw AdaptiveSurfaceError.invalidDescriptor }
        try Self.validateLifetime(desktop, monotonicNowMilliseconds: monotonicNowMilliseconds)
        phase = .active(desktop)
    }

    public mutating func requestSelection(
        target: AdaptiveSurfaceDescriptor,
        expectedSurfaceRevision: SurfaceRevision,
        expectedCoordinateSpaceRevision: CoordinateSpaceRevision,
        monotonicNowMilliseconds: Int64
    ) throws -> [AdaptiveSurfaceEffect] {
        guard case let .active(current) = phase else {
            throw AdaptiveSurfaceError.transitionInProgress
        }
        try validateClientExpectation(
            current: current,
            surface: expectedSurfaceRevision,
            coordinate: expectedCoordinateSpaceRevision
        )
        try Self.validateLifetime(current, monotonicNowMilliseconds: monotonicNowMilliseconds)
        try validateSuccessor(current: current, target: target)
        try Self.validateLifetime(target, monotonicNowMilliseconds: monotonicNowMilliseconds)
        phase = .switching(from: current, target: target)
        return [.pauseInput, .releaseAllInput, .applyCaptureSource]
    }

    public mutating func beginFallback(
        target: AdaptiveSurfaceDescriptor,
        reason: SurfaceFallbackReason,
        monotonicNowMilliseconds: Int64
    ) throws -> [AdaptiveSurfaceEffect] {
        let current = try latestDescriptor()
        try Self.validateLifetime(current, monotonicNowMilliseconds: monotonicNowMilliseconds)
        try validateSuccessor(current: current, target: target)
        try Self.validateLifetime(target, monotonicNowMilliseconds: monotonicNowMilliseconds)
        phase = .fallbackPending(from: current, target: target, reason: reason)
        return [.pauseInput, .releaseAllInput, .applyCaptureSource]
    }

    public mutating func executorCommitted(
        descriptor: AdaptiveSurfaceDescriptor,
        monotonicNowMilliseconds: Int64
    ) throws -> [AdaptiveSurfaceEffect] {
        let target: AdaptiveSurfaceDescriptor
        switch phase {
        case let .switching(_, expected), let .fallbackPending(_, expected, _):
            target = expected
        default:
            throw AdaptiveSurfaceError.notActive
        }
        guard descriptor == target else { throw AdaptiveSurfaceError.invalidDescriptor }
        try Self.validateLifetime(descriptor, monotonicNowMilliseconds: monotonicNowMilliseconds)
        phase = .awaitingAcknowledgement(descriptor)
        return [.emitVideoDiscontinuity, .publishDescriptor, .requestCleanKeyframe]
    }

    public mutating func acknowledge(
        _ fence: SurfaceInputFence,
        monotonicNowMilliseconds: Int64
    ) throws -> [AdaptiveSurfaceEffect] {
        guard case let .awaitingAcknowledgement(descriptor) = phase else {
            throw AdaptiveSurfaceError.notActive
        }
        try Self.validateLifetime(descriptor, monotonicNowMilliseconds: monotonicNowMilliseconds)
        try validateFence(
            fence,
            descriptor: descriptor,
            requireFocus: descriptor.focus != nil
        )
        phase = .active(descriptor)
        return [.resumeInput]
    }

    public func validateInput(
        _ fence: SurfaceInputFence,
        requiresFocusBinding: Bool,
        monotonicNowMilliseconds: Int64
    ) throws {
        guard case let .active(descriptor) = phase else {
            throw AdaptiveSurfaceError.notActive
        }
        try Self.validateLifetime(descriptor, monotonicNowMilliseconds: monotonicNowMilliseconds)
        try validateFence(fence, descriptor: descriptor, requireFocus: requiresFocusBinding)
    }

    public mutating func suspend() throws -> [AdaptiveSurfaceEffect] {
        guard phase.isOperable else { throw AdaptiveSurfaceError.notActive }
        phase = .suspended
        return [.pauseInput, .releaseAllInput, .invalidateAllTokens, .stopCapture]
    }

    public mutating func end() throws -> [AdaptiveSurfaceEffect] {
        guard phase != .ended else { throw AdaptiveSurfaceError.notActive }
        phase = .ended
        return [.pauseInput, .releaseAllInput, .invalidateAllTokens, .stopCapture]
    }

    private func latestDescriptor() throws -> AdaptiveSurfaceDescriptor {
        switch phase {
        case let .active(value), let .awaitingAcknowledgement(value):
            value
        case let .switching(_, target), let .fallbackPending(_, target, _):
            target
        case .suspended, .ended:
            throw AdaptiveSurfaceError.notActive
        }
    }

    private func validateClientExpectation(
        current: AdaptiveSurfaceDescriptor,
        surface: SurfaceRevision,
        coordinate: CoordinateSpaceRevision
    ) throws {
        guard surface == current.surfaceRevision else { throw AdaptiveSurfaceError.staleSurface }
        guard coordinate == current.coordinateSpaceRevision else {
            throw AdaptiveSurfaceError.staleCoordinateSpace
        }
    }

    private func validateSuccessor(
        current: AdaptiveSurfaceDescriptor,
        target: AdaptiveSurfaceDescriptor
    ) throws {
        try target.validate()
        guard target.interactiveSessionID == current.interactiveSessionID else {
            throw AdaptiveSurfaceError.wrongSession
        }
        guard target.authorizationEpoch == current.authorizationEpoch else {
            throw AdaptiveSurfaceError.authorizationChanged
        }
        guard target.surfaceRevision == (try current.surfaceRevision.advanced()),
              target.coordinateSpaceRevision == (try current.coordinateSpaceRevision.advanced()) else {
            throw AdaptiveSurfaceError.invalidDescriptor
        }
    }

    private func validateFence(
        _ fence: SurfaceInputFence,
        descriptor: AdaptiveSurfaceDescriptor,
        requireFocus: Bool
    ) throws {
        guard fence.interactiveSessionID == descriptor.interactiveSessionID else {
            throw AdaptiveSurfaceError.wrongSession
        }
        guard fence.authorizationEpoch == descriptor.authorizationEpoch else {
            throw AdaptiveSurfaceError.authorizationChanged
        }
        guard fence.surfaceID == descriptor.surfaceID,
              fence.surfaceRevision == descriptor.surfaceRevision else {
            throw AdaptiveSurfaceError.staleSurface
        }
        guard fence.coordinateSpaceRevision == descriptor.coordinateSpaceRevision else {
            throw AdaptiveSurfaceError.staleCoordinateSpace
        }
        if requireFocus {
            guard let focus = descriptor.focus,
                  fence.focusToken == focus.token,
                  fence.focusRevision == focus.revision else {
                throw AdaptiveSurfaceError.staleFocus
            }
        } else if fence.focusToken != nil || fence.focusRevision != nil {
            guard let focus = descriptor.focus,
                  fence.focusToken == focus.token,
                  fence.focusRevision == focus.revision else {
                throw AdaptiveSurfaceError.staleFocus
            }
        }
    }

    private static func validateLifetime(
        _ descriptor: AdaptiveSurfaceDescriptor,
        monotonicNowMilliseconds: Int64
    ) throws {
        guard monotonicNowMilliseconds >= descriptor.createdAtMonotonicMilliseconds,
              monotonicNowMilliseconds < descriptor.expiresAtMonotonicMilliseconds else {
            throw AdaptiveSurfaceError.expired
        }
    }
}

private extension AdaptiveSurfacePhase {
    var isOperable: Bool {
        switch self {
        case .active, .switching, .fallbackPending, .awaitingAcknowledgement:
            true
        case .suspended, .ended:
            false
        }
    }
}
