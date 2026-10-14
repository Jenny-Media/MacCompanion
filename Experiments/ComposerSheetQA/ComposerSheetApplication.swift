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
        window.rootViewController = ComposerSheetRoot(); self.window = window; window.makeKeyAndVisible()
    }
}
final class ComposerSheetRoot: UIViewController {
    let composer = DirectTextComposer(macName: "Synthetic Mac", mode: "desktop")
    private var sends = 0
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBlue
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
