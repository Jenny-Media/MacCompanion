import UIKit
// This entry point is linked only into a generated simulator QA app.
@main final class ComposerSheetApplication: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Synthetic Sheet", sessionRole: session.role)
        configuration.delegateClass = ComposerSheetScene.self
        return configuration
    }
}
final class ComposerSheetScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let arguments = ProcessInfo.processInfo.arguments
        DirectAppearanceV1.shared.app = arguments.contains("--qa-dark") ? .dark : .light
        window.rootViewController = ComposerSheetRoot(); self.window = window; window.makeKeyAndVisible()
    }
}
final class ComposerSheetRoot: UIViewController {
    private var terminalMode: Bool { ProcessInfo.processInfo.arguments.contains("--qa-terminal") }
    lazy var composer = DirectTextComposer(macName: "Synthetic Mac", mode: terminalMode ? "terminal" : "desktop")
    private var sends = 0
    override func viewDidLoad() {
        super.viewDidLoad()
        if terminalMode { overrideUserInterfaceStyle = ProcessInfo.processInfo.arguments.contains("--qa-terminal-dark") ? .dark : .light }
        view.backgroundColor = terminalMode ? .systemBackground : .black
        if ProcessInfo.processInfo.arguments.contains("--qa-glass-background") {
            let desktop = SyntheticGlassDesktop(); desktop.isUserInteractionEnabled = false
            desktop.frame = view.bounds; desktop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(desktop)
        }
        if ProcessInfo.processInfo.arguments.contains("--qa-shortcut-bar") {
            let bar = UIView(); bar.backgroundColor = terminalMode ? .secondarySystemBackground
                : UIColor.secondarySystemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            bar.accessibilityIdentifier = "qa-shortcut-bar"; bar.isAccessibilityElement = true
            bar.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(bar)
            NSLayoutConstraint.activate([bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: view.trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 52),
                bar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)])
            composer.shortcutBar = bar
        }
        let button = UIButton(type: .system); button.setTitle("Compose", for: .normal)
        button.accessibilityIdentifier = "qa-compose"
        button.addTarget(self, action: #selector(openComposer), for: .touchUpInside)
        view.addSubview(button); button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor)])
    }
    @objc func openComposer() {
        if ProcessInfo.processInfo.arguments.contains("--qa-narrow-composer") {
            let draft = composer.draft
            draft.configure(available: { true }, send: { _, _ in })
            let panel = DirectTextComposerPanel(draft: draft)
            addChild(panel); view.addSubview(panel.view); panel.didMove(toParent: self)
            panel.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([panel.view.widthAnchor.constraint(equalToConstant: 320),
                panel.view.heightAnchor.constraint(equalToConstant: 220),
                panel.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
                panel.view.centerXAnchor.constraint(equalTo: view.centerXAnchor)])
            draft.close = { [weak panel] in
                panel?.willMove(toParent: nil); panel?.view.removeFromSuperview(); panel?.removeFromParent()
            }
            draft.edit(String(repeating: "x", count: 257))
            return
        }
        composer.present(from: self, available: { true }, send: { [weak self] _, completion in
            guard let self, ProcessInfo.processInfo.arguments.contains("--qa-delivery-result") else { return }
            self.sends += 1; completion(self.sends == 1 ? "Synthetic delivery failure" : nil)
        })
    }
}

// Synthetic contrast/motion surface; never linked into a normal app target.
private final class SyntheticGlassDesktop: UIView {
    override func draw(_ rect: CGRect) {
        let size: CGFloat = 32
        for row in 0..<Int(ceil(bounds.height / size)) {
            for column in 0..<Int(ceil(bounds.width / size)) {
                ((row + column).isMultiple(of: 2) ? UIColor.systemTeal : UIColor.systemOrange).setFill()
                UIRectFill(CGRect(x: CGFloat(column) * size, y: CGFloat(row) * size, width: size, height: size))
            }
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular), .foregroundColor: UIColor.label]
        for y in stride(from: CGFloat(64), to: bounds.height, by: 48) {
            ("Synthetic desktop · text and color" as NSString).draw(at: CGPoint(x: 8, y: y), withAttributes: attributes)
        }
    }
}
