import XCTest
import SwiftTerm
import UIKit
@testable import Mac_Companion

@MainActor private final class ShortcutOutputController: TerminalController {
    var output: [UInt8] = []
    private let inputEpoch = UUID()
    override func viewDidLoad() {
        super.viewDidLoad()
        terminal.customInputEpoch = { [weak self] in self?.inputEpoch }
        terminal.admitCustomInput = { [weak self] bytes in self?.output += bytes; return self != nil }
        keyboardBar.refresh()
    }
    override func send(source: TerminalView, data: ArraySlice<UInt8>) { output += terminal.encodeOutput(data) }
}

@MainActor final class TerminalShortcutRegressionTests: XCTestCase {
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func controller(flags: Int) throws -> ShortcutOutputController {
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic keyboard", addresses: ["127.0.0.1"]))
        let controller = ShortcutOutputController(session: session, customize: {})
        controller.loadViewIfNeeded()
        controller.terminal.feed(text: "\u{1b}[>\(flags)u")
        XCTAssertEqual(controller.terminal.getTerminal().keyboardEnhancementFlags.rawValue, flags)
        controller.output = []
        return controller
    }
    private func tap(_ title: String, in controller: ShortcutOutputController) throws {
        let button = try XCTUnwrap(descendants(controller.keyboardBar).compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == title || $0.configuration?.title == title })
        button.sendActions(for: .touchUpInside)
    }
    func testOnScreenAltNumberButtonsKeepEveryDigitInEachNegotiatedMode() throws {
        for flags in [0, 1, 3, 8, 24, 2] {
            let controller = try controller(flags: flags)
            for digit in "1234567890" {
                controller.output = []
                try tap("Alt", in: controller); try tap(String(digit), in: controller)
                var expected = flags == 0 || flags == 2 ? "\u{1b}\(digit)" : "\u{1b}[\(digit.asciiValue!);3u"
                if flags & 2 != 0 { expected += "\u{1b}[\(digit.asciiValue!);3:3u" }
                XCTAssertEqual(controller.output, Array(expected.utf8), "flags=\(flags), Alt+\(digit)")
                XCTAssertTrue(controller.terminal.keyboardState.active.isEmpty)
            }
        }
    }
    func testIndexedEnhancedShortcutsKeepKeyIdentityAndCombinedModifiers() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        func keyboard(_ value: Any) -> [String: Any]? {
            guard let object = value as? [String: Any] else { return nil }
            if let keys = object["terminalKeyboard"] as? [String: Any] { return keys }
            return object.values.compactMap(keyboard).first
        }
        let cases = try XCTUnwrap(try XCTUnwrap(keyboard(root))["enhancedShortcutCases"] as? [[String: Any]])
        for item in cases {
            let controller = try controller(flags: try XCTUnwrap(item["flags"] as? Int))
            try tap("Alt", in: controller)
            if item["ctrl"] as? Bool == true { try tap("Ctrl", in: controller) }
            if item["shift"] as? Bool == true { controller.terminal.keyboardState.toggle(.shift) }
            controller.terminal.insertText(try XCTUnwrap(item["text"] as? String))
            XCTAssertEqual(controller.output.map { String(format: "%02x", $0) }.joined(), item["expectedHex"] as? String)
            XCTAssertTrue(controller.terminal.hasText, "Shortcut insertion must retain native UITextInput bookkeeping")
        }
    }
    func testLockedAltSurvivesSeveralNumberButtonsAndClearsOnFocusLoss() throws {
        let controller = try controller(flags: 1)
        controller.terminal.keyboardState.toggle(.alt, lock: true)
        try tap("1", in: controller); try tap("2", in: controller)
        XCTAssertEqual(controller.output, Array("\u{1b}[49;3u\u{1b}[50;3u".utf8))
        XCTAssertEqual(controller.terminal.keyboardState.active, .alt)
        _ = controller.terminal.resignFirstResponder()
        XCTAssertTrue(controller.terminal.keyboardState.active.isEmpty)
    }
}
