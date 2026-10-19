#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UIKit

/// Presentation owns no connection or credentials. Swapping sheet content never
/// moves or reconstructs the remote controller underneath it.
@objc(DirectConnectionPanelHost) @MainActor final class DirectConnectionPanelHost: NSObject, UIAdaptivePresentationControllerDelegate {
    private weak var anchor: UIViewController?
    private var sheet: UIViewController?
    private var content: UIViewController?
    private var owner: NSObject?
    // A dismissed login can still receive a final native/SwiftUI redraw while
    // cancellation tears it down. Keep its owner retired until it deallocates.
    private let dismissedOwners = NSHashTable<NSObject>.weakObjects()
    private var cancel: (() -> Void)?
    private var transient: UIViewController?
    private var dismissalLocked = false
    private var dismissing = false
    private var preferredHeight: CGFloat = 500
    private var expanded = false
    var isVisible: Bool { owner != nil }
    func attach(_ anchor: UIViewController) { self.anchor = anchor; reconcile() }
    @objc(showContent:owner:cancel:) func show(_ content: UIViewController, owner: NSObject, cancel: @escaping () -> Void) {
        guard !dismissedOwners.contains(owner) else { return }
        if self.owner !== owner { dismissalLocked = false; preferredHeight = 500; expanded = false }
        self.owner = owner; self.content = content; self.cancel = cancel; reconcile(); updatePreferredSize()
    }
    @objc(setDismissalLocked:owner:) func setDismissalLocked(_ locked: Bool, owner: NSObject) {
        guard self.owner === owner else { return }
        dismissalLocked = locked
        sheet?.isModalInPresentation = transient != nil || locked
    }
    @objc(setContentHeight:owner:) func setContentHeight(_ height: CGFloat, owner: NSObject) {
        guard self.owner === owner, height.isFinite, abs(preferredHeight - height) > 1 else { return }
        preferredHeight = max(220, height)
        updatePreferredSize()
    }
    @objc(hideOwner:) func hide(_ owner: NSObject) {
        // Let a new stage take ownership before dismantling the previous stage.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.owner === owner else { return }
            self.owner = nil; self.content = nil; self.cancel = nil; self.transient = nil; self.dismissalLocked = false; self.reconcile()
        }
    }
    @objc(showTrust:) func showTrust(_ controller: UIViewController) { transient = controller; reconcile(); updatePreferredSize() }
    @objc(finishTrust:) func finishTrust(_ controller: UIViewController) {
        guard transient === controller else { return }; transient = nil; reconcile(); updatePreferredSize()
    }
    func close() { owner = nil; content = nil; cancel = nil; transient = nil; dismissalLocked = false; reconcile() }
    func expand() {
        // More room for Connection Options while retaining a bounded native form.
        expanded = true; updatePreferredSize()
    }
    func compact() { expanded = false; updatePreferredSize() }
    @objc(presentSecondary:) func presentSecondary(_ controller: UIViewController) {
        guard let sheet, sheet.presentedViewController == nil else { return }
        sheet.present(controller, animated: true)
    }
    private func updatePreferredSize() {
        // Native form sizing adapts to the available window, not the device model.
        sheet?.preferredContentSize = CGSize(width: 560, height: transient == nil ? max(expanded ? 620 : 0, preferredHeight) : 620)
    }
    private func reconcile() {
        guard !dismissing else { return }
        guard let next = transient ?? content, owner != nil else {
            guard let old = sheet else { return }; dismissing = true
            old.dismiss(animated: true) { [weak self] in
                guard let self else { return }; self.sheet = nil; self.dismissing = false; self.reconcile()
            }; return
        }
        if sheet == nil {
            guard let anchor, anchor.viewIfLoaded?.window != nil, anchor.presentedViewController == nil else { return }
            let panel = UIViewController(); panel.view.backgroundColor = DirectConnectionStyle.panel
            panel.view.accessibilityIdentifier = "connection-sheet"
            panel.view.accessibilityViewIsModal = true
            panel.modalPresentationStyle = .formSheet
            panel.preferredContentSize = CGSize(width: 560, height: transient == nil ? max(expanded ? 620 : 0, preferredHeight) : 620)
            panel.sheetPresentationController?.prefersPageSizing = false
            if #available(iOS 27.0, *) { panel.sheetPresentationController?.preferredPlacement = .center }
            // Explicit height detents turn the native floating form into an
            // edge-attached sheet. Let UIKit size and position this form, including
            // its compact-window and keyboard adaptation.
            panel.presentationController?.delegate = self
            sheet = panel; mount(next, in: panel); anchor.present(panel, animated: true)
            panel.presentationController?.delegate = self
        } else if let sheet { mount(next, in: sheet) }
    }
    private func mount(_ next: UIViewController, in panel: UIViewController) {
        panel.isModalInPresentation = transient != nil || dismissalLocked
        guard next.parent !== panel else { return }
        panel.children.forEach { old in old.willMove(toParent: nil); old.view.removeFromSuperview(); old.removeFromParent() }
        panel.addChild(next); next.view.translatesAutoresizingMaskIntoConstraints = false; panel.view.addSubview(next.view)
        NSLayoutConstraint.activate([next.view.leadingAnchor.constraint(equalTo: panel.view.leadingAnchor), next.view.trailingAnchor.constraint(equalTo: panel.view.trailingAnchor), next.view.topAnchor.constraint(equalTo: panel.view.topAnchor), next.view.bottomAnchor.constraint(equalTo: panel.view.bottomAnchor)])
        next.didMove(toParent: panel)
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === sheet else { return }
        if let owner { dismissedOwners.add(owner) }
        let action = cancel; sheet = nil; owner = nil; content = nil; transient = nil; cancel = nil; dismissalLocked = false; action?()
    }
}

/// Own the whole native library subtree so its navigation bar, list and bottom
/// controls share one reliable interaction/accessibility gate. The hosting
/// controller remains mounted while session and sheet owners come and go.
struct DirectLibraryContainer<Content: View>: UIViewControllerRepresentable {
    let blocked: Bool
    let content: Content
    init(blocked: Bool, @ViewBuilder content: () -> Content) {
        self.blocked = blocked; self.content = content()
    }
    final class Controller: UIViewController {
        let host: UIHostingController<AnyView>
        init(content: AnyView) { host = UIHostingController(rootView: content); super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidLoad() {
            super.viewDidLoad(); view.backgroundColor = .clear
            addChild(host); host.view.backgroundColor = .clear; host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            host.didMove(toParent: self)
        }
    }
    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller(content: hosted(context.environment))
        controller.loadViewIfNeeded(); apply(controller)
        return controller
    }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.host.rootView = hosted(context.environment)
        apply(controller)
    }
    private func hosted(_ environment: EnvironmentValues) -> AnyView {
        // Forward public presentation inputs, never the outer host's private
        // rendering environment or its sheet-specific dismissal action.
        AnyView(content.directAppearance()
            .environment(\.scenePhase, environment.scenePhase)
            .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
            .environment(\.colorScheme, environment.colorScheme)
            .environment(\.locale, environment.locale)
            .environment(\.layoutDirection, environment.layoutDirection)
            .environment(\.horizontalSizeClass, environment.horizontalSizeClass)
            .environment(\.verticalSizeClass, environment.verticalSizeClass)
            .environment(\.openURL, environment.openURL))
    }
    private func apply(_ controller: UIViewController) {
        controller.view.accessibilityElementsHidden = blocked
        controller.view.isUserInteractionEnabled = !blocked
    }
}

struct DirectConnectionPanelAnchor: UIViewControllerRepresentable {
    let host: DirectConnectionPanelHost
    final class Anchor: UIViewController {
        var host: DirectConnectionPanelHost?
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); host?.attach(self) }
    }
    func makeUIViewController(context: Context) -> Anchor { let anchor = Anchor(); anchor.host = host; anchor.view.backgroundColor = .clear; return anchor }
    func updateUIViewController(_ anchor: Anchor, context: Context) { host.attach(anchor) }
}

struct DirectConnectionPanelContent<Content: View>: UIViewControllerRepresentable {
    let host: DirectConnectionPanelHost
    let cancel: () -> Void
    var preferredHeight: CGFloat = 500
    var preventsDismissal = false
    @ViewBuilder let content: () -> Content
    final class Coordinator {
        let owner = NSObject()
        var controller: UIHostingController<Content>?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> UIViewController {
        let placeholder = Placeholder(); placeholder.host = host; placeholder.view.backgroundColor = .clear
        let controller = UIHostingController(rootView: content()); controller.view.backgroundColor = .clear
        context.coordinator.controller = controller
        host.show(controller, owner: context.coordinator.owner, cancel: cancel)
        host.setDismissalLocked(preventsDismissal, owner: context.coordinator.owner)
        host.setContentHeight(preferredHeight, owner: context.coordinator.owner)
        return placeholder
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let contentController = context.coordinator.controller else { return }
        contentController.rootView = content()
        host.show(contentController, owner: context.coordinator.owner, cancel: cancel)
        host.setDismissalLocked(preventsDismissal, owner: context.coordinator.owner)
        host.setContentHeight(preferredHeight, owner: context.coordinator.owner)
    }
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        // Store the host on the placeholder so dismantling can release only its owner.
        (controller as? Placeholder)?.host?.hide(coordinator.owner)
    }
    private final class Placeholder: UIViewController { var host: DirectConnectionPanelHost? }
}
#endif
