#if os(iOS)
import CompanionInteractiveClient
import CompanionInteractiveWire
import CoreGraphics
import Foundation
import UIKit

public enum UIKitClientLiveSurfaceFailureV0: Error, Equatable, Sendable {
    case invalidGeometry
    case invalidGesture
}

/// Stateless software-keyboard bridge. UIKit owns any marked/composition
/// state; this view never retains entered text, selection, or field content.
@MainActor
private final class UIKitClientKeyboardProxyV0: UIView, UIKeyInput {
    private let submit: (ClientKeyboardActionV0) -> Void

    init(submit: @escaping (ClientKeyboardActionV0) -> Void) {
        self.submit = submit
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var canBecomeFirstResponder: Bool { true }
    // Keep Delete available without retaining a local mirror of remote text.
    var hasText: Bool { true }

    func insertText(_ text: String) {
        guard let action = UIKitClientInputAdapterV0.keyboardAction(
            for: text
        ) else { return }
        submit(action)
    }

    func deleteBackward() { submit(.deleteBackward) }
}

@MainActor
public final class UIKitClientLiveSurfaceViewV0:
    UIView,
    UIGestureRecognizerDelegate
{
    public let videoView = UIKitClientVideoSurfaceViewV0(frame: .zero)

    private var mapper: ClientViewportInputMapperV0?
    private var mode: ClientInputInteractionModeV0
    private var encodedWidth: UInt16 = 0
    private var encodedHeight: UInt16 = 0
    private var inputEnabled = false
    private var visualZoomEditing = false
    private var visualZoomScale = 1.0
    private var visualZoomTranslation = CGPoint.zero
    private var visualZoomStartScale = 1.0
    private var visualZoomViewportSize = CGSize.zero
    private var dragRecognizer: UILongPressGestureRecognizer!
    private var visualZoomPinchRecognizer: UIPinchGestureRecognizer!
    private var visualZoomPanRecognizer: UIPanGestureRecognizer!
    private var dragLastLocation: CGPoint?
    private lazy var keyboardProxy = UIKitClientKeyboardProxyV0 {
        [weak self] action in self?.submitKeyboardAction(action)
    }
    private let onPayloads: ([InteractiveInputPayload]) -> Void
    private let onFailure: (UIKitClientLiveSurfaceFailureV0) -> Void

    public init(
        mode: ClientInputInteractionModeV0,
        onPayloads: @escaping ([InteractiveInputPayload]) -> Void,
        onFailure: @escaping (UIKitClientLiveSurfaceFailureV0) -> Void
    ) {
        self.mode = mode
        self.onPayloads = onPayloads
        self.onFailure = onFailure
        super.init(frame: .zero)
        backgroundColor = .black
        addSubview(videoView)
        addSubview(keyboardProxy)
        installRecognizers()
        setInputEnabled(false)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if visualZoomViewportSize != bounds.size {
            resetMapper()
            visualZoomViewportSize = bounds.size
            resetVisualZoomState()
        }
        videoView.bounds = CGRect(origin: .zero, size: bounds.size)
        videoView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        applyVisualZoomTransform()
        if !visualZoomEditing { rebuildMapperForCurrentGeometry() }
    }

    public func setMode(_ value: ClientInputInteractionModeV0) {
        guard mode != value else { return }
        resetMapper()
        mode = value
        setNeedsLayout()
    }

    public func setEncodedDimensions(width: UInt16, height: UInt16) {
        guard encodedWidth != width || encodedHeight != height else { return }
        resetMapper()
        encodedWidth = width
        encodedHeight = height
        resetVisualZoomState()
        setNeedsLayout()
    }

    public func setInputEnabled(_ value: Bool) {
        if !value {
            keyboardProxy.resignFirstResponder()
            resetMapper()
            visualZoomEditing = false
            resetVisualZoomState()
        }
        guard inputEnabled != value else { return }
        inputEnabled = value
        isUserInteractionEnabled = value
        if value { setNeedsLayout() }
    }

    public func resetInputAndBlank() {
        keyboardProxy.resignFirstResponder()
        resetMapper()
        visualZoomEditing = false
        resetVisualZoomState()
        inputEnabled = false
        isUserInteractionEnabled = false
        videoView.blank()
    }

    public func toggleSoftwareKeyboard() {
        guard inputEnabled else { return }
        if keyboardProxy.isFirstResponder {
            keyboardProxy.resignFirstResponder()
        } else {
            keyboardProxy.becomeFirstResponder()
        }
    }

    public func hideSoftwareKeyboard() {
        keyboardProxy.resignFirstResponder()
    }

    /// Enters a local visual-editing mode. Remote input is reset before the
    /// view begins consuming pinch/pan gestures and remains suppressed until
    /// editing ends; this never changes the selected host surface or fence.
    public func setVisualZoomEditing(_ value: Bool) {
        let next = value && inputEnabled
        guard visualZoomEditing != next else { return }
        keyboardProxy.resignFirstResponder()
        resetMapper()
        visualZoomEditing = next
        if !next { rebuildMapperForCurrentGeometry() }
    }

    public func resetVisualZoom() {
        resetMapper()
        resetVisualZoomState()
        if !visualZoomEditing { rebuildMapperForCurrentGeometry() }
    }

    private func rebuildMapperForCurrentGeometry() {
        guard inputEnabled, bounds.width > 0, bounds.height > 0,
              encodedWidth > 0, encodedHeight > 0 else { return }
        do {
            let viewport = try ClientInputRectV0(
                x: 0,
                y: 0,
                width: Double(bounds.width),
                height: Double(bounds.height)
            )
            let content = try ClientAspectFitGeometryV0.contentRect(
                viewport: viewport,
                encodedWidth: encodedWidth,
                encodedHeight: encodedHeight
            )
            if mapper?.viewport != viewport || mapper?.content != content {
                resetMapper()
                mapper = try ClientViewportInputMapperV0(
                    viewport: viewport,
                    content: content,
                    mode: mode
                )
            }
        } catch {
            setInputEnabled(false)
            onFailure(.invalidGeometry)
        }
    }

    private func resetMapper() {
        if var mapper {
            emit([mapper.reset()])
        }
        mapper = nil
        dragLastLocation = nil
    }

    private func installRecognizers() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        let pointerPan = UIPanGestureRecognizer(
            target: self,
            action: #selector(pointerPanned(_:))
        )
        pointerPan.maximumNumberOfTouches = 1
        let scrollPan = UIPanGestureRecognizer(
            target: self,
            action: #selector(scrolled(_:))
        )
        scrollPan.minimumNumberOfTouches = 2
        scrollPan.maximumNumberOfTouches = 2
        let drag = UILongPressGestureRecognizer(
            target: self,
            action: #selector(dragged(_:))
        )
        drag.minimumPressDuration = 0.35
        let zoomPinch = UIPinchGestureRecognizer(
            target: self,
            action: #selector(visualZoomPinched(_:))
        )
        let zoomPan = UIPanGestureRecognizer(
            target: self,
            action: #selector(visualZoomPanned(_:))
        )
        zoomPan.minimumNumberOfTouches = 1
        zoomPan.maximumNumberOfTouches = 2
        drag.delegate = self
        pointerPan.delegate = self
        scrollPan.delegate = self
        tap.delegate = self
        zoomPinch.delegate = self
        zoomPan.delegate = self
        tap.require(toFail: drag)
        addGestureRecognizer(tap)
        addGestureRecognizer(pointerPan)
        addGestureRecognizer(scrollPan)
        addGestureRecognizer(drag)
        addGestureRecognizer(zoomPinch)
        addGestureRecognizer(zoomPan)
        dragRecognizer = drag
        visualZoomPinchRecognizer = zoomPinch
        visualZoomPanRecognizer = zoomPan
    }

    public override func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let isVisualZoomGesture = gestureRecognizer
            === visualZoomPinchRecognizer
            || gestureRecognizer === visualZoomPanRecognizer
        if isVisualZoomGesture {
            return inputEnabled && visualZoomEditing
        }
        return inputEnabled && !visualZoomEditing
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer:
            UIGestureRecognizer
    ) -> Bool {
        let zoomPair = visualZoomEditing
            && (gestureRecognizer === visualZoomPinchRecognizer
                || gestureRecognizer === visualZoomPanRecognizer)
            && (otherGestureRecognizer === visualZoomPinchRecognizer
                || otherGestureRecognizer === visualZoomPanRecognizer)
        if zoomPair { return true }
        return gestureRecognizer === dragRecognizer
            || otherGestureRecognizer === dragRecognizer
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        withMapper { mapper in
            switch mapper.mode {
            case .directTouch:
                return try mapper.tap(at: try mappedDirectLocation(recognizer))
            case .trackpad:
                return try mapper.tap()
            }
        }
    }

    @objc private func pointerPanned(_ recognizer: UIPanGestureRecognizer) {
        guard dragRecognizer.state != .began,
              dragRecognizer.state != .changed,
              recognizer.state == .began
                || recognizer.state == .changed
                || recognizer.state == .ended else {
            return
        }
        withMapper { mapper in
            let payload: InteractiveInputPayload
            switch mapper.mode {
            case .directTouch:
                payload = try mapper.directMove(to:
                    mappedDirectLocation(recognizer)
                )
            case .trackpad:
                payload = try mapper.trackpadMove(delta:
                    mappedTrackpadDelta(recognizer)
                )
            }
            return [payload]
        }
    }

    @objc private func scrolled(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .began
                || recognizer.state == .changed
                || recognizer.state == .ended else {
            return
        }
        withMapper { mapper in
            let delta = try UIKitClientInputAdapterV0.consumeTranslation(
                of: recognizer,
                in: self
            )
            guard delta.x != 0 || delta.y != 0 else { return [] }
            return [try mapper.scroll(delta: delta)]
        }
    }

    @objc private func dragged(_ recognizer: UILongPressGestureRecognizer) {
        withMapper { mapper in
            let location = recognizer.location(in: self)
            switch recognizer.state {
            case .began:
                dragLastLocation = location
                switch mapper.mode {
                case .directTouch:
                    return try mapper.beginDirectDrag(at:
                        mappedDirectLocation(recognizer)
                    )
                case .trackpad:
                    return try mapper.beginTrackpadDrag()
                }
            case .changed:
                let payload: InteractiveInputPayload
                switch mapper.mode {
                case .directTouch:
                    payload = try mapper.updateDirectDrag(to:
                        mappedDirectLocation(recognizer)
                    )
                case .trackpad:
                    guard let previous = dragLastLocation else {
                        throw UIKitClientLiveSurfaceFailureV0.invalidGesture
                    }
                    payload = try mapper.updateTrackpadDrag(delta:
                        makeVisualZoomTransform().mappingDeltaToUnzoomed(
                            ClientInputPointV0(
                                x: Double(location.x - previous.x),
                                y: Double(location.y - previous.y)
                            )
                        )
                    )
                }
                dragLastLocation = location
                return [payload]
            case .ended:
                dragLastLocation = nil
                return [try mapper.endDrag()]
            case .cancelled, .failed:
                dragLastLocation = nil
                return [mapper.reset()]
            case .possible:
                return []
            @unknown default:
                dragLastLocation = nil
                return [mapper.reset()]
            }
        }
    }

    @objc private func visualZoomPinched(
        _ recognizer: UIPinchGestureRecognizer
    ) {
        guard inputEnabled, visualZoomEditing else { return }
        do {
            if recognizer.state == .began {
                visualZoomStartScale = visualZoomScale
            }
            guard recognizer.state == .began
                    || recognizer.state == .changed
                    || recognizer.state == .ended else { return }
            let current = try makeVisualZoomTransform()
            let next = try current.zoomed(
                to: visualZoomStartScale * Double(recognizer.scale),
                around: try UIKitClientInputAdapterV0.point(
                    recognizer.location(in: self)
                )
            )
            acceptVisualZoomTransform(next)
        } catch {
            failVisualZoomGeometry()
        }
    }

    @objc private func visualZoomPanned(
        _ recognizer: UIPanGestureRecognizer
    ) {
        guard inputEnabled, visualZoomEditing,
              (recognizer.state == .began
                || recognizer.state == .changed
                || recognizer.state == .ended) else { return }
        do {
            let delta = try UIKitClientInputAdapterV0.consumeTranslation(
                of: recognizer,
                in: self
            )
            let current = try makeVisualZoomTransform()
            acceptVisualZoomTransform(try current.panned(by: delta))
        } catch {
            failVisualZoomGeometry()
        }
    }

    private func mappedDirectLocation(
        _ recognizer: UIGestureRecognizer
    ) throws -> ClientInputPointV0 {
        let point = try UIKitClientInputAdapterV0.point(
            recognizer.location(in: self)
        )
        return try makeVisualZoomTransform().mappingToUnzoomed(point)
    }

    private func mappedTrackpadDelta(
        _ recognizer: UIPanGestureRecognizer
    ) throws -> ClientInputPointV0 {
        let delta = try UIKitClientInputAdapterV0.consumeTranslation(
            of: recognizer,
            in: self
        )
        return try makeVisualZoomTransform()
            .mappingDeltaToUnzoomed(delta)
    }

    private func makeVisualZoomTransform() throws
        -> ClientVisualZoomTransformV0
    {
        let viewport = try ClientInputRectV0(
            x: 0,
            y: 0,
            width: Double(bounds.width),
            height: Double(bounds.height)
        )
        let content = try ClientAspectFitGeometryV0.contentRect(
            viewport: viewport,
            encodedWidth: encodedWidth,
            encodedHeight: encodedHeight
        )
        return try ClientVisualZoomTransformV0(
            viewport: viewport,
            content: content,
            scale: visualZoomScale,
            translation: ClientInputPointV0(
                x: Double(visualZoomTranslation.x),
                y: Double(visualZoomTranslation.y)
            )
        )
    }

    private func acceptVisualZoomTransform(
        _ value: ClientVisualZoomTransformV0
    ) {
        visualZoomScale = value.scale
        visualZoomTranslation = CGPoint(
            x: value.translation.x,
            y: value.translation.y
        )
        applyVisualZoomTransform()
    }

    private func resetVisualZoomState() {
        visualZoomScale = 1
        visualZoomTranslation = .zero
        visualZoomStartScale = 1
        applyVisualZoomTransform()
    }

    private func applyVisualZoomTransform() {
        videoView.transform = CGAffineTransform(
            a: visualZoomScale,
            b: 0,
            c: 0,
            d: visualZoomScale,
            tx: visualZoomTranslation.x,
            ty: visualZoomTranslation.y
        )
    }

    private func failVisualZoomGeometry() {
        setInputEnabled(false)
        onFailure(.invalidGeometry)
    }

    private func withMapper(
        _ body: (inout ClientViewportInputMapperV0) throws
            -> [InteractiveInputPayload]
    ) {
        guard inputEnabled, var mapper else { return }
        do {
            let payloads = try body(&mapper)
            self.mapper = mapper
            emit(payloads)
        } catch {
            self.mapper = mapper
            setInputEnabled(false)
            onFailure(.invalidGesture)
        }
    }

    private func submitKeyboardAction(_ action: ClientKeyboardActionV0) {
        guard inputEnabled else { return }
        do { emit(try action.payloads()) }
        catch {
            setInputEnabled(false)
            onFailure(.invalidGesture)
        }
    }

    private func emit(_ payloads: [InteractiveInputPayload]) {
        guard !payloads.isEmpty else { return }
        onPayloads(payloads)
    }
}

@MainActor
public final class UIKitClientLiveSurfaceSessionV0 {
    public let view: UIKitClientLiveSurfaceViewV0
    public let decoder: UIKitClientDecodeRenderCoordinatorV0

    public init(
        mode: ClientInputInteractionModeV0,
        onPayloads: @escaping ([InteractiveInputPayload]) -> Void,
        onFailure: @escaping (UIKitClientLiveSurfaceFailureV0) -> Void
    ) {
        let view = UIKitClientLiveSurfaceViewV0(
            mode: mode,
            onPayloads: onPayloads,
            onFailure: onFailure
        )
        self.view = view
        decoder = UIKitClientDecodeRenderCoordinatorV0(
            renderer: view.videoView
        )
    }

    public func interruptAndBlank() {
        view.resetInputAndBlank()
        decoder.interruptAndBlank()
    }
}
#endif
