#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import AppKit
import SwiftUI

private final class MacVNCControlHint: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct MacVNCSurface: NSViewRepresentable {
    let session: MacVNCSession
    func makeNSView(context: Context) -> MacVNCInputView { MacVNCInputView(session: session) }
    func updateNSView(_ view: MacVNCInputView, context: Context) {
        view.update(image: session.image, crop: session.crop, zoom: session.zoom, pan: session.pan,
                    enabled: session.canInput, cursorImage: session.cursorImage,
                    cursorHotspot: session.cursorHotspot, cursorPosition: session.cursorPosition)
    }
    static func dismantleNSView(_ view: MacVNCInputView, coordinator: ()) { view.detach() }
}

// AppKit invokes this older, nonisolated text-input protocol on its UI thread.
@MainActor final class MacVNCInputView: NSView, @preconcurrency NSTextInputClient {
    private weak var session: MacVNCSession?
    private var image: NSImage?
    private var crop = CGRect.zero
    private var zoom: CGFloat = 1
    private var pan = CGPoint.zero
    private var enabled = false
    private var cursorImage: NSImage?
    private var cursorHotspot = CGPoint.zero
    private var cursorPosition = CGPoint.zero
    private var remoteCursor: NSCursor?
    private let controlHint = MacVNCControlHint(labelWithString: "")
    private var keys = MacVNCKeyboardState()
    private var composition = MacVNCComposition()
    private var textEvent: NSEvent?
    private var eventStartedWithMarkedText = false
    private var mask = 0
    private var scrollX: CGFloat = 0, scrollY: CGFloat = 0
    private var observers: [NSObjectProtocol] = []
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { enabled }
    init(session: MacVNCSession) {
        self.session = session; super.init(frame: .zero)
        session.resetInput = { [weak self] in self?.releaseInput() }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Remote desktop")
        setAccessibilityIdentifier("mac-vnc-surface")
        controlHint.font = .systemFont(ofSize: 12, weight: .medium)
        controlHint.textColor = .white
        controlHint.backgroundColor = NSColor.black.withAlphaComponent(0.8)
        controlHint.drawsBackground = true
        controlHint.isHidden = true
        controlHint.setAccessibilityIdentifier("mac-vnc-control-hint")
        addSubview(controlHint)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    private var destination: CGRect { MacVNCGeometry.destination(crop: crop, viewport: bounds.size, zoom: zoom, pan: pan) }
    private var admitsInput: Bool { enabled && session?.canInput == true && NSApplication.shared.isActive && window?.isKeyWindow == true && window?.firstResponder === self }
    func update(image: NSImage?, crop: CGRect, zoom: CGFloat, pan: CGPoint, enabled: Bool,
                cursorImage: NSImage?, cursorHotspot: CGPoint, cursorPosition: CGPoint) {
        if self.enabled && (!enabled || self.crop != crop) { releaseInput() }
        self.image = image; self.crop = crop; self.zoom = zoom; self.pan = pan
        if self.cursorImage !== cursorImage || self.cursorHotspot != cursorHotspot {
            remoteCursor = cursorImage.map { NSCursor(image: $0, hotSpot: cursorHotspot) }
        }
        self.cursorImage = cursorImage; self.cursorHotspot = cursorHotspot; self.cursorPosition = cursorPosition
        self.enabled = enabled; needsDisplay = true
        setAccessibilityHidden(image == nil)
        refreshControlPresentation()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); removeObservers()
        guard let window else { releaseInput(); return }
        for (name, object) in [(NSWindow.didResignKeyNotification, window as AnyObject), (NSWindow.didBecomeKeyNotification, window as AnyObject),
                               (NSApplication.didResignActiveNotification, NSApplication.shared as AnyObject), (NSApplication.didBecomeActiveNotification, NSApplication.shared as AnyObject)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if name == NSWindow.didResignKeyNotification || name == NSApplication.didResignActiveNotification { self?.releaseInput() }
                    self?.refreshControlPresentation()
                }
            })
        }
        refreshControlPresentation()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        defer { drawComposition() }
        guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = cgImage.cropping(to: crop), let context = NSGraphicsContext.current?.cgContext else { return }
        let destination = destination
        context.saveGState(); context.interpolationQuality = .high
        context.translateBy(x: destination.minX, y: destination.maxY); context.scaleBy(x: 1, y: -1)
        context.draw(cropped, in: CGRect(origin: .zero, size: destination.size)); context.restoreGState()
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        // AppKit installs the new responder after this callback returns.
        DispatchQueue.main.async { [weak self] in self?.refreshControlPresentation() }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        releaseInput()
        DispatchQueue.main.async { [weak self] in self?.refreshControlPresentation() }
        return super.resignFirstResponder()
    }
    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { releaseInput() }
        super.setFrameSize(newSize)
        refreshControlPresentation()
    }
    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: .arrow)
        let canvas = destination.intersection(visibleRect)
        if admitsInput, !canvas.isEmpty, let remoteCursor { addCursorRect(canvas, cursor: remoteCursor) }
    }
    override func cursorUpdate(with event: NSEvent) {
        guard window?.isKeyWindow == true, NSApplication.shared.isActive,
              event.windowNumber == window?.windowNumber, ownsCursor(at: event.locationInWindow) else { return }
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }
    private func ownsCursor(at windowPoint: CGPoint) -> Bool {
        guard let content = window?.contentView else { return false }
        let hitPoint = content.superview?.convert(windowPoint, from: nil) ?? windowPoint
        return content.hitTest(hitPoint) === self
    }
    private func cursor(at point: CGPoint) -> NSCursor {
        admitsInput && destination.intersection(visibleRect).contains(point) ? remoteCursor ?? .arrow : .arrow
    }
    private func refreshControlPresentation() {
        let hint: String
        if image == nil || admitsInput { hint = "" }
        else if !enabled || session?.canInput != true { hint = session?.controlUnavailableHint ?? "Control unavailable" }
        else { hint = "Click to control" }
        controlHint.stringValue = hint; controlHint.isHidden = hint.isEmpty
        controlHint.sizeToFit()
        controlHint.frame.origin = CGPoint(x: 12, y: max(12, bounds.height - controlHint.frame.height - 12))
        setAccessibilityHelp(hint.isEmpty ? (admitsInput ? "Controlling remote desktop" : "Remote desktop unavailable") : hint)
        window?.invalidateCursorRects(for: self)
        // A shape-only report can arrive while the physical mouse is stationary.
        // Set it immediately only when this view actually owns the pointer.
        guard let window, window.isKeyWindow, NSApplication.shared.isActive,
              NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window.windowNumber else { return }
        let point = window.mouseLocationOutsideOfEventStream
        guard ownsCursor(at: point) else { return }
        cursor(at: convert(point, from: nil)).set()
    }
    override func mouseDown(with event: NSEvent) { click(event, bit: 1, down: true) }
    override func mouseUp(with event: NSEvent) { click(event, bit: 1, down: false) }
    override func rightMouseDown(with event: NSEvent) { click(event, bit: 4, down: true) }
    override func rightMouseUp(with event: NSEvent) { click(event, bit: 4, down: false) }
    override func otherMouseDown(with event: NSEvent) { if event.buttonNumber == 2 { click(event, bit: 2, down: true) } }
    override func otherMouseUp(with event: NSEvent) { if event.buttonNumber == 2 { click(event, bit: 2, down: false) } }
    override func mouseMoved(with event: NSEvent) { move(event) }
    override func mouseDragged(with event: NSEvent) { move(event) }
    override func rightMouseDragged(with event: NSEvent) { move(event) }
    override func otherMouseDragged(with event: NSEvent) { move(event) }
    private func point(_ event: NSEvent, clamp: Bool) -> CGPoint? {
        return MacVNCGeometry.map(point: convert(event.locationInWindow, from: nil), crop: crop, destination: destination, clamp: clamp)
    }
    private func click(_ event: NSEvent, bit: Int, down: Bool) {
        if down { window?.makeFirstResponder(self); refreshControlPresentation() }
        guard admitsInput, let point = point(event, clamp: !down) else { return }
        if down { mask |= bit } else { mask &= ~bit }
        session?.pointer(point, mask: mask)
    }
    private func move(_ event: NSEvent) {
        guard admitsInput, let point = point(event, clamp: mask != 0) else { return }
        session?.pointer(point, mask: mask)
    }
    override func scrollWheel(with event: NSEvent) {
        guard admitsInput, let session else { return }
        if event.modifierFlags.contains(.option) {
            session.pan.x += event.scrollingDeltaX; session.pan.y += event.scrollingDeltaY; return
        }
        scrollX += event.scrollingDeltaX * VNCSessionPreferences.scrollSpeed
        scrollY += event.scrollingDeltaY * VNCSessionPreferences.scrollSpeed
        let unit: CGFloat = event.hasPreciseScrollingDeltas ? 6 : 1
        func send(_ value: inout CGFloat, positive: Int, negative: Int) {
            let count = min(8, Int(abs(value) / unit)); guard count > 0 else { return }
            let bit = value > 0 ? positive : negative
            for _ in 0..<count { session.pointer(session.cursorPosition, mask: mask | bit); session.pointer(session.cursorPosition, mask: mask) }
            value = value.truncatingRemainder(dividingBy: unit)
        }
        send(&scrollY, positive: 8, negative: 16); send(&scrollX, positive: 32, negative: 64)
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { scrollX = 0; scrollY = 0 }
    }
    override func magnify(with event: NSEvent) {
        session?.zoom = max(1, min(8, (session?.zoom ?? 1) * (1 + event.magnification)))
    }
    override func keyDown(with event: NSEvent) {
        guard admitsInput else { return }
        if !event.modifierFlags.intersection([.control, .command]).isEmpty
            || (event.modifierFlags.contains(.option) && !composition.hasMarkedText) {
            sendPhysicalKey(event); return
        }
        textEvent = event; eventStartedWithMarkedText = composition.hasMarkedText
        defer { textEvent = nil; eventStartedWithMarkedText = false }
        interpretKeyEvents([event])
    }
    private func sendPhysicalKey(_ event: NSEvent) {
        session?.keys(keys.updateModifiers(event.modifierFlags) + keys.keyDown(code: event.keyCode, characters: event.charactersIgnoringModifiers ?? "", repeatKey: event.isARepeat))
    }
    override func keyUp(with event: NSEvent) { guard admitsInput else { return }; session?.keys(keys.keyUp(code: event.keyCode)) }
    override func flagsChanged(with event: NSEvent) { guard admitsInput, !composition.hasMarkedText else { return }; session?.keys(keys.updateModifiers(event.modifierFlags)) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains([.command, .control]), event.charactersIgnoringModifiers?.lowercased() == "f" { return false }
        guard admitsInput, event.modifierFlags.contains(.command),
              !(event.modifierFlags.contains(.shift) && event.charactersIgnoringModifiers?.lowercased() == "n"),
              !["q", "w", "h", "m", ","].contains(event.charactersIgnoringModifiers?.lowercased() ?? "") else { return false }
        keyDown(with: event); return true
    }
    func releaseInput() {
        session?.releaseKeys(keys.releaseAll())
        if mask != 0 { session?.releasePointer() }
        mask = 0; scrollX = 0; scrollY = 0
        composition.discard(); inputContext?.discardMarkedText(); needsDisplay = true
    }
    func insertText(_ value: Any, replacementRange: NSRange) {
        guard admitsInput else { return }
        let text = (value as? NSAttributedString)?.string ?? (value as? String) ?? ""
        guard !text.isEmpty, text.utf16.count <= 4096 else { unmarkText(); return }
        if !eventStartedWithMarkedText, !composition.hasMarkedText, text.unicodeScalars.count == 1,
           let event = textEvent, event.charactersIgnoringModifiers == text {
            sendPhysicalKey(event)
        } else {
            session?.releaseKeys(keys.releaseAll()); composition.discard()
            session?.text(text)
        }
        needsDisplay = true
    }
    override func doCommand(by selector: Selector) {
        guard admitsInput else { return }
        if composition.hasMarkedText { unmarkText(); return }
        if let event = textEvent { sendPhysicalKey(event) }
    }
    func setMarkedText(_ value: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard admitsInput else { return }
        session?.releaseKeys(keys.releaseAll())
        composition.set((value as? NSAttributedString)?.string ?? (value as? String) ?? "", selectedRange: selectedRange)
        needsDisplay = true
    }
    func unmarkText() { composition.discard(); needsDisplay = true }
    func hasMarkedText() -> Bool { composition.hasMarkedText }
    func markedRange() -> NSRange { composition.markedRange }
    func selectedRange() -> NSRange { composition.selection }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let (text, actual) = composition.substring(range) else { actualRange?.pointee = NSRange(location: NSNotFound, length: 0); return nil }
        actualRange?.pointee = actual; return text
    }
    private var compositionRect: NSRect {
        .init(x: 12, y: max(12, bounds.height - 40), width: max(1, min(420, bounds.width - 24)), height: 28)
    }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = composition.markedRange
        guard let window else { return .zero }
        return window.convertToScreen(convert(compositionRect, to: nil))
    }
    func characterIndex(for point: NSPoint) -> Int { NSNotFound }
    private func drawComposition() {
        guard composition.hasMarkedText, admitsInput else { return }
        NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect: compositionRect, xRadius: 6, yRadius: 6).fill()
        (composition.text as NSString).draw(in: compositionRect.insetBy(dx: 8, dy: 5), withAttributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor, .underlineStyle: NSUnderlineStyle.single.rawValue])
    }
    private func removeObservers() { observers.forEach(NotificationCenter.default.removeObserver); observers = [] }
    func detach() {
        releaseInput(); removeObservers(); session?.resetInput = nil; session = nil; image = nil; cursorImage = nil
        remoteCursor = nil; enabled = false; refreshControlPresentation()
    }
}
#endif
