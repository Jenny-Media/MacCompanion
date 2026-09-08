#if os(macOS)
import CoreGraphics
import Foundation

public enum MacInteractiveOpaqueDisplaySelectionErrorV1: Error, Equatable, Sendable {
    case unavailable
    case selectionMismatch
}

public struct MacInteractiveDisplayChoiceV1: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let layoutX: Int
    public let layoutY: Int
    public let layoutWidth: Int
    public let layoutHeight: Int
    public let isMain: Bool

    package init(
        id: UUID,
        name: String,
        pixelWidth: Int,
        pixelHeight: Int,
        layoutX: Int,
        layoutY: Int,
        layoutWidth: Int,
        layoutHeight: Int,
        isMain: Bool
    ) {
        self.id = id
        self.name = name
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.layoutX = layoutX
        self.layoutY = layoutY
        self.layoutWidth = layoutWidth
        self.layoutHeight = layoutHeight
        self.isMain = isMain
    }
}

/// Menu-process-only ownership of every online physical display identity.
/// Other modules receive only opaque IDs; physical IDs never enter Codable
/// state, local XPC, logs, or UI presentation.
@available(macOS 14.0, *)
public final class MacInteractiveOpaqueDisplaySelectionV1: @unchecked Sendable {
    package struct PhysicalDisplay: Equatable, Sendable {
        package let id: CGDirectDisplayID
        package let pixelWidth: Int
        package let pixelHeight: Int
        package let layoutX: Int
        package let layoutY: Int
        package let layoutWidth: Int
        package let layoutHeight: Int
        package let isMain: Bool

        package init(
            id: CGDirectDisplayID,
            pixelWidth: Int,
            pixelHeight: Int,
            layoutX: Int = 0,
            layoutY: Int = 0,
            layoutWidth: Int? = nil,
            layoutHeight: Int? = nil,
            isMain: Bool
        ) {
            self.id = id
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.layoutX = layoutX
            self.layoutY = layoutY
            self.layoutWidth = layoutWidth ?? pixelWidth
            self.layoutHeight = layoutHeight ?? pixelHeight
            self.isMain = isMain
        }
    }

    private struct Entry {
        let opaqueID: UUID
        let physical: PhysicalDisplay
    }

    private let lock = NSLock()
    private let identifier: @Sendable () -> UUID
    private let onlineDisplays: @Sendable () -> [PhysicalDisplay]
    private var entries: [CGDirectDisplayID: Entry] = [:]
    private var selectedOpaqueID: UUID?

    public convenience init(
        identifier: @escaping @Sendable () -> UUID = { UUID() }
    ) throws {
        try self.init(
            identifier: identifier,
            onlineDisplays: Self.currentOnlineDisplays
        )
    }

    package convenience init(
        physicalDisplayID: CGDirectDisplayID,
        opaqueID: UUID,
        isDisplayOnline: @escaping @Sendable (CGDirectDisplayID) -> Bool
    ) throws {
        try self.init(
            identifier: { UUID() },
            initialOpaqueIDs: [physicalDisplayID: opaqueID],
            onlineDisplays: {
                guard physicalDisplayID != 0,
                      isDisplayOnline(physicalDisplayID) else { return [] }
                return [PhysicalDisplay(
                    id: physicalDisplayID,
                    pixelWidth: 1,
                    pixelHeight: 1,
                    layoutX: 0,
                    layoutY: 0,
                    layoutWidth: 1,
                    layoutHeight: 1,
                    isMain: true
                )]
            }
        )
    }

    package init(
        identifier: @escaping @Sendable () -> UUID = { UUID() },
        initialOpaqueIDs: [CGDirectDisplayID: UUID] = [:],
        onlineDisplays: @escaping @Sendable () -> [PhysicalDisplay]
    ) throws {
        self.identifier = identifier
        self.onlineDisplays = onlineDisplays
        let displays = Self.validated(onlineDisplays())
        guard let initial = displays.first(where: \.isMain)
                ?? displays.first else {
            throw MacInteractiveOpaqueDisplaySelectionErrorV1.unavailable
        }
        for display in displays {
            let opaqueID = initialOpaqueIDs[display.id] ?? identifier()
            entries[display.id] = Entry(opaqueID: opaqueID, physical: display)
        }
        selectedOpaqueID = entries[initial.id]?.opaqueID
    }

    public func availableDisplays() -> [MacInteractiveDisplayChoiceV1] {
        lock.withLock {
            refreshLocked()
            let ordered = Self.ordered(entries.values.map(\.physical))
            return ordered.enumerated().compactMap { index, display in
                guard let entry = entries[display.id] else { return nil }
                return MacInteractiveDisplayChoiceV1(
                    id: entry.opaqueID,
                    name: display.isMain
                        ? "Main Display" : "Display \(index + 1)",
                    pixelWidth: display.pixelWidth,
                    pixelHeight: display.pixelHeight,
                    layoutX: display.layoutX,
                    layoutY: display.layoutY,
                    layoutWidth: display.layoutWidth,
                    layoutHeight: display.layoutHeight,
                    isMain: display.isMain
                )
            }
        }
    }

    public func selectDisplay(id opaqueID: UUID) throws {
        try lock.withLock {
            refreshLocked()
            guard entries.values.contains(where: { $0.opaqueID == opaqueID })
            else {
                throw MacInteractiveOpaqueDisplaySelectionErrorV1.unavailable
            }
            selectedOpaqueID = opaqueID
        }
    }

    public func opaqueSelectedDisplayID() -> UUID? {
        lock.withLock {
            refreshLocked()
            return selectedOpaqueID
        }
    }

    package func resolvePhysicalDisplayID(
        selectedDisplayID: UUID
    ) throws -> CGDirectDisplayID {
        try lock.withLock {
            refreshLocked()
            guard selectedOpaqueID == selectedDisplayID else {
                throw MacInteractiveOpaqueDisplaySelectionErrorV1
                    .selectionMismatch
            }
            guard let entry = entries.values.first(where: {
                $0.opaqueID == selectedDisplayID
            }) else {
                throw MacInteractiveOpaqueDisplaySelectionErrorV1.unavailable
            }
            return entry.physical.id
        }
    }

    package func invalidate() {
        lock.withLock {
            entries.removeAll()
            selectedOpaqueID = nil
        }
    }

    private func refreshLocked() {
        let displays = Self.validated(onlineDisplays())
        let onlineIDs = Set(displays.map(\.id))
        entries = entries.filter { onlineIDs.contains($0.key) }
        for display in displays {
            if let existing = entries[display.id] {
                entries[display.id] = Entry(
                    opaqueID: existing.opaqueID,
                    physical: display
                )
            } else {
                entries[display.id] = Entry(
                    opaqueID: identifier(),
                    physical: display
                )
            }
        }
        if let selectedOpaqueID,
           !entries.values.contains(where: { $0.opaqueID == selectedOpaqueID }) {
            self.selectedOpaqueID = nil
        }
    }

    private static func validated(
        _ values: [PhysicalDisplay]
    ) -> [PhysicalDisplay] {
        let valid = values.filter {
            $0.id != 0
                && $0.pixelWidth > 0
                && $0.pixelHeight > 0
                && $0.layoutWidth > 0
                && $0.layoutHeight > 0
        }
        var seen: Set<CGDirectDisplayID> = []
        return ordered(valid.filter { seen.insert($0.id).inserted })
    }

    private static func ordered(
        _ values: [PhysicalDisplay]
    ) -> [PhysicalDisplay] {
        values.sorted {
            if $0.isMain != $1.isMain { return $0.isMain }
            return $0.id < $1.id
        }
    }

    private static func currentOnlineDisplays() -> [PhysicalDisplay] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success,
              count > 0 else { return [] }
        var ids = Array(repeating: CGDirectDisplayID(0), count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return []
        }
        return ids.prefix(Int(count)).map {
            let bounds = CGDisplayBounds($0)
            return PhysicalDisplay(
                id: $0,
                pixelWidth: Int(CGDisplayPixelsWide($0)),
                pixelHeight: Int(CGDisplayPixelsHigh($0)),
                layoutX: Int(bounds.origin.x.rounded()),
                layoutY: Int(bounds.origin.y.rounded()),
                layoutWidth: Int(bounds.width.rounded()),
                layoutHeight: Int(bounds.height.rounded()),
                isMain: CGDisplayIsMain($0) != 0
            )
        }
    }
}
#endif
