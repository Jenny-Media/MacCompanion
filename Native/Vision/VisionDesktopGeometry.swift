import Foundation
import CoreGraphics

/// One selection sequence distinguishes a pinch with hand jitter from a drag.
struct VisionSelectionGesture {
    private(set) var active = false
    private(set) var dragging = false
    mutating func update(translation: CGPoint) -> Bool {
        guard translation.x.isFinite, translation.y.isFinite else { return false }
        active = true
        let began = !dragging && hypot(translation.x, translation.y) >= 12
        dragging = dragging || began
        return began
    }
    mutating func finish(cancelled: Bool) -> Bool {
        let click = active && !dragging && !cancelled
        self = Self()
        return click
    }
}

/// Remote pixels retain their aspect ratio at every window size, including
/// wide/ultrawide frames. This contains no OS window-placement assumptions.
enum VisionDesktopGeometry {
    static func visibleTarget(cursor: CGPoint, crop: CGRect, destination: CGRect, viewport: CGSize) -> (remote: CGPoint, local: CGPoint)? {
        let visible = destination.intersection(CGRect(origin: .zero, size: viewport))
        guard crop.width > 0, crop.height > 0, !visible.isNull, !visible.isEmpty else { return nil }
        let cursorLocal = CGPoint(x: destination.minX + (cursor.x - crop.minX) / crop.width * destination.width,
                                  y: destination.minY + (cursor.y - crop.minY) / crop.height * destination.height)
        let local = crop.contains(cursor) && visible.contains(cursorLocal) ? cursorLocal : CGPoint(x: visible.midX, y: visible.midY)
        guard let remote = map(local, crop: crop, destination: destination) else { return nil }
        return (remote, local)
    }
    static func clampedPan(_ pan: CGPoint, crop: CGRect, viewport: CGSize, zoom: CGFloat) -> CGPoint {
        guard pan.x.isFinite, pan.y.isFinite else { return .zero }
        let rect = destination(crop: crop, viewport: viewport, zoom: zoom)
        let x = max(0, (rect.width - viewport.width) / 2), y = max(0, (rect.height - viewport.height) / 2)
        return CGPoint(x: max(-x, min(x, pan.x)), y: max(-y, min(y, pan.y)))
    }
    static func anchoredPan(crop: CGRect, viewport: CGSize, zoom: CGFloat, pan: CGPoint, nextZoom: CGFloat, anchor: CGPoint) -> CGPoint {
        let before = destination(crop: crop, viewport: viewport, zoom: zoom, pan: pan)
        let after = destination(crop: crop, viewport: viewport, zoom: nextZoom)
        guard before.width > 0, before.height > 0, anchor.x.isFinite, anchor.y.isFinite else { return .zero }
        let normalized = CGPoint(x: (anchor.x - before.minX) / before.width, y: (anchor.y - before.minY) / before.height)
        return clampedPan(CGPoint(x: anchor.x - after.minX - normalized.x * after.width,
                                  y: anchor.y - after.minY - normalized.y * after.height), crop: crop, viewport: viewport, zoom: nextZoom)
    }
    static func destination(crop: CGRect, viewport: CGSize, zoom: CGFloat = 1, pan: CGPoint = .zero) -> CGRect {
        guard [crop.minX, crop.minY, crop.width, crop.height, viewport.width, viewport.height, zoom, pan.x, pan.y].allSatisfy(\.isFinite),
              crop.width > 0, crop.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let scale = min(viewport.width / crop.width, viewport.height / crop.height) * max(1, min(8, zoom))
        let width = crop.width * scale, height = crop.height * scale
        let limitX = max(0, (width - viewport.width) / 2), limitY = max(0, (height - viewport.height) / 2)
        return CGRect(x: (viewport.width - width) / 2 + max(-limitX, min(limitX, pan.x)),
                      y: (viewport.height - height) / 2 + max(-limitY, min(limitY, pan.y)), width: width, height: height)
    }
    static func map(_ point: CGPoint, crop: CGRect, destination: CGRect, dragging: Bool = false) -> CGPoint? {
        guard [point.x, point.y, crop.minX, crop.minY, crop.width, crop.height,
               destination.minX, destination.minY, destination.width, destination.height].allSatisfy(\.isFinite),
              crop.width > 0, crop.height > 0, destination.width > 0, destination.height > 0,
              dragging || destination.contains(point) else { return nil }
        return CGPoint(x: crop.minX + floor(max(0, min(crop.width - 1, (point.x - destination.minX) / destination.width * crop.width))),
                       y: crop.minY + floor(max(0, min(crop.height - 1, (point.y - destination.minY) / destination.height * crop.height))))
    }
}

/// Partition movement at the existing transport's 16.16 precision and bound.
enum VisionNativeScroll {
    static func packets(dx: CGFloat, dy: CGFloat) -> [CGPoint]? {
        guard dx.isFinite, dy.isFinite, abs(dx) <= 16_384, abs(dy) <= 16_384 else { return nil }
        let x = Int64((Double(dx) * 65_536).rounded(.toNearestOrAwayFromZero))
        let y = Int64((Double(dy) * 65_536).rounded(.toNearestOrAwayFromZero))
        let limit: Int64 = 2_048 * 65_536
        let count = Int((max(abs(x), abs(y)) + limit - 1) / limit)
        guard count > 0 else { return [] }
        func part(_ units: Int64, _ index: Int) -> CGFloat {
            let base = units / Int64(count), remainder = units % Int64(count)
            let extra: Int64 = Int64(index) < abs(remainder) ? (remainder < 0 ? -1 : 1) : 0
            return CGFloat(base + extra) / 65_536
        }
        return (0..<count).map { CGPoint(x: part(x, $0), y: part(y, $0)) }
    }
}

/// Shared by the native spatial-event adapter and manifest-indexed boundary tests.
struct VisionDesktopGesture {
    enum State: String { case idle, pending, scrolling, context, dragArmed, dragging, adjusting }
    enum Source { case hand, pointer }
    enum Action { case right, doubleClick, armDrag }
    struct Effect: Equatable {
        enum Kind: String { case click, secondary, doubleClick, scroll, dragStart, dragMove, dragEnd, menu, localPan }
        let kind: Kind
        let point: CGPoint
        var delta: CGPoint = .zero
    }
    static let holdDelay = 0.55
    static let doubleClickDelay = 0.35
    static let doubleClickDistance: CGFloat = 24
    private(set) var state = State.idle
    private(set) var active = false
    private(set) var target = CGPoint.zero
    private var localStart = CGPoint.zero
    private var started = 0.0
    private var movement = VisionSelectionGesture()
    private var previous = CGPoint.zero
    private var armed = false
    private var source = Source.hand
    private var adjusting = false
    private var lastClick: (remote: CGPoint, local: CGPoint, time: Double)?

    mutating func begin(target point: CGPoint, local: CGPoint, time: Double, source: Source = .hand) -> [Effect] {
        guard !active, [.idle, .dragArmed, .adjusting].contains(state),
              [point.x, point.y, local.x, local.y, time].allSatisfy(\.isFinite) else { return [] }
        armed = state == .dragArmed
        if !armed { target = point }
        localStart = local; started = time; self.source = source
        previous = .zero; movement = .init(); _ = movement.update(translation: .zero); active = true
        if adjusting { state = .adjusting; lastClick = nil; return [] }
        if source == .pointer { state = .dragging; lastClick = nil; return [.init(kind: .dragStart, point: target)] }
        state = .pending; return []
    }
    mutating func move(_ translation: CGPoint) -> [Effect] {
        guard active, translation.x.isFinite, translation.y.isFinite else { return [] }
        _ = movement.update(translation: translation)
        if state == .adjusting {
            let delta = CGPoint(x: translation.x - previous.x, y: translation.y - previous.y)
            previous = translation; return [.init(kind: .localPan, point: target, delta: delta)]
        }
        var result: [Effect] = []
        if state == .pending, movement.dragging {
            lastClick = nil
            if armed { state = .dragging; result.append(.init(kind: .dragStart, point: target)) }
            else { state = .scrolling }
        }
        if state == .scrolling {
            result.append(.init(kind: .scroll, point: target, delta: CGPoint(x: translation.x - previous.x, y: translation.y - previous.y)))
        } else if state == .dragging { result.append(.init(kind: .dragMove, point: target, delta: translation)) }
        // Pending jitter belongs to the first admitted scroll displacement.
        if state != .pending { previous = translation }
        return result
    }
    mutating func hold(time: Double) -> [Effect] {
        guard active, state == .pending, !armed, time.isFinite, time - started >= Self.holdDelay else { return [] }
        state = .context; lastClick = nil
        return [.init(kind: .menu, point: target)]
    }
    mutating func finish(time: Double, cancelled: Bool = false) -> [Effect] {
        guard active else { return [] }
        if cancelled || !time.isFinite || time < started { return cancel() }
        var effects: [Effect] = []
        if state == .pending, !armed {
            if time - started >= Self.holdDelay { effects = hold(time: time) }
            else {
                let point: CGPoint
                if let lastClick, time >= lastClick.time, time - lastClick.time <= Self.doubleClickDelay,
                   hypot(localStart.x - lastClick.local.x, localStart.y - lastClick.local.y) <= Self.doubleClickDistance {
                    point = lastClick.remote; self.lastClick = nil
                } else { point = target; lastClick = (target, localStart, time) }
                effects = [.init(kind: .click, point: point)]
            }
        } else if state == .dragging { effects = [.init(kind: .dragEnd, point: target)] }
        active = false; armed = false; movement = .init()
        if state != .context { state = adjusting ? .adjusting : .idle }
        return effects
    }
    mutating func action(_ action: Action) -> [Effect] {
        guard state == .context, !active else { return [] }
        lastClick = nil
        switch action {
        case .armDrag: state = .dragArmed; return []
        case .right: state = .idle; return [.init(kind: .secondary, point: target)]
        case .doubleClick: state = .idle; return [.init(kind: .doubleClick, point: target)]
        }
    }
    mutating func setAdjusting(_ value: Bool) -> [Effect] {
        let releases = cancel(); adjusting = value; state = value ? .adjusting : .idle; return releases
    }
    mutating func cancel() -> [Effect] {
        let releases: [Effect] = state == .dragging ? [.init(kind: .dragEnd, point: target)] : []
        active = false; armed = false; movement = .init(); lastClick = nil
        state = adjusting ? .adjusting : .idle
        return releases
    }
}

struct VisionScrollDistance {
    static let quantum: CGFloat = 12
    static let positiveVertical = 8, negativeVertical = 16, positiveHorizontal = 32, negativeHorizontal = 64
    private(set) var remainder = CGPoint.zero
    mutating func accumulate(dx: CGFloat, dy: CGFloat) -> (horizontal: Int, vertical: Int)? {
        guard dx.isFinite, dy.isFinite, abs(dx) <= 16_384, abs(dy) <= 16_384 else { return nil }
        let x = remainder.x + dx, y = remainder.y + dy
        let horizontal = Int(x / Self.quantum), vertical = Int(y / Self.quantum)
        remainder = CGPoint(x: x - CGFloat(horizontal) * Self.quantum, y: y - CGFloat(vertical) * Self.quantum)
        return (horizontal, vertical)
    }
}

struct VisionHeldInput {
    private(set) var keys: Set<UInt32> = []
    private(set) var buttons = 0
    mutating func down(_ key: UInt32) -> Bool {
        guard keys.count < 256 || keys.contains(key) else { return false }
        keys.insert(key); return true
    }
    mutating func up(_ key: UInt32) -> Bool { keys.remove(key) != nil }
    mutating func pointer(_ mask: Int) { buttons = mask & 7 }
    mutating func release() -> (keys: [UInt32], pointer: Bool) {
        let result = (keys.sorted(), buttons != 0)
        keys = []; buttons = 0
        return result
    }
}

enum VisionTerminalAdmission {
    static func allows(focused: Bool, emulatorReply: Bool, suspended: Bool, unlocked: Bool) -> Bool {
        !suspended && unlocked && (focused || emulatorReply)
    }
}
