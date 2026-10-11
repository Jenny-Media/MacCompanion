import XCTest
#if os(macOS)
@testable import MacCompanion
#else
@testable import Mac_Companion
#endif

@MainActor final class QuickActionEditingTests: XCTestCase {
    func testScreenTextIsAFreeDesktopBuiltInAndPreservesSavedProfiles() throws {
        let action = VNCQuickAction(title: "Copy Text", kind: .copyText)
        #if os(iOS)
        XCTAssertEqual(DirectControlMode.desktop.defaults.map(\.kind), [.mode, .copyText, .fit, .rightClick])
        XCTAssertTrue(DirectQuickActionEditing.standards(.desktop).contains { $0.kind == .copyText })
        XCTAssertTrue(DirectQuickActionEditing.canSave([action], mode: .desktop, hasPro: false))
        #else
        XCTAssertFalse(DirectControlMode.desktop.defaults.contains { $0.kind == .copyText })
        XCTAssertFalse(action.compatible(with: .desktop))
        #endif
        XCTAssertFalse(action.compatible(with: .trackpad))
        XCTAssertFalse(action.compatible(with: .terminal))
        let saved = [VNCQuickAction(title: "My Right Click", kind: .rightClick, enabled: false)]
        let decoded = try JSONDecoder().decode([VNCQuickAction].self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded, saved, "Existing saved choices retain identity, visibility and order")
    }
    func testAddingHiddenStandardRestoresItsIdentityInsteadOfDuplicatingIt() throws {
        let hidden = VNCQuickAction(title: "Custom Return Label", kind: .returnKey, enabled: false)
        var actions = [hidden]
        let standard = try XCTUnwrap(DirectQuickActionEditing.standards(.trackpad).first { $0.kind == .returnKey })
        XCTAssertEqual(DirectQuickActionEditing.add(standard, to: &actions, mode: .trackpad), hidden.id)
        XCTAssertEqual(actions.count, 1); XCTAssertTrue(actions[0].enabled)
        XCTAssertEqual(actions[0].title, hidden.title)
        _ = DirectQuickActionEditing.add(standard, to: &actions, mode: .trackpad)
        XCTAssertEqual(actions.count, 1, "Already-added standard actions never duplicate")
    }
    func testReorderPreservesHiddenActionsPayloadsAndStableIDs() {
        let first = VNCQuickAction(title: "First", kind: .shortcut, key: 0x63, modifiers: [0xffe3])
        let hidden = VNCQuickAction(title: "Hidden", kind: .escape, enabled: false)
        let last = VNCQuickAction(title: "Last", kind: .text, text: "synthetic-only")
        var actions = [first, hidden, last]
        DirectQuickActionEditing.move(last.id, to: first.id, in: &actions)
        XCTAssertEqual(actions, [last, first, hidden])
        DirectQuickActionEditing.move(last.id, to: hidden.id, in: &actions)
        XCTAssertEqual(actions, [first, hidden, last])
        DirectQuickActionEditing.move(UUID(), to: first.id, in: &actions)
        XCTAssertEqual(actions, [first, hidden, last])
    }
    func testCapacityAllowsRestoringHiddenStandardsButRejectsNewItems() {
        let hidden = VNCQuickAction(title: "Return", kind: .returnKey, enabled: false)
        var actions = [hidden] + (0..<14).map { VNCQuickAction(title: "Synthetic \($0)", kind: .escape) }
        XCTAssertEqual(DirectQuickActionEditing.add(.init(title: "Return", kind: .returnKey), to: &actions, mode: .terminal), hidden.id)
        XCTAssertNil(DirectQuickActionEditing.add(.init(title: "Tab", kind: .tab), to: &actions, mode: .terminal))
        XCTAssertEqual(actions.count, 15)
    }
    func testCataloguesAndSaveValidationHonorEachMode() {
        for mode in DirectControlMode.allCases {
            XCTAssertTrue(DirectQuickActionEditing.standards(mode).allSatisfy { $0.compatible(with: mode) })
        }
        #if os(macOS)
        XCTAssertFalse(DirectQuickActionEditing.standards(.desktop).contains { $0.kind == .mode })
        #else
        XCTAssertTrue(DirectQuickActionEditing.standards(.desktop).contains { $0.kind == .mode })
        #endif
        XCTAssertFalse(DirectQuickActionEditing.valid([.init(title: "Copy", kind: .shortcut, key: 0x63, modifiers: [0xffeb])], mode: .terminal))
        XCTAssertFalse(DirectQuickActionEditing.valid([.init(title: "Text", kind: .text)], mode: .desktop))
        XCTAssertFalse(DirectQuickActionEditing.valid((0..<13).map { .init(title: "Text \($0)", kind: .text, text: "synthetic") }, mode: .terminal))
        let same = VNCQuickAction(title: "Escape", kind: .escape)
        XCTAssertFalse(DirectQuickActionEditing.valid([same, same], mode: .terminal))
        XCTAssertTrue(DirectQuickActionEditing.valid([], mode: .terminal), "Empty profiles must remain intentional")
    }
}
