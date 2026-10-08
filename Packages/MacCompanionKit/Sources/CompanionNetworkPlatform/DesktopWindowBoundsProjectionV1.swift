import CompanionWire
import CoreGraphics
import Foundation

enum DesktopWindowBoundsProjectionV1 {
    /// Ordered ordinary window bounds only; no window names, pixels or input.
    static func project(_ query: DesktopWindowQueryV1, desktop: CGRect, windows: [CGRect]) throws -> DesktopWindowGeometryV1 {
        let empty = try DesktopWindowGeometryV1(query: query, rect: [0, 0, 0, 0])
        guard !desktop.isNull, !desktop.isEmpty, desktop.width.isFinite, desktop.height.isFinite,
              abs(Double(query.width) / Double(query.height) - desktop.width / desktop.height) / (desktop.width / desktop.height) < 0.03 else { return empty }
        let point = CGPoint(x: desktop.minX + CGFloat(query.x) / CGFloat(query.width) * desktop.width,
                            y: desktop.minY + CGFloat(query.y) / CGFloat(query.height) * desktop.height)
        guard let window = windows.first(where: { !$0.isNull && !$0.isEmpty && $0.contains(point) }) else { return empty }
        let visible = window.intersection(desktop)
        guard !visible.isNull, !visible.isEmpty else { return empty }
        let x = max(0, Int64(((visible.minX - desktop.minX) / desktop.width * CGFloat(query.width)).rounded()))
        let y = max(0, Int64(((visible.minY - desktop.minY) / desktop.height * CGFloat(query.height)).rounded()))
        let right = min(query.width, Int64(((visible.maxX - desktop.minX) / desktop.width * CGFloat(query.width)).rounded()))
        let bottom = min(query.height, Int64(((visible.maxY - desktop.minY) / desktop.height * CGFloat(query.height)).rounded()))
        guard right > x, bottom > y else { return empty }
        return try DesktopWindowGeometryV1(query: query, rect: [x, y, right - x, bottom - y])
    }
    static func system(_ query: DesktopWindowQueryV1) throws -> DesktopWindowGeometryV1 {
        #if os(macOS)
        var displays = [CGDirectDisplayID](repeating: 0, count: 32); var count: UInt32 = 0
        guard CGGetActiveDisplayList(32, &displays, &count) == .success else {
            return try DesktopWindowGeometryV1(query: query, rect: [0, 0, 0, 0])
        }
        let desktop = displays.prefix(Int(count)).reduce(CGRect.null) { $0.union(CGDisplayBounds($1)) }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = info.prefix(512).compactMap { item -> CGRect? in
            guard (item[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (item[kCGWindowSharingState as String] as? NSNumber)?.intValue != 0,
                  let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 40, rect.height > 30 else { return nil }
            return rect
        }
        return try project(query, desktop: desktop, windows: windows)
        #else
        return try DesktopWindowGeometryV1(query: query, rect: [0, 0, 0, 0])
        #endif
    }
}
