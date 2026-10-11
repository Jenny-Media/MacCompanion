#if os(visionOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UIKit
import SwiftTerm
import Observation

struct VisionSceneCapture: UIViewRepresentable {
    let changed: @MainActor (UIWindowScene?) -> Void
    final class Capture: UIView {
        var changed: @MainActor (UIWindowScene?) -> Void = { _ in }
        override func didMoveToWindow() { super.didMoveToWindow(); changed(window?.windowScene) }
    }
    func makeUIView(context: Context) -> Capture { let view = Capture(); view.changed = changed; return view }
    func updateUIView(_ view: Capture, context: Context) { view.changed = changed }
}

/// Native ornaments have separate UIWindows within the connection's scene.
/// Admission never borrows a key window from a different connection scene.
@MainActor final class VisionSurfaceFocus {
    weak var view: UIView?
    var changed: @MainActor (Bool) -> Void = { _ in }
    private var observers: [NSObjectProtocol] = []
    var available: Bool {
        guard let window = view?.window else { return false }
        return window.windowScene?.keyWindow != nil && window.windowScene?.activationState == .foregroundActive && DirectAppLockV1.shared.canAccess
    }
    init() {
        for name in [UIWindow.didBecomeKeyNotification, UIWindow.didResignKeyNotification, UIScene.willDeactivateNotification, UIScene.didActivateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let targetWindow = note.object as? UIWindow, targetScene = note.object as? UIWindowScene
                MainActor.assumeIsolated {
                    guard let self, let window = self.view?.window else { return }
                    if targetWindow?.windowScene === window.windowScene || targetScene === window.windowScene {
                        // didResignKey precedes didBecomeKey during an ornament
                        // transition. Observe the settled owned scene rather than
                        // treating that transient gap as another session owner.
                        DispatchQueue.main.async { [weak self] in
                            guard let self else { return }; self.changed(self.available)
                        }
                    }
                }
            })
        }
    }
    isolated deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
}

@MainActor @Observable final class VisionDesktopInteraction {
    struct Target: Identifiable {
        let id = UUID()
        let local: CGPoint
    }
    weak var canvas: VisionDesktopCanvas?
    var contextTarget: Target?
    var selectionActive = false
    var dragArmed = false
    var adjusting = false
    var keyboardVisible = false
    var keyboardFocused = false
    var keyboardRequest = UUID()
    var transferringFocus = false
    let physicalKeyboard = VisionPhysicalKeyboard()
    var diagnostic = ""
    func requestKeyboard() {
        canvas?.cancelSelection()
        keyboardVisible = true; keyboardRequest = UUID()
    }
    func dismissKeyboard() { keyboardVisible = false; keyboardFocused = false }
    func performQuickAction(_ action: VNCQuickAction) { canvas?.performQuickAction(action) }
}

struct VisionDesktopSurface: View {
    let session: VisionDesktopSession
    let interaction: VisionDesktopInteraction
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                VisionDesktopRenderer(session: session, interaction: interaction)
                    .contentShape(Rectangle())
                    .simultaneousGesture(SpatialEventGesture()
                        .onChanged { interaction.canvas?.spatialEvents($0) }
                        .onEnded { events in
                            interaction.canvas?.spatialEvents(events)
                            interaction.canvas?.spatialEnded()
                        })
                    .modifier(VisionHandMovement(interaction: interaction))
                    .accessibilityLabel("Remote Desktop")
                    .accessibilityHint("Pinch to click, pinch and move to scroll, or hold for actions. Use Adjust View to zoom or pan.")
                    .accessibilityIdentifier("vision-desktop-canvas")
                    .accessibilityValue(interaction.diagnostic)
                if let target = interaction.contextTarget {
                    ScrollView {
                        VStack(spacing: 12) {
                            Text("Desktop Actions").font(.headline)
                            Button("Right Click") { interaction.canvas?.targetAction(.right) }
                                .accessibilityIdentifier("vision-target-right-click")
                            Button("Double Click") { interaction.canvas?.targetAction(.doubleClick) }
                                .accessibilityIdentifier("vision-target-double-click")
                            Button("Drag Item") { interaction.canvas?.targetAction(.armDrag) }
                                .accessibilityIdentifier("vision-target-drag-item")
                            Button("Cancel") { interaction.canvas?.cancelSelection() }
                                .accessibilityIdentifier("vision-target-cancel")
                        }.buttonStyle(.bordered).controlSize(.large)
                            .disabled(interaction.selectionActive).padding(16)
                    }.accessibilityIdentifier("vision-desktop-target-actions")
                        .frame(width: 260, height: min(320, max(120, geometry.size.height - 16)))
                        .glassBackgroundEffect()
                        .position(x: max(130, min(geometry.size.width - 130, target.local.x)),
                                  y: min(geometry.size.height / 2, max(160, target.local.y)))
                }
                if interaction.dragArmed {
                    HStack {
                        Text("Drag Item: pinch and move to drag the selected item")
                        Button("Cancel") { interaction.canvas?.cancelSelection() }
                    }.padding(12).glassBackgroundEffect().padding(16)
                }
            }
        }
    }
}
private struct VisionHandMovement: ViewModifier {
    let interaction: VisionDesktopInteraction
    @ViewBuilder func body(content: Content) -> some View {
        if #available(visionOS 27, *) {
            content.simultaneousGesture(DragGesture(minimumDistance: 0, inputKinds: [.directTouch, .indirectTouch])
                .onChanged(moved).onEnded(moved))
        } else {
            content.simultaneousGesture(DragGesture(minimumDistance: 0).onChanged(moved).onEnded(moved))
        }
    }
    private func moved(_ value: DragGesture.Value) {
        interaction.canvas?.handMovement(CGPoint(x: value.translation.width, y: value.translation.height))
    }
}
private struct VisionDesktopRenderer: UIViewRepresentable {
    let session: VisionDesktopSession
    let interaction: VisionDesktopInteraction
    func makeUIView(context: Context) -> VisionDesktopCanvas {
        let view = VisionDesktopCanvas(session: session, interaction: interaction); interaction.canvas = view; return view
    }
    func updateUIView(_ view: VisionDesktopCanvas, context: Context) { view.setNeedsDisplay() }
    static func dismantleUIView(_ view: VisionDesktopCanvas, coordinator: ()) {
        view.session.releaseInput(); view.focus.view = nil; view.interaction.canvas = nil
    }
}

final class VisionDesktopCanvas: UIView, UIGestureRecognizerDelegate {
    let session: VisionDesktopSession
    let interaction: VisionDesktopInteraction
    let focus = VisionSurfaceFocus()
    private var physical: VisionPhysicalKeyboard { interaction.physicalKeyboard }
    private var gesture = VisionDesktopGesture()
    private var eventID: SpatialEventCollection.Event.ID?
    private var blockedID: SpatialEventCollection.Event.ID?
    private var start = CGPoint.zero
    private var binding: (generation: UUID, crop: CGRect, destination: CGRect, viewport: CGSize)?
    private var wheelBinding: (generation: UUID, crop: CGRect, destination: CGRect, viewport: CGSize, target: CGPoint)?
    private var zoomBinding: (generation: UUID, crop: CGRect, viewport: CGSize, anchor: CGPoint, zoom: CGFloat, pan: CGPoint)?
    private var holdTask: Task<Void, Never>?
    private var viewport = CGSize.zero
    private var physicalOrigin: CGPoint?
    private var physicalPresses: [ObjectIdentifier: (generation: UUID, crop: CGRect, destination: CGRect, viewport: CGSize)] = [:]
    private var movementCallbacks = 0
    private var maximumMovement: CGFloat = 0
    private var spatialKind = "none"
    private var interruptedSelection = false
    override var canBecomeFirstResponder: Bool { true }
    init(session: VisionDesktopSession, interaction: VisionDesktopInteraction = .init()) {
        self.session = session; self.interaction = interaction; super.init(frame: .zero)
        backgroundColor = .black; isOpaque = true; clipsToBounds = true
        isAccessibilityElement = true
        accessibilityLabel = "Remote Desktop"; accessibilityIdentifier = "vision-desktop-canvas"
        focus.view = self
        physical.send = { [weak session] key, down in session?.key(key, down: down) }
        session.invalidatePhysicalPresses = { [weak self] in self?.physicalPresses.removeAll() }
        session.resetInput = { [weak self] in
            guard let self else { return }
            self.physical.clear(); self.blockedID = self.eventID
            self.interruptedSelection = self.gesture.active
            self.holdTask?.cancel(); self.holdTask = nil; self.eventID = nil
            _ = self.gesture.cancel(); _ = self.gesture.setAdjusting(self.interaction.adjusting)
            self.binding = nil; self.physicalOrigin = nil
            self.physicalPresses.removeAll()
            self.wheelBinding = nil; self.zoomBinding = nil
            self.interaction.contextTarget = nil; self.interaction.dragArmed = false
            self.interaction.selectionActive = false
            self.setNeedsDisplay()
        }
        session.inputAvailable = { [weak focus] in focus?.available == true }
        focus.changed = { [weak session] active in if !active { session?.releaseInput() } }
        let pointer = NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        let wheel = UIPanGestureRecognizer(target: self, action: #selector(wheel(_:)))
        wheel.allowedTouchTypes = []; wheel.allowedScrollTypesMask = .all; wheel.delegate = self; addGestureRecognizer(wheel)
        let primary = UITapGestureRecognizer(target: self, action: #selector(primary(_:)))
        primary.allowedTouchTypes = [pointer]; primary.buttonMaskRequired = .primary; primary.delegate = self
        let drag = UIPanGestureRecognizer(target: self, action: #selector(physicalDrag(_:)))
        drag.allowedTouchTypes = [pointer]; drag.delegate = self
        primary.require(toFail: drag); addGestureRecognizer(primary); addGestureRecognizer(drag)
        let secondary = UITapGestureRecognizer(target: self, action: #selector(secondary(_:)))
        secondary.allowedTouchTypes = [pointer]; secondary.buttonMaskRequired = .secondary; secondary.delegate = self; addGestureRecognizer(secondary)
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hover(_:)))
        hover.allowedTouchTypes = [pointer]; addGestureRecognizer(hover)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:))); pinch.delegate = self; addGestureRecognizer(pinch)
        observeRendering()
    }
    required init?(coder: NSCoder) { fatalError() }
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
        if let pan = recognizer as? UIPanGestureRecognizer, pan.allowedTouchTypes.isEmpty {
            return event.type == .scroll && !interaction.adjusting && !gesture.active && !session.pointerHeld
                && interaction.contextTarget == nil && !interaction.dragArmed
        }
        if recognizer is UIPinchGestureRecognizer { return interaction.adjusting }
        if recognizer is UIPanGestureRecognizer, !event.buttonMask.contains(.primary) { return false }
        return !gesture.active && !interaction.adjusting && interaction.contextTarget == nil && !interaction.dragArmed
    }
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard recognizer is UITapGestureRecognizer || recognizer is UIPanGestureRecognizer && !recognizer.allowedTouchTypes.isEmpty else { return true }
        let id = ObjectIdentifier(recognizer); physicalPresses[id] = nil
        guard touch.type == .indirectPointer, touch.phase == .began, physicalPressAvailable,
              remote(touch.location(in: self)) != nil else { return false }
        physicalPresses[id] = (session.inputGeneration, session.crop, destination, bounds.size)
        return true
    }
    private var physicalPressAvailable: Bool {
        session.canInput && !gesture.active && !interaction.adjusting && !session.pointerHeld
            && interaction.contextTarget == nil && !interaction.dragArmed
    }
    private func consumePhysicalPress(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let owner = physicalPresses.removeValue(forKey: ObjectIdentifier(recognizer)) else { return false }
        return physicalPressAvailable && owner.generation == session.inputGeneration && owner.crop == session.crop
            && owner.destination == destination && owner.viewport == bounds.size
    }
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    private func observeRendering() {
        withObservationTracking {
            _ = session.image; _ = session.cursor; _ = session.cursorHotspot; _ = session.cursorPosition
            _ = session.crop; _ = session.zoom; _ = session.pan
        } onChange: { [weak self] in
            Task { @MainActor in self?.setNeedsDisplay(); self?.observeRendering() }
        }
    }
    private var destination: CGRect { VisionDesktopGeometry.destination(crop: session.crop, viewport: bounds.size, zoom: session.zoom, pan: session.pan) }
    private var currentBinding: Bool {
        guard let binding else { return false }
        return session.canInput && binding.generation == session.inputGeneration && binding.crop == session.crop
            && binding.viewport == bounds.size && (interaction.adjusting || binding.destination == destination)
    }
    func remote(_ point: CGPoint, dragging: Bool = false) -> CGPoint? {
        VisionDesktopGeometry.map(point, crop: session.crop, destination: destination, dragging: dragging)
    }
    override func draw(_ rect: CGRect) {
        guard let image = session.image?.cgImage, let context = UIGraphicsGetCurrentContext(), destination.width > 0,
              let cropped = image.cropping(to: session.crop) else { return }
        UIImage(cgImage: cropped).draw(in: destination)
        if let cursor = session.cursor, session.crop.contains(session.cursorPosition) {
            let scale = destination.width / session.crop.width
            let point = CGPoint(x: destination.minX + (session.cursorPosition.x - session.crop.minX - session.cursorHotspot.x) * scale,
                                y: destination.minY + (session.cursorPosition.y - session.crop.minY - session.cursorHotspot.y) * scale)
            context.saveGState(); context.clip(to: destination)
            cursor.draw(in: CGRect(origin: point, size: CGSize(width: cursor.size.width * scale, height: cursor.size.height * scale)))
            context.restoreGState()
        }
        if gesture.state == .context || gesture.state == .dragArmed {
            let x = destination.minX + (gesture.target.x - session.crop.minX) / session.crop.width * destination.width
            let y = destination.minY + (gesture.target.y - session.crop.minY) / session.crop.height * destination.height
            context.setStrokeColor(UIColor.white.cgColor); context.setLineWidth(2)
            context.strokeEllipse(in: CGRect(x: x - 10, y: y - 10, width: 20, height: 20))
        }
    }
    func spatialEvents(_ events: SpatialEventCollection) {
        for event in events where event.kind != .pointer {
            spatialKind = String(describing: event.kind)
            if event.id == blockedID {
                if event.phase != .active { blockedID = nil }; continue
            }
            switch event.phase {
            case .active:
                if eventID == nil {
                    guard !gesture.active, physicalOrigin == nil, !session.pointerHeld,
                          gesture.state != .context, session.canInput, remote(event.location) != nil else { continue }
                    interruptedSelection = false
                    selectionChanged(start: event.location, translation: .zero)
                    if gesture.active { eventID = event.id }
                }
                guard eventID == event.id else { continue }
            case .ended, .cancelled:
                guard eventID == event.id else { continue }
                selectionFinished(cancelled: event.phase == .cancelled); eventID = nil
            @unknown default: cancelSelection()
            }
        }
    }
    func spatialEnded() {
        // Spatial pointer events also end here, but their UIKit recognizer owns
        // completion. A hand observer must never release/restart a mouse drag.
        if eventID != nil, gesture.active { selectionFinished(cancelled: false) }
        eventID = nil; blockedID = nil
    }
    /// DragGesture supplies the system's normalized pinch displacement; spatial
    /// location retains the selected target and must not be treated as motion.
    func handMovement(_ translation: CGPoint) {
        movementCallbacks += 1; maximumMovement = max(maximumMovement, hypot(translation.x, translation.y))
        publish()
        guard eventID != nil, gesture.active, blockedID != eventID else { return }
        selectionChanged(start: start, translation: translation)
    }
    func selectionChanged(start: CGPoint, translation: CGPoint) {
        guard !interruptedSelection, session.canInput else { return }
        if !gesture.active {
            guard let point = remote(start), gesture.state != .context else { return }
            physicalPresses.removeAll()
            retireWheel()
            becomeFirstResponder(); self.start = start
            binding = (session.inputGeneration, session.crop, destination, bounds.size)
            apply(gesture.begin(target: point, local: start, time: ProcessInfo.processInfo.systemUptime))
            holdTask?.cancel()
            holdTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
                guard let self, self.currentBinding, !Task.isCancelled else { return }
                self.apply(self.gesture.hold(time: ProcessInfo.processInfo.systemUptime)); self.publish()
            }
        }
        guard currentBinding else { cancelSelection(); return }
        apply(gesture.move(translation))
        if gesture.state != .pending { holdTask?.cancel(); holdTask = nil }
        publish()
    }
    func selectionFinished(cancelled: Bool) {
        holdTask?.cancel(); holdTask = nil
        guard gesture.active else { interruptedSelection = false; return }
        apply(gesture.finish(time: ProcessInfo.processInfo.systemUptime, cancelled: cancelled || !currentBinding))
        session.finishGesture(); publish()
    }
    func cancelSelection() {
        holdTask?.cancel(); holdTask = nil; blockedID = eventID
        retireWheel(); zoomBinding = nil
        physicalOrigin = nil
        physicalPresses.removeAll()
        interruptedSelection = gesture.active
        apply(gesture.cancel()); session.finishGesture(); binding = nil; publish()
    }
    func targetAction(_ action: VisionDesktopGesture.Action) {
        guard currentBinding else { cancelSelection(); return }
        apply(gesture.action(action)); publish()
    }
    func showActions() {
        setAdjusting(false); interruptedSelection = false
        guard session.canInput,
              let target = VisionDesktopGeometry.visibleTarget(cursor: session.cursorPosition, crop: session.crop,
                  destination: destination, viewport: bounds.size) else { return }
        start = target.local
        binding = (session.inputGeneration, session.crop, destination, bounds.size)
        apply(gesture.begin(target: target.remote, local: start, time: 0))
        apply(gesture.hold(time: 1)); apply(gesture.finish(time: 1)); publish()
    }
    func performQuickAction(_ action: VNCQuickAction) {
        guard action.enabled, action.valid, action.compatible(with: .desktop) else { return }
        if action.kind == .rightClick {
            showActions(); targetAction(.right)
        } else {
            session.quickAction(action)
        }
    }
    func setAdjusting(_ value: Bool) {
        becomeFirstResponder(); interaction.dismissKeyboard()
        cancelSelection(); apply(gesture.setAdjusting(value)); interaction.adjusting = value; publish()
    }
    func adjustZoom(_ factor: CGFloat, anchor: CGPoint? = nil) {
        guard factor.isFinite, factor > 0 else { return }
        physicalPresses.removeAll()
        let next = max(1, min(8, session.zoom * factor)), point = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let pan = VisionDesktopGeometry.anchoredPan(crop: session.crop, viewport: bounds.size, zoom: session.zoom,
            pan: session.pan, nextZoom: next, anchor: point)
        session.zoom = next; session.pan = pan; setNeedsDisplay()
    }
    func adjustPan(_ delta: CGPoint) {
        physicalPresses.removeAll()
        session.pan = VisionDesktopGeometry.clampedPan(CGPoint(x: session.pan.x + delta.x, y: session.pan.y + delta.y),
            crop: session.crop, viewport: bounds.size, zoom: session.zoom); setNeedsDisplay()
    }
    private func publish() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--vision-qa-empty-library") {
            interaction.diagnostic = "\(gesture.state.rawValue); source=\(spatialKind); movementCallbacks=\(movementCallbacks); distance=\(Int(maximumMovement)); active=\(gesture.active)"
        }
        #endif
        interaction.selectionActive = gesture.active
        interaction.dragArmed = gesture.state == .dragArmed
        if gesture.state != .context { interaction.contextTarget = nil }
        accessibilityValue = interaction.adjusting ? "Adjusting View" : interaction.dragArmed ? "Drag Item armed" : "Click, scroll, or hold for actions"
        setNeedsDisplay()
    }
    private func apply(_ effects: [VisionDesktopGesture.Effect]) {
        for effect in effects {
            switch effect.kind {
            case .click: session.click(effect.point)
            case .secondary: session.click(effect.point, button: 4)
            case .doubleClick: session.click(effect.point); session.click(effect.point)
            case .scroll: session.scroll(effect.point, dx: effect.delta.x, dy: effect.delta.y)
            case .dragStart: session.pointer(effect.point, mask: 1)
            case .dragMove:
                let scale = destination.width / session.crop.width
                if scale > 0 { session.pointer(CGPoint(x: effect.point.x + effect.delta.x / scale, y: effect.point.y + effect.delta.y / scale), mask: 1) }
            case .dragEnd: session.finishGesture()
            case .menu: interaction.contextTarget = .init(local: start)
            case .localPan:
                adjustPan(effect.delta)
            }
        }
    }
    @objc private func primary(_ recognizer: UITapGestureRecognizer) {
        guard [.ended, .cancelled, .failed].contains(recognizer.state) else { return }
        let admitted = consumePhysicalPress(recognizer)
        guard recognizer.state == .ended, admitted, let point = remote(recognizer.location(in: self)) else { return }
        physicalPresses.removeAll()
        becomeFirstResponder(); session.click(point)
    }
    @objc private func secondary(_ recognizer: UITapGestureRecognizer) {
        guard [.ended, .cancelled, .failed].contains(recognizer.state) else { return }
        let admitted = consumePhysicalPress(recognizer)
        guard recognizer.state == .ended, admitted, let point = remote(recognizer.location(in: self)) else { return }
        physicalPresses.removeAll()
        becomeFirstResponder(); session.click(point, button: 4)
    }
    @objc private func physicalDrag(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard consumePhysicalPress(recognizer) else { return }
            physicalPresses.removeAll()
            interruptedSelection = false
            becomeFirstResponder()
            let point = recognizer.location(in: self), delta = recognizer.translation(in: self)
            physicalOrigin = CGPoint(x: point.x - delta.x, y: point.y - delta.y)
            if let origin = physicalOrigin { physicalSelection(start: origin, translation: delta) }
        case .changed:
            if let origin = physicalOrigin { physicalSelection(start: origin, translation: recognizer.translation(in: self)) }
        case .ended, .cancelled, .failed:
            physicalPresses.removeValue(forKey: ObjectIdentifier(recognizer))
            guard let origin = physicalOrigin else { return }
            physicalSelection(start: origin, translation: recognizer.translation(in: self))
            selectionFinished(cancelled: recognizer.state != .ended); physicalOrigin = nil
        default: break
        }
    }
    /// Same state and ownership checks as hand input, with conventional physical
    /// button semantics rather than the hand scroll/hold interpretation.
    func physicalSelection(start: CGPoint, translation: CGPoint) {
        guard !interruptedSelection, session.canInput else { return }
        if !gesture.active {
            guard let point = remote(start) else { return }
            physicalPresses.removeAll()
            retireWheel()
            becomeFirstResponder(); self.start = start
            binding = (session.inputGeneration, session.crop, destination, bounds.size)
            apply(gesture.begin(target: point, local: start, time: ProcessInfo.processInfo.systemUptime, source: .pointer))
        }
        guard currentBinding else { cancelSelection(); return }
        apply(gesture.move(translation)); publish()
    }
    @objc private func hover(_ recognizer: UIHoverGestureRecognizer) {
        guard !interaction.adjusting, !session.pointerHeld, recognizer.state == .changed, let point = remote(recognizer.location(in: self)) else { return }
        session.pointer(point, mask: 0)
    }
    @objc private func wheel(_ recognizer: UIPanGestureRecognizer) {
        let delta = recognizer.translation(in: self); recognizer.setTranslation(.zero, in: self)
        // Completion belongs only to this admitted wheel sequence, even outside
        // the image. A late callback cannot retire a later hand selection.
        defer {
            if [.ended, .cancelled, .failed].contains(recognizer.state) { retireWheel() }
        }
        if recognizer.state == .began {
            retireWheel()
            guard session.canInput, !interaction.adjusting, !gesture.active, !session.pointerHeld,
                  interaction.contextTarget == nil, !interaction.dragArmed,
                  let target = remote(recognizer.location(in: self)) else { return }
            wheelBinding = (session.inputGeneration, session.crop, destination, bounds.size, target)
        }
        guard [.began, .changed, .ended].contains(recognizer.state), let owner = wheelBinding else { return }
        guard session.canInput, !interaction.adjusting, !gesture.active, !session.pointerHeld,
              interaction.contextTarget == nil, !interaction.dragArmed,
              owner.generation == session.inputGeneration, owner.crop == session.crop,
              owner.destination == destination, owner.viewport == bounds.size else { retireWheel(); return }
        guard remote(recognizer.location(in: self)) != nil else { return }
        session.scroll(owner.target, dx: delta.x, dy: delta.y)
    }
    private func retireWheel() {
        guard wheelBinding != nil else { return }
        wheelBinding = nil; session.finishScrolling()
    }
    @objc private func zoom(_ recognizer: UIPinchGestureRecognizer) {
        let scale = recognizer.scale; recognizer.scale = 1
        defer {
            if [.ended, .cancelled, .failed].contains(recognizer.state) { zoomBinding = nil }
        }
        guard interaction.adjusting, session.canInput, scale.isFinite, scale > 0 else { zoomBinding = nil; return }
        if recognizer.state == .began {
            let anchor = recognizer.location(in: self)
            guard remote(anchor) != nil else { zoomBinding = nil; return }
            zoomBinding = (session.inputGeneration, session.crop, bounds.size, anchor, session.zoom, session.pan)
        }
        guard [.began, .changed, .ended].contains(recognizer.state), let owner = zoomBinding else { return }
        guard owner.generation == session.inputGeneration, owner.crop == session.crop,
              owner.viewport == bounds.size, owner.zoom == session.zoom, owner.pan == session.pan else { zoomBinding = nil; return }
        adjustZoom(scale, anchor: owner.anchor)
        zoomBinding = (owner.generation, owner.crop, owner.viewport, owner.anchor, session.zoom, session.pan)
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { physical.handle(key, down: true) } }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { physical.handle(key, down: false) } }
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) { session.releaseInput() }
    override func becomeFirstResponder() -> Bool {
        interaction.transferringFocus = true; defer { interaction.transferringFocus = false }
        if window?.windowScene?.activationState == .foregroundActive, DirectAppLockV1.shared.canAccess { window?.makeKey() }
        return super.becomeFirstResponder()
    }
    override func resignFirstResponder() -> Bool {
        if interaction.transferringFocus { cancelSelection() }
        else { session.releaseInput(discardComposition: false) }
        return super.resignFirstResponder()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if viewport != bounds.size { viewport = bounds.size; session.releaseInput(); session.pan = VisionDesktopGeometry.clampedPan(session.pan, crop: session.crop, viewport: viewport, zoom: session.zoom); setNeedsDisplay() }
    }
}

@MainActor enum VisionHardwareKeys {
    static func symbol(_ key: UIKey) -> UInt32? {
        let special: [UIKeyboardHIDUsage: UInt32] = [.keyboardEscape: 0xff1b, .keyboardTab: 0xff09, .keyboardReturnOrEnter: 0xff0d,
            .keyboardDeleteOrBackspace: 0xff08, .keyboardDeleteForward: 0xffff, .keyboardLeftArrow: 0xff51, .keyboardUpArrow: 0xff52,
            .keyboardRightArrow: 0xff53, .keyboardDownArrow: 0xff54, .keyboardHome: 0xff50, .keyboardEnd: 0xff57,
            .keyboardPageUp: 0xff55, .keyboardPageDown: 0xff56, .keyboardLeftShift: 0xffe1, .keyboardRightShift: 0xffe2,
            .keyboardLeftControl: 0xffe3, .keyboardRightControl: 0xffe4, .keyboardLeftAlt: 0xffe9, .keyboardRightAlt: 0xffea,
            .keyboardLeftGUI: 0xffeb, .keyboardRightGUI: 0xffec]
        if let value = special[key.keyCode] { return value }
        let code = key.keyCode.rawValue
        if (UIKeyboardHIDUsage.keyboardF1.rawValue...UIKeyboardHIDUsage.keyboardF12.rawValue).contains(code) {
            return 0xffbe + UInt32(code - UIKeyboardHIDUsage.keyboardF1.rawValue)
        }
        guard let scalar = key.charactersIgnoringModifiers.unicodeScalars.first, key.charactersIgnoringModifiers.unicodeScalars.count == 1 else { return nil }
        return scalar.value < 256 ? scalar.value : 0x01000000 | scalar.value
    }
}

/// UITextInput owns IME/dictation locally. Only committed text leaves this view.
final class VisionCommittedTextView: UITextView, UITextViewDelegate {
    var activateOnAttachment = false
    var lostFocus: @MainActor () -> Void = {}
    var committed: @MainActor (String) -> Void = { _ in }
    var backspace: @MainActor () -> Void = {}
    var admission: @MainActor () -> Bool = { false }
    var physical = VisionPhysicalKeyboard()
    weak var interaction: VisionDesktopInteraction?
    var lastFocusRequest: UUID?
    private var cancelling = false
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        delegate = self; font = .preferredFont(forTextStyle: .body)
        autocorrectionType = .no; autocapitalizationType = .none; smartQuotesType = .no; smartDashesType = .no
        accessibilityLabel = "Type on the Mac"; accessibilityIdentifier = "vision-desktop-keyboard"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if activateOnAttachment, window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.admission(), self.interaction?.keyboardVisible != false else { return }
                self.becomeFirstResponder()
            }
        }
    }
    override func becomeFirstResponder() -> Bool {
        interaction?.transferringFocus = true; defer { interaction?.transferringFocus = false }
        if window?.windowScene?.activationState == .foregroundActive, DirectAppLockV1.shared.canAccess { window?.makeKey() }
        let result = super.becomeFirstResponder()
        if result { interaction?.keyboardFocused = true }
        updateFocusDiagnostic()
        return result
    }
    func textViewDidChange(_ view: UITextView) {
        guard !cancelling, markedTextRange == nil else { return }
        let value = text ?? ""; text = ""
        if admission(), !value.isEmpty { committed(value) }
    }
    override func deleteBackward() {
        if markedTextRange == nil, text.isEmpty { if admission() { backspace() } }
        else { super.deleteBackward() }
    }
    override func unmarkText() { super.unmarkText(); textViewDidChange(self) }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var remaining = presses
        if markedTextRange == nil {
            for press in presses {
                if let key = press.key, VisionPhysicalKeyboard.capturesForTextInput(key), admission() {
                    physical.handle(key, down: true); remaining.remove(press)
                }
            }
        }
        if !remaining.isEmpty { super.pressesBegan(remaining, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var remaining = presses
        for press in presses {
            if let key = press.key, physical.captured(key) {
                physical.handle(key, down: false); remaining.remove(press)
            }
        }
        if !remaining.isEmpty { super.pressesEnded(remaining, with: event) }
    }
    func discard() {
        _ = resignFirstResponder()
    }
    override func resignFirstResponder() -> Bool {
        let wasFocused = isFirstResponder
        cancelling = true
        if wasFocused, interaction?.transferringFocus != true { physical.clear() }
        setMarkedText(nil, selectedRange: .init(location: 0, length: 0)); text = ""
        let result = super.resignFirstResponder()
        cancelling = false
        if wasFocused { interaction?.keyboardFocused = false; lostFocus() }
        updateFocusDiagnostic()
        return result
    }
    private func updateFocusDiagnostic() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--vision-qa-empty-library") {
            accessibilityValue = isFirstResponder ? "Focused" : "Unfocused"
        }
        #endif
    }
}
struct VisionDesktopKeyboard: UIViewRepresentable {
    let session: VisionDesktopSession
    let interaction: VisionDesktopInteraction
    func makeUIView(context: Context) -> VisionCommittedTextView {
        let view = VisionCommittedTextView()
        view.interaction = interaction; view.physical = interaction.physicalKeyboard
        view.activateOnAttachment = true
        view.admission = { [weak view, weak session] in
            view?.window?.windowScene?.keyWindow != nil && session?.canInput == true
        }
        view.committed = { [weak session] in session?.text($0) }
        view.backspace = { [weak session] in session?.key(0xff08, down: true); session?.key(0xff08, down: false) }
        view.physical.send = { [weak session] key, down in session?.key(key, down: down) }
        view.lostFocus = { [weak session, weak interaction] in
            if interaction?.transferringFocus != true { session?.releaseInput(discardComposition: false) }
        }
        session.clearComposition = { [weak view] in view?.discard() }
        return view
    }
    func updateUIView(_ view: VisionCommittedTextView, context: Context) {
        guard view.lastFocusRequest != interaction.keyboardRequest else { return }
        view.lastFocusRequest = interaction.keyboardRequest
        let request = interaction.keyboardRequest
        DispatchQueue.main.async { [weak view, weak interaction] in
            guard let view, view.window != nil, view.admission(), interaction?.keyboardVisible == true,
                  interaction?.keyboardRequest == request else { return }
            _ = view.becomeFirstResponder()
        }
    }
    static func dismantleUIView(_ view: VisionCommittedTextView, coordinator: ()) { view.discard() }
}

final class VisionTerminalView: TerminalView {
    var lostFocus: @MainActor () -> Void = {}
    override init(frame: CGRect) { super.init(frame: frame); getTerminal().semanticPromptClickBehavior = .disabled }
    required init?(coder: NSCoder) { super.init(coder: coder); getTerminal().semanticPromptClickBehavior = .disabled }
    func discardComposition() { setMarkedText(nil, selectedRange: NSRange(location: 0, length: 0)); controlModifier = false; metaModifier = false }
    override func becomeFirstResponder() -> Bool {
        if window?.windowScene?.activationState == .foregroundActive, DirectAppLockV1.shared.canAccess { window?.makeKey() }
        return super.becomeFirstResponder()
    }
    override func resignFirstResponder() -> Bool { discardComposition(); lostFocus(); return super.resignFirstResponder() }
}
@MainActor @Observable final class VisionTerminalInteraction {
    var quickAction: (@MainActor (VNCQuickAction) -> Void)?
    var keyboard: (@MainActor () -> Void)?
    var dismissKeyboard: (@MainActor () -> Void)?
    var specialKey: (@MainActor (UInt32) -> Void)?
    var sendControl: (@MainActor (UInt8) -> Void)?
    var toggleModifier: (@MainActor (Bool) -> Void)?
    var control = false
    var option = false
    var link: URL?
}
struct VisionTerminalSurface: UIViewRepresentable {
    let session: DirectTerminalSession
    let interaction: VisionTerminalInteraction
    @Environment(DirectAppearanceV1.self) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeCoordinator() -> Coordinator { Coordinator(session: session, interaction: interaction) }
    func makeUIView(context: Context) -> VisionTerminalView {
        let view = VisionTerminalView(frame: .zero), coordinator = context.coordinator
        if reduceMotion { view.getTerminal().setCursorStyle(.steadyBlock) }
        coordinator.view = view; coordinator.focus.view = view; view.terminalDelegate = coordinator
        view.accessibilityIdentifier = "vision-terminal-canvas"
        view.inputAccessoryView = nil; view.font = .monospacedSystemFont(ofSize: 18, weight: .regular)
        session.inputAvailable = { [weak coordinator] in coordinator?.focus.available == true }
        session.received = { [weak coordinator] in coordinator?.feed($0) }
        session.suspendInput = { [weak coordinator] in coordinator?.release() }
        view.lostFocus = { [weak coordinator] in coordinator?.release() }
        interaction.quickAction = { [weak coordinator] in coordinator?.perform($0) }
        interaction.keyboard = { [weak view] in
            guard let view else { return }
            _ = view.becomeFirstResponder()
        }
        interaction.dismissKeyboard = { [weak view] in _ = view?.resignFirstResponder() }
        interaction.specialKey = { [weak coordinator] in coordinator?.specialKey($0) }
        interaction.sendControl = { [weak coordinator] byte in
            guard let coordinator, coordinator.focus.available, [3, 4].contains(byte) else { return }
            coordinator.release(); coordinator.view?.send(data: [byte])
        }
        interaction.toggleModifier = { [weak coordinator] control in
            guard let coordinator, coordinator.focus.available, let view = coordinator.view else { return }
            if control { view.controlModifier.toggle() } else { view.metaModifier.toggle() }
            coordinator.syncModifiers()
        }
        coordinator.focus.changed = { [weak coordinator] active in
            guard let coordinator else { return }
            if !active { coordinator.release() }
            else if let view = coordinator.view { coordinator.session.resize(columns: view.getTerminal().cols, rows: view.getTerminal().rows) }
        }
        return view
    }
    func updateUIView(_ view: VisionTerminalView, context: Context) {
        if reduceMotion { view.getTerminal().setCursorStyle(.steadyBlock) }
        let dark = appearance.terminal == .dark || (appearance.terminal == .app && view.traitCollection.userInterfaceStyle == .dark)
        view.nativeBackgroundColor = dark ? .black : .white; view.nativeForegroundColor = dark ? .white : .black
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 18, weight: .regular))
        if view.font.pointSize != font.pointSize { view.font = font }
    }
    static func dismantleUIView(_ view: VisionTerminalView, coordinator: Coordinator) {
        coordinator.release(); coordinator.focus.view = nil; coordinator.session.received = nil
        coordinator.session.inputAvailable = { false }; coordinator.session.suspendInput = nil
        coordinator.interaction.quickAction = nil; coordinator.interaction.keyboard = nil; coordinator.interaction.link = nil
        coordinator.interaction.dismissKeyboard = nil; coordinator.interaction.specialKey = nil; coordinator.interaction.toggleModifier = nil
        coordinator.interaction.sendControl = nil
    }
    @MainActor final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        let session: DirectTerminalSession
        let interaction: VisionTerminalInteraction
        weak var view: VisionTerminalView?
        let focus = VisionSurfaceFocus()
        private var held = MacTerminalHeldInput()
        private var protocolDepth = 0
        init(session: DirectTerminalSession, interaction: VisionTerminalInteraction) { self.session = session; self.interaction = interaction }
        func release() { view?.discardComposition(); session.releaseNativeInput(held.releaseAll()); interaction.link = nil; syncModifiers() }
        func syncModifiers() { interaction.control = view?.controlModifier == true; interaction.option = view?.metaModifier == true }
        func specialKey(_ symbol: UInt32) {
            guard focus.available, let view else { return }
            let modifiers: [UInt32] = (view.controlModifier ? [0xffe3] : []) + (view.metaModifier ? [0xffe9] : [])
            let action = VNCQuickAction(title: "Terminal Key", kind: .shortcut, key: symbol, modifiers: modifiers)
            guard action.valid else { return }
            let bytes = action.terminalBytes(applicationCursor: view.getTerminal().applicationCursor)
            release(); view.send(data: bytes[...])
        }
        func feed(_ bytes: [UInt8]) {
            protocolDepth += 1; defer { protocolDepth -= 1 }
            view?.feed(byteArray: bytes[...])
        }
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            if protocolDepth > 0 { session.send(Array(data), source: .emulatorReply); return }
            guard focus.available else { return }
            guard held.observe(data, keyboardEvents: source.getTerminal().keyboardEnhancementFlags.contains(.reportEvents)) else { session.failNativeInputAdmission(); return }
            session.send(Array(data))
            Task { @MainActor [weak self] in self?.syncModifiers() }
        }
        func perform(_ action: VNCQuickAction) {
            guard focus.available, action.enabled, action.valid, action.compatible(with: .terminal), let view,
                  !action.isCustom || DirectProAccess.shared.hasPro else { return }
            release()
            switch action.kind {
            case .interrupt: view.send(data: [3])
            case .escape: view.send(data: [27])
            case .tab: view.send(data: [9])
            case .returnKey: view.send(data: [13])
            case .shortcut: view.send(data: action.terminalBytes(applicationCursor: view.getTerminal().applicationCursor)[...])
            case .text: paste(action.text, view: view)
            case .paste: if let value = UIPasteboard.general.string { paste(value, view: view) }
            default: break
            }
        }
        private func paste(_ value: String, view: TerminalView) {
            guard value.utf8.count <= 16_384 else { return }
            let text = view.getTerminal().bracketedPasteMode ? "\u{1b}[200~" + value + "\u{1b}[201~" : value
            view.send(data: Array(text.utf8)[...])
        }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { session.resize(columns: newCols, rows: newRows) }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard focus.available, let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil, url.user == nil, url.password == nil else { return }
            interaction.link = url
        }
        func bell(source: TerminalView) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func clipboardRead(source: TerminalView) -> Data? { nil }
    }
}
#endif
