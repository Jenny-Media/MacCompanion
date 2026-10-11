import XCTest
import SwiftUI
#if os(iOS)
import UIKit
@testable import Mac_Companion
#else
import AppKit
@testable import MacCompanion
#endif

@MainActor final class QuickActionRefinementTests: XCTestCase {
    func testNameSymbolInsertionRespectsUnicodeCursorSelectionAndNameLimit() throws {
        let name = "Mac 🖥️ Copy"
        let range = try XCTUnwrap(name.range(of: "Copy"))
        let result = try XCTUnwrap(DirectQuickActionName.inserting("⌘", into: name, selection: NSRange(range, in: name)))
        XCTAssertEqual(result.name, "Mac 🖥️ ⌘")
        XCTAssertEqual(result.cursor, result.name.utf16.count)
        let caret = DirectQuickActionName.inserting("⇧", into: "Copy", selection: NSRange(location: 0, length: 0))
        XCTAssertEqual(caret?.name, "⇧Copy"); XCTAssertEqual(caret?.cursor, 1)
        XCTAssertNil(DirectQuickActionName.inserting("⌘", into: String(repeating: "a", count: 40), selection: nil))
        XCTAssertEqual(DirectQuickActionName.inserting("⌘", into: "Copy", selection: NSRange(location: 100, length: 0))?.name, "Copy⌘")
    }
    func testSavedTextEditorGrowsForMultilineContentWithoutModifyingWhitespace() throws {
        let short = "  one line  "
        let multiline = "first\n  second\nthird\nfourth\nfifth\nsixth\nseventh\neighth\n"
        func height(_ text: String) -> CGFloat {
            #if os(iOS)
            let host = UIHostingController(rootView: DirectSavedTextEditor(text: .constant(text), mode: .terminal))
            return host.sizeThatFits(in: .init(width: 320, height: 1000)).height
            #else
            let host = NSHostingView(rootView: DirectSavedTextEditor(text: .constant(text), mode: .terminal).frame(width: 320))
            host.layoutSubtreeIfNeeded(); return host.fittingSize.height
            #endif
        }
        XCTAssertGreaterThan(height(multiline), height(short) + 30)
        let action = VNCQuickAction(title: "Synthetic", kind: .text, text: multiline)
        XCTAssertTrue(action.valid); XCTAssertEqual(action.text, multiline)
        XCTAssertLessThan(height(multiline), 420)
    }
}
