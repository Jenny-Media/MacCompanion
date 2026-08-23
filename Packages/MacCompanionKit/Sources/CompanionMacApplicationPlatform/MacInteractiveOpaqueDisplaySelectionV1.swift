#if os(macOS)
import CoreGraphics
import Foundation

public enum MacInteractiveOpaqueDisplaySelectionErrorV1:
    Error,
    Equatable,
    Sendable
{
    case unavailable
    case selectionMismatch
}

/// Menu-process-only ownership of the physical display identity. Other
/// modules receive only `opaqueSelectedDisplayID`; the `CGDirectDisplayID`
/// never enters Codable state, local XPC, logs, or UI presentation.
@available(macOS 14.0, *)
public final class MacInteractiveOpaqueDisplaySelectionV1:
    @unchecked Sendable
{
    private struct Selection {
        let opaqueID: UUID
        let physicalID: CGDirectDisplayID
    }

    private let lock = NSLock()
    private let isDisplayOnline: @Sendable (CGDirectDisplayID) -> Bool
    private var selection: Selection?

    public convenience init(
        identifier: @escaping @Sendable () -> UUID = { UUID() }
    ) throws {
        try self.init(
            physicalDisplayID: CGMainDisplayID(),
            opaqueID: identifier(),
            isDisplayOnline: { CGDisplayIsOnline($0) != 0 }
        )
    }

    package init(
        physicalDisplayID: CGDirectDisplayID,
        opaqueID: UUID,
        isDisplayOnline: @escaping @Sendable (CGDirectDisplayID) -> Bool
    ) throws {
        guard physicalDisplayID != 0,
              isDisplayOnline(physicalDisplayID) else {
            throw MacInteractiveOpaqueDisplaySelectionErrorV1.unavailable
        }
        self.isDisplayOnline = isDisplayOnline
        selection = Selection(
            opaqueID: opaqueID,
            physicalID: physicalDisplayID
        )
    }

    /// Returns nil after exact display loss and permanently discards the
    /// mapping. It never silently selects a replacement display.
    public func opaqueSelectedDisplayID() -> UUID? {
        lock.withLock {
            guard let selection else { return nil }
            guard isDisplayOnline(selection.physicalID) else {
                self.selection = nil
                return nil
            }
            return selection.opaqueID
        }
    }

    /// Package-only resolution for later concrete capture/input adapters in
    /// this platform target. Exact opaque mismatch and display loss are closed.
    package func resolvePhysicalDisplayID(
        selectedDisplayID: UUID
    ) throws -> CGDirectDisplayID {
        try lock.withLock {
            guard let selection else {
                throw MacInteractiveOpaqueDisplaySelectionErrorV1.unavailable
            }
            guard selection.opaqueID == selectedDisplayID else {
                throw MacInteractiveOpaqueDisplaySelectionErrorV1
                    .selectionMismatch
            }
            guard isDisplayOnline(selection.physicalID) else {
                self.selection = nil
                throw MacInteractiveOpaqueDisplaySelectionErrorV1.unavailable
            }
            return selection.physicalID
        }
    }

    package func invalidate() {
        lock.withLock { selection = nil }
    }
}
#endif
