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
        composer.present(from: self, available: { true }, send: { _, _ in })
    }
}
