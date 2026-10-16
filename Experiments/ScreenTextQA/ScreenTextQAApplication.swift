import SwiftUI
import UIKit

@main
struct ScreenTextQAApplication: App {
    @State private var returned = false
    var body: some Scene {
        WindowGroup {
            if returned {
                VStack {
                    Text("Back to Screen Sharing").accessibilityIdentifier("screen-text-returned")
                    Button("Copy Text") { returned = false }.accessibilityIdentifier("screen-text-open")
                }
            } else {
                ScreenTextQAHost { returned = true }.ignoresSafeArea()
            }
        }
    }
}

private struct ScreenTextQAHost: UIViewControllerRepresentable {
    var returned: () -> Void
    func makeUIViewController(context: Context) -> CompanionVNCTextNavigation {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 700), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 700))
            ("mini.local\nError: Connection refused\n    return value_42;\n你好世界" as NSString).draw(
                in: CGRect(x: 100, y: 100, width: 800, height: 500),
                withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 48, weight: .regular), .foregroundColor: UIColor.black])
        }
        let review = ScreenTextQAReview(image: image, visibleRect: CGRect(x: 0, y: 0, width: 1000, height: 700))
        if ProcessInfo.processInfo.environment["MACCOMPANION_SCREEN_TEXT_AXXXL"] == "1" {
            review.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        }
        review.returnHandler = returned
        let navigation = CompanionVNCTextNavigation(rootViewController: UIViewController())
        navigation.pushViewController(review, animated: false)
        return navigation
    }
    func updateUIViewController(_ controller: CompanionVNCTextNavigation, context: Context) {}
}

// Apply the synthetic accessibility setting to this QA window, so presented
// controllers inherit it too. No system or other Simulator preference changes.
private final class ScreenTextQAReview: CompanionVNCTextReview {
    override func viewDidAppear(_ animated: Bool) {
        if ProcessInfo.processInfo.environment["MACCOMPANION_SCREEN_TEXT_AXXXL"] == "1" {
            view.window?.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        }
        super.viewDidAppear(animated)
        if ProcessInfo.processInfo.environment["MACCOMPANION_SCREEN_TEXT_VIEWPORT_GESTURE"] == "1",
           let crop = value(forKey: "crop") as? UIView,
           let image = crop.value(forKey: "imageView") as? UIImageView {
            // Target the real bitmap bounds for synthetic multi-touch. The
            // scroll canvas can contain large empty regions on a tablet.
            // Accessibility metadata does not alter the touch/view hierarchy.
            image.isAccessibilityElement = true
            image.accessibilityIdentifier = "screen-text-pinch-image"
            image.accessibilityLabel = "Frozen image"
            let probe = UIBarButtonItem(title: "Viewport", style: .plain, target: self, action: #selector(inspectViewport))
            probe.accessibilityIdentifier = "screen-text-viewport-probe"
            navigationItem.rightBarButtonItem = probe
        }
    }
    @objc private func inspectViewport() {
        guard let crop = value(forKey: "crop") as? UIView,
              let scroll = crop.value(forKey: "scroll") as? UIScrollView,
              let image = crop.value(forKey: "imageView") as? UIImageView else { return }
        let pixels = scroll.convert(scroll.bounds, to: image).intersection(image.bounds).integral.intersection(image.bounds)
        navigationItem.rightBarButtonItem?.accessibilityValue =
            [scroll.zoomScale, pixels.minX, pixels.minY, pixels.width, pixels.height].map { String(Double($0)) }.joined(separator: "|")
    }
}
