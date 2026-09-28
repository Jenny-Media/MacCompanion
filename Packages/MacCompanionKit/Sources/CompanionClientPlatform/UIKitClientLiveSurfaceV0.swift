#if os(iOS)
import CompanionClientNetworkPlatform
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CoreGraphics
import Foundation
import UIKit

public enum UIKitClientLiveSurfaceFailureV0: Error, Equatable, Sendable {
    case invalidGeometry
    case invalidGesture
}

package enum UIKitClientTwoFingerPanDestinationV0: Equatable, Sendable {
    case remoteScroll
    case localViewport
}

package enum UIKitClientVisualZoomGesturePolicyV0 {
    package static func twoFingerPanDestination(
        visualZoomScale: Double
    ) -> UIKitClientTwoFingerPanDestinationV0 {
        visualZoomScale > 1.000_1 ? .localViewport : .remoteScroll
    }
}

/// Compact controls that remain available above the native iOS keyboard.
/// These are physical-key actions, so they do not depend on editable-focus
/// metadata and never enter the sentinel-backed text field.
@MainActor
private final class UIKitClientKeyboardAccessoryV0: UIInputView {
    private let submit: (ClientKeyboardActionV0) -> Void
    private let dismissKeyboard: () -> Void
    private let keyControl = UISegmentedControl(
        items: ["esc", "tab", "←", "↓", "↑", "→", "⌫"]
    )

    init(
        submit: @escaping (ClientKeyboardActionV0) -> Void,
        dismissKeyboard: @escaping () -> Void
    ) {
        self.submit = submit
        self.dismissKeyboard = dismissKeyboard
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
        allowsSelfSizing = true

        keyControl.selectedSegmentIndex = UISegmentedControl.noSegment
        keyControl.addTarget(
            self,
            action: #selector(keySelected),
            for: .valueChanged
        )
        keyControl.accessibilityLabel = "Remote keyboard controls"

        let dismissButton = UIButton(type: .system)
        dismissButton.setImage(
            UIImage(systemName: "keyboard.chevron.compact.down"),
            for: .normal
        )
        dismissButton.accessibilityLabel = "Hide Keyboard"
        dismissButton.addTarget(
            self,
            action: #selector(dismissSelected),
            for: .touchUpInside
        )

        let stack = UIStackView(arrangedSubviews: [
            keyControl,
            dismissButton,
        ])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -8
            ),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            dismissButton.widthAnchor.constraint(equalToConstant: 42),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }

    @objc private func keySelected() {
        let action: ClientKeyboardActionV0? = switch
            keyControl.selectedSegmentIndex
        {
        case 0: .escape
        case 1: .tab
        case 2: .arrowLeft
        case 3: .arrowDown
        case 4: .arrowUp
        case 5: .arrowRight
        case 6: .deleteBackward
        default: nil
        }
        keyControl.selectedSegmentIndex = UISegmentedControl.noSegment
        if let action { submit(action) }
    }

    @objc private func dismissSelected() {
        dismissKeyboard()
    }
}

/// Stateless software-keyboard bridge backed by a real UIKit text client.
///
/// A bare `UIKeyInput` view is insufficient on physical iOS devices: the
/// system keyboard can retain ordinary characters for prediction/composition
/// while committing delimiter keys such as Space independently. This field
/// gives UIKit the concrete editing client it expects, but rejects every
/// proposed mutation in its delegate. Its backing value therefore remains a
/// fixed, non-user sentinel and entered text is forwarded without being
/// retained as field content.
@MainActor
private final class UIKitClientKeyboardProxyV0:
    UITextField,
    UITextFieldDelegate
{
    private static let sentinel = "\u{2060}"
    private let submit: (ClientKeyboardActionV0) -> Void
    private lazy var keyboardAccessory = UIKitClientKeyboardAccessoryV0(
        submit: { [weak self] action in self?.submit(action) },
        dismissKeyboard: { [weak self] in self?.resignFirstResponder() }
    )

    init(submit: @escaping (ClientKeyboardActionV0) -> Void) {
        self.submit = submit
        super.init(frame: .zero)
        delegate = self
        text = Self.sentinel
        backgroundColor = .clear
        borderStyle = .none
        textColor = .clear
        tintColor = .clear
        isAccessibilityElement = false
        autocapitalizationType = .none
        autocorrectionType = .no
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        inlinePredictionType = .no
        inputAccessoryView = keyboardAccessory
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func becomeFirstResponder() -> Bool {
        restoreSentinel()
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder { restoreSentinel() }
        return becameFirstResponder
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        guard textField === self else { return false }
        defer { restoreSentinel() }
        if string.isEmpty {
            submit(.deleteBackward)
        } else if let action = UIKitClientInputAdapterV0.keyboardAction(
            for: string
        ) {
            submit(action)
        }
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard textField === self else { return false }
        submit(.returnKey)
        restoreSentinel()
        return false
    }

    private func restoreSentinel() {
        text = Self.sentinel
        selectedTextRange = textRange(
            from: endOfDocument,
            to: endOfDocument
        )
    }
}

@MainActor
public final class UIKitClientLiveSurfaceViewV0:
    UIView,
    UIGestureRecognizerDelegate
{
    public let videoView = UIKitClientVideoSurfaceViewV0(frame: .zero)
    private var webRTCVideoView: UIView?
    private var nativeVideoView: UIView?
    private var nativeContentGeometry: InteractiveNativeVideoContentGeometryV0?
    private var nativeInputCurrent: (@MainActor () -> Bool)?
    private var canDispatchInput: Bool { inputEnabled && !hasUnverifiedExternalVideo }

    private var mapper: ClientViewportInputMapperV0?
    private var mode: ClientInputInteractionModeV0
    private var encodedWidth: UInt16 = 0
    private var encodedHeight: UInt16 = 0
    private var inputEnabled = false
    private var visualZoomScale = 1.0
    private var visualZoomTranslation = CGPoint.zero
    private var visualZoomStartScale = 1.0
    private var visualZoomViewportSize = CGSize.zero
    private var visualZoomOutPastFitLatched = false
    private var dragRecognizer: UILongPressGestureRecognizer!
    private var visualZoomPinchRecognizer: UIPinchGestureRecognizer!
    private var visualZoomPanRecognizer: UIPanGestureRecognizer!
    private var dragLastLocation: CGPoint?
    private var onZoomOutPastFit: (() -> Void)?
    private var onManualViewportChange: (() -> Void)?
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
        // The proxy must participate in the view hierarchy as a concrete text
        // client, but it must never cover pixels or become a touch target.
        keyboardProxy.frame = CGRect(x: -2, y: -2, width: 1, height: 1)
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
        rebuildMapperForCurrentGeometry()
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
        if nativeVideoView != nil {
            nativeContentGeometry = nil
            nativeInputCurrent = nil
            setInputEnabled(false)
        }
        encodedWidth = width
        encodedHeight = height
        resetVisualZoomState()
        setNeedsLayout()
    }

    public func setInputEnabled(_ value: Bool) {
        if value, hasUnverifiedExternalVideo { return }
        if !value {
            keyboardProxy.resignFirstResponder()
            resetMapper()
            resetVisualZoomState()
        }
        // UIKit defaults to enabled even before our first admitted input frame.
        // Enforce the view state when the cached logical value is unchanged.
        isUserInteractionEnabled = value
        guard inputEnabled != value else { return }
        inputEnabled = value
        if value { setNeedsLayout() }
    }

    public func resetInputAndBlank() {
        keyboardProxy.resignFirstResponder()
        resetMapper()
        resetVisualZoomState()
        inputEnabled = false
        isUserInteractionEnabled = false
        videoView.blank()
        removeWebRTCVideoView()
        removeNativeVideoView()
    }

    /// The WebRTC receiver is installed only for the current negotiated peer.
    /// Its own frame sink reveals the view after the first admitted frame.
    public func installWebRTCVideoView(_ view: UIView) {
        guard nativeVideoView == nil else { return }
        removeWebRTCVideoView()
        setInputEnabled(false)
        view.frame = videoView.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isHidden = true
        videoView.addSubview(view)
        webRTCVideoView = view
    }

    public var hasUnverifiedWebRTCVideo: Bool {
        webRTCVideoView != nil
    }

    public var hasUnverifiedExternalVideo: Bool {
        webRTCVideoView != nil || (nativeVideoView != nil && nativeInputCurrent?() != true)
    }

    /// An injected native driver owns decoding. This slot remains input-disabled
    /// until a native presentation proof is admitted by the Control authority.
    @discardableResult
    public func installNativeVideoView(_ view: UIView) -> Bool {
        guard webRTCVideoView == nil, nativeVideoView == nil else { return false }
        setInputEnabled(false)
        view.frame = videoView.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isHidden = true
        videoView.addSubview(view)
        nativeVideoView = view
        return true
    }

    package func stageNativeInputGeometry(_ geometry: InteractiveNativeVideoContentGeometryV0,
        expectedView: UIView, isCurrent: @escaping @MainActor () -> Bool) throws {
        guard nativeVideoView === expectedView, webRTCVideoView == nil,
              geometry.encodedWidth == Int(encodedWidth), geometry.encodedHeight == Int(encodedHeight) else {
            throw UIKitClientLiveSurfaceFailureV0.invalidGeometry
        }
        resetMapper()
        nativeContentGeometry = geometry; nativeInputCurrent = isCurrent
    }
    package func clearNativeInputAdmission(_ expectedView: UIView) {
        guard nativeVideoView === expectedView else { return }
        nativeContentGeometry = nil; nativeInputCurrent = nil
        setInputEnabled(false)
    }

    public func removeNativeVideoView(_ expected: UIView? = nil) {
        if let expected, nativeVideoView !== expected { return }
        nativeContentGeometry = nil; nativeInputCurrent = nil
        nativeVideoView?.isHidden = true
        nativeVideoView?.removeFromSuperview()
        nativeVideoView = nil
    }

    public func removeWebRTCVideoView(_ expected: UIView? = nil) {
        if let expected, webRTCVideoView !== expected { return }
        webRTCVideoView?.removeFromSuperview()
        webRTCVideoView = nil
    }

    public func toggleSoftwareKeyboard() {
        guard canDispatchInput else { return }
        if keyboardProxy.isFirstResponder {
            keyboardProxy.resignFirstResponder()
        } else {
            _ = keyboardProxy.becomeFirstResponder()
        }
    }

    public var isSoftwareKeyboardVisible: Bool {
        keyboardProxy.isFirstResponder
    }

    public func hideSoftwareKeyboard() {
        keyboardProxy.resignFirstResponder()
    }

    public var isVisuallyZoomed: Bool {
        visualZoomScale > 1.000_1
    }

    public func resetVisualZoom(animated: Bool = false) {
        resetMapper()
        resetVisualZoomState(animated: animated)
        rebuildMapperForCurrentGeometry()
    }

    /// Smoothly frames a verified host focus inside the current surface. This
    /// changes only the local viewport; it does not replace the capture source
    /// or alter the acknowledged input fence.
    @discardableResult
    public func focusVisualZoom(
        on bounds: NormalizedSurfaceRect,
        animated: Bool = true
    ) -> Bool {
        guard canDispatchInput, self.bounds.width > 0, self.bounds.height > 0,
              encodedWidth > 0, encodedHeight > 0 else {
            IOSClientRuntimeDiagnosticLogV0.record(
                "ui.automatic-visual-zoom.deferred-geometry"
            )
            return false
        }
        do {
            resetMapper()
            let current = try makeVisualZoomTransform()
            acceptVisualZoomTransform(
                try current.focused(onNormalized: bounds),
                animated: animated
            )
            rebuildMapperForCurrentGeometry()
            return true
        } catch {
            // Automatic Smart Zoom is local presentation only. A stale focus
            // rectangle or transient UIKit geometry must never close the
            // authenticated Control roles. Return to fit and wait for the next
            // verified focus refresh.
            IOSClientRuntimeDiagnosticLogV0.record(
                "ui.automatic-visual-zoom.recovered",
                error: error
            )
            resetVisualZoomState()
            rebuildMapperForCurrentGeometry()
            return false
        }
    }

    public func setZoomOutPastFitHandler(
        _ handler: (() -> Void)?
    ) {
        onZoomOutPastFit = handler
    }

    public func setManualViewportChangeHandler(
        _ handler: (() -> Void)?
    ) {
        onManualViewportChange = handler
    }

    private func rebuildMapperForCurrentGeometry() {
        guard canDispatchInput, bounds.width > 0, bounds.height > 0,
              encodedWidth > 0, encodedHeight > 0 else { return }
        do {
            let viewport = try ClientInputRectV0(
                x: 0,
                y: 0,
                width: Double(bounds.width),
                height: Double(bounds.height)
            )
            let content: ClientInputRectV0
            if let nativeContentGeometry {
                content = try ClientAspectFitGeometryV0.nativeContentRect(viewport: viewport, geometry: nativeContentGeometry)
            } else {
                content = try ClientAspectFitGeometryV0.contentRect(viewport: viewport,
                    encodedWidth: encodedWidth, encodedHeight: encodedHeight)
            }
            if mapper?.viewport != viewport || mapper?.content != content {
                resetMapper()
                mapper = try ClientViewportInputMapperV0(
                    viewport: viewport,
                    content: content,
                    mode: mode
                )
            }
        } catch {
            // View bounds can be transiently inconsistent while SwiftUI
            // changes chrome, safe-area, or rotation geometry. Without a
            // mapper no remote input can be emitted, so this is a local
            // presentation outage rather than a reason to revoke the healthy
            // authenticated Control session. A later layout pass rebuilds it.
            resetMapper()
            IOSClientRuntimeDiagnosticLogV0.record(
                "ui.mapper-geometry.recovered",
                error: error
            )
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
        let doubleTap = UITapGestureRecognizer(
            target: self,
            action: #selector(doubleTapped(_:))
        )
        doubleTap.numberOfTapsRequired = 2
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
        zoomPan.minimumNumberOfTouches = 2
        zoomPan.maximumNumberOfTouches = 2
        drag.delegate = self
        pointerPan.delegate = self
        scrollPan.delegate = self
        tap.delegate = self
        doubleTap.delegate = self
        zoomPinch.delegate = self
        zoomPan.delegate = self
        tap.require(toFail: doubleTap)
        tap.require(toFail: drag)
        doubleTap.require(toFail: drag)
        addGestureRecognizer(tap)
        addGestureRecognizer(doubleTap)
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
        guard canDispatchInput else { return false }
        if gestureRecognizer === visualZoomPinchRecognizer {
            return true
        }
        if gestureRecognizer === visualZoomPanRecognizer {
            return UIKitClientVisualZoomGesturePolicyV0
                .twoFingerPanDestination(visualZoomScale: visualZoomScale)
                == .localViewport
                || visualZoomPinchRecognizer.state == .began
                || visualZoomPinchRecognizer.state == .changed
        }
        if let pan = gestureRecognizer as? UIPanGestureRecognizer,
           pan.minimumNumberOfTouches == 2,
           gestureRecognizer !== visualZoomPanRecognizer {
            return UIKitClientVisualZoomGesturePolicyV0
                .twoFingerPanDestination(visualZoomScale: visualZoomScale)
                == .remoteScroll
        }
        return true
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer:
            UIGestureRecognizer
    ) -> Bool {
        let firstIsPinch = gestureRecognizer === visualZoomPinchRecognizer
        let secondIsPinch = otherGestureRecognizer
            === visualZoomPinchRecognizer
        let firstIsTwoFingerPan = (gestureRecognizer
            as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2
        let secondIsTwoFingerPan = (otherGestureRecognizer
            as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2
        let zoomPair = (firstIsPinch && secondIsTwoFingerPan)
            || (secondIsPinch && firstIsTwoFingerPan)
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

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        withMapper { mapper in
            switch mapper.mode {
            case .directTouch:
                return try mapper.doubleTap(
                    at: try mappedDirectLocation(recognizer)
                )
            case .trackpad:
                return try mapper.doubleTap()
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
        if recognizer.state == .changed {
            panVisualZoomTowardEdgeIfNeeded(
                location: recognizer.location(in: self)
            )
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
        // A recognized pinch owns the same two touches locally. Suppress the
        // scroll recognizer rather than sending an accidental remote scroll.
        if visualZoomPinchRecognizer.state == .began
            || visualZoomPinchRecognizer.state == .changed
        {
            _ = recognizer.translation(in: self)
            recognizer.setTranslation(.zero, in: self)
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
        if recognizer.state == .changed {
            panVisualZoomTowardEdgeIfNeeded(
                location: recognizer.location(in: self)
            )
        }
        withMapper { mapper in
            let location = recognizer.location(in: self)
            switch recognizer.state {
            case .began:
                let payloads: [InteractiveInputPayload]
                switch mapper.mode {
                case .directTouch:
                    payloads = try mapper.beginDirectDrag(at:
                        mappedDirectLocation(recognizer)
                    )
                case .trackpad:
                    payloads = try mapper.beginTrackpadDrag()
                }
                dragLastLocation = location
                return payloads
            case .changed:
                guard mapper.heldDragButton != nil else {
                    dragLastLocation = nil
                    return []
                }
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
                guard mapper.heldDragButton != nil else {
                    dragLastLocation = nil
                    return []
                }
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
        guard canDispatchInput else { return }
        do {
            if recognizer.state == .began {
                resetMapper()
                onManualViewportChange?()
                visualZoomStartScale = visualZoomScale
                visualZoomOutPastFitLatched = false
            }
            guard recognizer.state == .began
                    || recognizer.state == .changed
                    || recognizer.state == .ended
                    || recognizer.state == .cancelled else { return }
            let requestedScale = visualZoomStartScale
                * Double(recognizer.scale)
            if requestedScale < 0.82,
               !visualZoomOutPastFitLatched {
                visualZoomOutPastFitLatched = true
                onZoomOutPastFit?()
            }
            let current = try makeVisualZoomTransform()
            let next = try current.zoomed(
                to: requestedScale,
                around: try UIKitClientInputAdapterV0.point(
                    recognizer.location(in: self)
                )
            )
            acceptVisualZoomTransform(next)
            if recognizer.state == .ended
                || recognizer.state == .cancelled
            {
                rebuildMapperForCurrentGeometry()
            }
        } catch {
            failVisualZoomGeometry(error)
        }
    }

    @objc private func visualZoomPanned(
        _ recognizer: UIPanGestureRecognizer
    ) {
        guard canDispatchInput,
              UIKitClientVisualZoomGesturePolicyV0.twoFingerPanDestination(
                visualZoomScale: visualZoomScale
              ) == .localViewport,
              (recognizer.state == .began
                || recognizer.state == .changed
                || recognizer.state == .ended
                || recognizer.state == .cancelled) else { return }
        do {
            if recognizer.state == .began {
                resetMapper()
                onManualViewportChange?()
            }
            let delta = try UIKitClientInputAdapterV0.consumeTranslation(
                of: recognizer,
                in: self
            )
            let current = try makeVisualZoomTransform()
            acceptVisualZoomTransform(try current.panned(by: delta))
            if recognizer.state == .ended
                || recognizer.state == .cancelled
            {
                rebuildMapperForCurrentGeometry()
            }
        } catch {
            failVisualZoomGeometry(error)
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

    private func panVisualZoomTowardEdgeIfNeeded(location: CGPoint) {
        guard visualZoomScale > 1.000_1,
              bounds.width > 0,
              bounds.height > 0 else { return }
        do {
            let viewport = try ClientInputRectV0(
                x: 0,
                y: 0,
                width: Double(bounds.width),
                height: Double(bounds.height)
            )
            let delta = try ClientVisualZoomEdgePanV0.delta(
                for: UIKitClientInputAdapterV0.point(location),
                in: viewport
            )
            guard delta.x != 0 || delta.y != 0 else { return }
            onManualViewportChange?()
            acceptVisualZoomTransform(
                try makeVisualZoomTransform().panned(by: delta)
            )
        } catch {
            failVisualZoomGeometry(error)
        }
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
        _ value: ClientVisualZoomTransformV0,
        animated: Bool = false
    ) {
        visualZoomScale = value.scale
        visualZoomTranslation = CGPoint(
            x: value.translation.x,
            y: value.translation.y
        )
        if animated {
            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut]
            ) { [weak self] in
                self?.applyVisualZoomTransform()
            }
        } else {
            applyVisualZoomTransform()
        }
    }

    private func resetVisualZoomState(animated: Bool = false) {
        visualZoomScale = 1
        visualZoomTranslation = .zero
        visualZoomStartScale = 1
        visualZoomOutPastFitLatched = false
        if animated {
            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut]
            ) { [weak self] in
                self?.applyVisualZoomTransform()
            }
        } else {
            applyVisualZoomTransform()
        }
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

    private func failVisualZoomGeometry(_ error: any Error) {
        print(
            "[MacCompanion live-control] visual zoom recovered error=\(String(describing: error))"
        )
        // Visual zoom is local presentation state. If UIKit supplies an
        // unusable transient scale/anchor while a gesture is changing, return
        // to a known fit transform without revoking the remote session.
        resetVisualZoomState()
        rebuildMapperForCurrentGeometry()
    }

    private func withMapper(
        _ body: (inout ClientViewportInputMapperV0) throws
            -> [InteractiveInputPayload]
    ) {
        guard canDispatchInput, var mapper else { return }
        do {
            let payloads = try body(&mapper)
            self.mapper = mapper
            emit(payloads)
        } catch {
            self.mapper = mapper
            print(
                "[MacCompanion live-control] gesture mapping error=\(String(describing: error)) disposition=\(String(describing: ClientInputGestureErrorPolicyV0.disposition(for: error)))"
            )
            switch ClientInputGestureErrorPolicyV0.disposition(for: error) {
            case .ignoreLocally:
                if mapper.heldDragButton == nil { dragLastLocation = nil }
                return
            case .resetVisualZoomLocally:
                failVisualZoomGeometry(error)
                return
            case .failClosed:
                break
            }
            setInputEnabled(false)
            onFailure(.invalidGesture)
        }
    }

    /// Sends a one-shot physical key/chord or bounded text action through the
    /// same active input relay as gestures. Accessibility focus is optional;
    /// the producer still rejects positively identified secure focus.
    public func sendKeyboardAction(
        _ action: ClientKeyboardActionV0,
        modifiers: InteractiveModifierMask = []
    ) {
        guard canDispatchInput else { return }
        do { emit(try action.payloads(modifiers: modifiers)) }
        catch {
            setInputEnabled(false)
            onFailure(.invalidGesture)
        }
    }

    private func submitKeyboardAction(_ action: ClientKeyboardActionV0) {
        sendKeyboardAction(action)
    }

    private func emit(_ payloads: [InteractiveInputPayload]) {
        guard canDispatchInput, !payloads.isEmpty else { return }
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
