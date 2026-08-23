#if os(macOS)
import ApplicationServices
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CoreGraphics
import Foundation

public enum MacAccessibilityFocusReadResultV0: Equatable, Sendable {
    case verified(MacAccessibilityFocusObservationV0)
    case unavailable(InteractiveFocusEventReasonV0)
}

public struct MacAccessibilityFocusObservationV0: Equatable, Sendable {
    public let category: FocusElementCategory
    public let globalBounds: CGRect
    public let editable: Bool
    public let secure: Bool

    public init(
        category: FocusElementCategory,
        globalBounds: CGRect,
        editable: Bool,
        secure: Bool
    ) {
        self.category = category
        self.globalBounds = globalBounds
        self.editable = editable
        self.secure = secure
    }
}

public protocol MacAccessibilityFocusReadingV0: Sendable {
    func readCurrentFocus() -> MacAccessibilityFocusReadResultV0
}

/// Live, read-only AX adapter. Raw role/subrole strings are collapsed into the
/// closed category inside this call and are never retained or serialized.
/// Labels, values, selections, titles, descriptions, and identifiers are not
/// requested.
public struct SystemMacAccessibilityFocusReaderV0:
    MacAccessibilityFocusReadingV0
{
    public init() {}

    public func readCurrentFocus() -> MacAccessibilityFocusReadResultV0 {
        guard AXIsProcessTrusted() else {
            return .unavailable(.accessibilityUnavailable)
        }
        let system = AXUIElementCreateSystemWide()
        guard let focusedValue = Self.copy(
            kAXFocusedUIElementAttribute,
            from: system
        ), CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return .unavailable(.noVerifiedFocus)
        }
        let focused = unsafeDowncast(focusedValue, to: AXUIElement.self)
        guard let role = Self.copyString(kAXRoleAttribute, from: focused),
              let position = Self.copyPoint(
                kAXPositionAttribute,
                from: focused
              ),
              let size = Self.copySize(kAXSizeAttribute, from: focused),
              position.x.isFinite, position.y.isFinite,
              size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else {
            return .unavailable(.ambiguousGeometry)
        }
        let subrole = Self.copyString(kAXSubroleAttribute, from: focused)
        guard !Self.isSystemSurface(role: role) else {
            return .unavailable(.systemSurface)
        }
        var valueSettable = DarwinBoolean(false)
        let editable = AXUIElementIsAttributeSettable(
            focused,
            kAXValueAttribute as CFString,
            &valueSettable
        ) == .success && valueSettable.boolValue
        return .verified(MacAccessibilityFocusObservationV0(
            category: Self.category(for: role, subrole: subrole),
            globalBounds: CGRect(origin: position, size: size),
            editable: editable,
            secure: subrole == kAXSecureTextFieldSubrole
        ))
    }

    private static func copy(
        _ attribute: String,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else { return nil }
        return value
    }

    private static func copyString(
        _ attribute: String,
        from element: AXUIElement
    ) -> String? {
        copy(attribute, from: element) as? String
    }

    private static func copyPoint(
        _ attribute: String,
        from element: AXUIElement
    ) -> CGPoint? {
        guard let value = copy(attribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private static func copySize(
        _ attribute: String,
        from element: AXUIElement
    ) -> CGSize? {
        guard let value = copy(attribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private static func category(for role: String, subrole: String?)
        -> FocusElementCategory
    {
        if subrole == kAXDialogSubrole
            || subrole == kAXSystemDialogSubrole
        {
            return .dialog
        }
        switch role {
        case kAXTextFieldRole,
             kAXTextAreaRole,
             kAXComboBoxRole:
            return .text
        case kAXButtonRole:
            return .button
        case kAXListRole,
             kAXTableRole,
             kAXOutlineRole:
            return .list
        case kAXSheetRole:
            return .dialog
        default:
            return .unknown
        }
    }

    private static func isSystemSurface(role: String) -> Bool {
        switch role {
        case kAXApplicationRole,
             kAXMenuBarRole,
             kAXMenuRole:
            true
        default:
            false
        }
    }
}

public enum MacAccessibilityFocusProjectionErrorV0:
    Error, Equatable, Sendable
{
    case invalidGeometry
}

/// Converts one already privacy-filtered local observation into the closed
/// wire-safe focus candidate. Both rectangles must use the same global point
/// coordinate space; partially clipped or ambiguous geometry falls back.
public struct MacAccessibilityFocusProjectorV0: Sendable {
    public init() {}

    public func project(
        _ result: MacAccessibilityFocusReadResultV0,
        currentSurfaceGlobalBounds: CGRect,
        focusToken: UUID,
        focusRevision: FocusRevision,
        inputPaused: Bool,
        validForMilliseconds: Int64 = 1_000
    ) throws -> InteractiveFocusEventCandidateV0 {
        guard Self.isValid(currentSurfaceGlobalBounds) else {
            throw MacAccessibilityFocusProjectionErrorV0.invalidGeometry
        }
        switch result {
        case let .unavailable(reason):
            return try InteractiveFocusEventCandidateV0(
                recommendedTargetKind: .desktop,
                focus: nil,
                inputPaused: inputPaused,
                reason: reason,
                validForMilliseconds: validForMilliseconds
            )
        case let .verified(observation):
            guard Self.isValid(observation.globalBounds),
                  currentSurfaceGlobalBounds.contains(
                    observation.globalBounds
                  ) else {
                return try InteractiveFocusEventCandidateV0(
                    recommendedTargetKind: .desktop,
                    focus: nil,
                    inputPaused: inputPaused,
                    reason: .ambiguousGeometry,
                    validForMilliseconds: validForMilliseconds
                )
            }
            let normalized = try Self.normalize(
                observation.globalBounds,
                within: currentSurfaceGlobalBounds
            )
            return try InteractiveFocusEventCandidateV0(
                recommendedTargetKind: .focusedRegion,
                focus: try SurfaceFocus(
                    token: focusToken,
                    revision: focusRevision,
                    category: observation.category,
                    bounds: normalized,
                    editable: observation.editable,
                    secure: observation.secure
                ),
                inputPaused: inputPaused,
                reason: .verifiedFocus,
                validForMilliseconds: validForMilliseconds
            )
        }
    }

    private static func normalize(
        _ focus: CGRect,
        within surface: CGRect
    ) throws -> NormalizedSurfaceRect {
        let scale = Double(UInt16.max)
        let x = Int(floor(
            (focus.minX - surface.minX) / surface.width * scale
        ))
        let y = Int(floor(
            (focus.minY - surface.minY) / surface.height * scale
        ))
        let maxX = Int(ceil(
            (focus.maxX - surface.minX) / surface.width * scale
        ))
        let maxY = Int(ceil(
            (focus.maxY - surface.minY) / surface.height * scale
        ))
        guard x >= 0, y >= 0, maxX <= Int(UInt16.max),
              maxY <= Int(UInt16.max), maxX > x, maxY > y else {
            throw MacAccessibilityFocusProjectionErrorV0.invalidGeometry
        }
        return try NormalizedSurfaceRect(
            x: UInt16(x),
            y: UInt16(y),
            width: UInt16(maxX - x),
            height: UInt16(maxY - y)
        )
    }

    private static func isValid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }
}
#endif
