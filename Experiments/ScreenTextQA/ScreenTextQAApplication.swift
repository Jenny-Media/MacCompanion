import SwiftUI
import UIKit

@main
struct ScreenTextQAApplication: App {
    @State private var returned = false
    var body: some Scene {
        WindowGroup {
            if returned {
                Text("Back to Screen Sharing").accessibilityIdentifier("screen-text-returned")
            } else {
                ScreenTextQAHost { returned = true }.ignoresSafeArea()
            }
        }
    }
}

private struct ScreenTextQAHost: UIViewControllerRepresentable {
    var returned: () -> Void
    func makeUIViewController(context: Context) -> CompanionVNCTextReview {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 700), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 700))
            ("mini.local\nError: Connection refused\n    return value_42;\n你好世界" as NSString).draw(
                in: CGRect(x: 100, y: 100, width: 800, height: 500),
                withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 48, weight: .regular), .foregroundColor: UIColor.black])
        }
        let review = CompanionVNCTextReview(image: image, visibleRect: CGRect(x: 0, y: 0, width: 1000, height: 700))
        review.returnHandler = returned
        return review
    }
    func updateUIViewController(_ controller: CompanionVNCTextReview, context: Context) {}
}
