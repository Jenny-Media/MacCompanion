#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import UIKit

/// A passive visual echo of the pressed key. Input remains owned by the bar's
/// existing touch-up action; cancelling or scrolling never sends a key.
class TerminalKeyPreviewButton: UIButton {
    var previewsKey = false
    var previewAllowed: (() -> Bool)?
    private var bubble: UIView?
    private var anchor: CGRect?
    var keyPreviewVisible: Bool { bubble?.superview != nil }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addAction(UIAction { [weak self] _ in self?.showKeyPreview() }, for: [.touchDown, .touchDragEnter])
        addAction(UIAction { [weak self] _ in self?.dismissKeyPreview() },
                  for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        NotificationCenter.default.addObserver(self, selector: #selector(dismissKeyPreview),
            name: UIApplication.willResignActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isEnabled: Bool { didSet { if !isEnabled { dismissKeyPreview() } } }
    override func didMoveToWindow() { super.didMoveToWindow(); dismissKeyPreview() }
    override func layoutSubviews() {
        super.layoutSubviews()
        dismissMovedKeyPreview()
    }
    func dismissMovedKeyPreview() {
        if let window, let anchor, convert(bounds, to: window) != anchor { dismissKeyPreview() }
    }
    func showKeyPreview() {
        dismissKeyPreview()
        guard previewsKey, isEnabled, previewAllowed?() == true, let window,
              let bar = sequence(first: superview, next: { $0?.superview }).compactMap({ $0 as? TerminalKeyboardBar }).first,
              !UIAccessibility.isVoiceOverRunning else { return }
        let key = convert(bounds, to: window)
        let pane = bar.convert(bar.bounds, to: window).intersection(window.bounds.inset(by: window.safeAreaInsets)).insetBy(dx: 4, dy: 0)
        guard pane.width >= 44, pane.intersects(key) else { return }
        let content = UIView()
        content.isUserInteractionEnabled = false; content.accessibilityElementsHidden = true
        content.backgroundColor = .secondarySystemBackground
        content.layer.cornerRadius = 12
        content.layer.shadowColor = UIColor.black.cgColor; content.layer.shadowOpacity = 0.22
        content.layer.shadowRadius = 5; content.layer.shadowOffset = CGSize(width: 0, height: 2)
        let label = UILabel()
        label.textAlignment = .center; label.textColor = .label
        label.font = .systemFont(ofSize: 29, weight: .medium)
        label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.55
        label.text = configuration?.title ?? accessibilityLabel
        let width = min(pane.width, max(62, min(144, label.intrinsicContentSize.width + 24)))
        let x = min(max(key.midX - width / 2, pane.minX), pane.maxX - width)
        let top = max(window.safeAreaInsets.top + 4, key.minY - 66)
        content.frame = CGRect(x: x, y: top, width: width, height: 58)
        if let image = configuration?.image {
            let icon = UIImageView(image: image.withConfiguration(UIImage.SymbolConfiguration(pointSize: 29, weight: .medium)))
            icon.contentMode = .center; icon.tintColor = .label
            icon.frame = content.bounds.insetBy(dx: 10, dy: 6); content.addSubview(icon)
        } else { label.frame = content.bounds.insetBy(dx: 10, dy: 6); content.addSubview(label) }
        window.addSubview(content); bubble = content; anchor = key
    }
    @objc func dismissKeyPreview() { bubble?.removeFromSuperview(); bubble = nil; anchor = nil }
}
#endif
