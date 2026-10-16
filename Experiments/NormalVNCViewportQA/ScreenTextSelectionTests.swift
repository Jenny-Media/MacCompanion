import XCTest
import UIKit
@testable import Mac_Companion

@MainActor
final class ScreenTextSelectionTests: XCTestCase {
    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 800, height: 300)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 300))
            ("mini.local\nError: Connection refused" as NSString).draw(
                in: CGRect(x: 40, y: 40, width: 700, height: 200),
                withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 32, weight: .regular),
                                 .foregroundColor: UIColor.black])
        }
    }

    func testSystemAnalysisUsesFrozenImageAndRetirementClearsSelectableText() async throws {
        guard CompanionVNCTextSelection.supported else {
            throw XCTSkip("System Live Text is unavailable on this Simulator; area recognition is covered separately")
        }
        let image = image()
        let view = UIImageView(image: image)
        let selection = CompanionVNCTextSelection(imageView: view)
        let finished = expectation(description: "Local system image analysis completes")
        selection.analyze(image: image) { found in
            XCTAssertTrue(found)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 20)
        XCTAssertTrue(selection.text.contains("mini.local"))
        XCTAssertTrue(selection.selectedText.isEmpty, "Analysis must not select/export text on the user's behalf")
        selection.invalidate()
        XCTAssertTrue(selection.text.isEmpty)
        XCTAssertTrue(selection.selectedText.isEmpty)
        XCTAssertTrue(view.interactions.isEmpty)
        var restarted = true
        selection.analyze(image: image) { restarted = $0 }
        XCTAssertFalse(restarted)
    }

    func testCancellingSystemAnalysisCannotPublishLateText() async throws {
        guard CompanionVNCTextSelection.supported else { throw XCTSkip("System Live Text unavailable in Simulator") }
        let image = image()
        let view = UIImageView(image: image)
        let selection = CompanionVNCTextSelection(imageView: view)
        var replied = false
        selection.analyze(image: image) { _ in replied = true }
        selection.invalidate()
        for _ in 0..<100 where selection.busy { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(replied)
        XCTAssertTrue(selection.text.isEmpty)
        XCTAssertTrue(selection.selectedText.isEmpty)
        XCTAssertTrue(view.interactions.isEmpty)
    }
}
