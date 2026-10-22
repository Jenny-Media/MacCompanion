import XCTest
import SwiftUI
import StoreKitTest
import Security
@testable import Mac_Companion

@MainActor final class QuickActionEditorTests: XCTestCase {
    @Observable final class Draft { var actions: [VNCQuickAction] = [] }
    @Observable final class TextDraft { var text = "" }

    func testSavedTextAcceptsNativeEditingAndResizesWhileFocused() async throws {
        let draft = TextDraft()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: NavigationStack {
            ScrollView {
                DirectSavedTextEditor(text: Binding(get: { draft.text }, set: { draft.text = $0 }), mode: .terminal).padding(16)
            }.navigationTitle("Saved Text").navigationBarTitleDisplayMode(.inline)
        })
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        try await Task.sleep(for: .milliseconds(100))
        let field = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UITextView }.first)
        let initialHeight = field.bounds.height
        XCTAssertTrue(field.becomeFirstResponder())
        let text = "first\n  second\nthird\nfourth\nfifth\nsixth\nseventh\neighth\n"
        field.insertText(text)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(draft.text, text, "Native editing preserves indentation and trailing newlines")
        XCTAssertTrue(field.isFirstResponder, "Resizing does not lose input focus")
        XCTAssertGreaterThan(field.bounds.height, initialHeight + 30)
        XCTAssertLessThanOrEqual(field.bounds.height, 240)
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        attachment.name = "saved-text-native-editing"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testEachModeEditsTheNativePreviewWithoutExecutingInputOrWritingItsProfile() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url); store.disableDialogs = true; store.clearTransactions()
        DirectProAccess.shared.start()
        _ = try await store.buyProduct(identifier: DirectProAccess.productID)
        for _ in 0..<250 {
            await DirectProAccess.shared.refresh()
            if DirectProAccess.shared.hasPro { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(DirectProAccess.shared.hasPro)
        let previous = DirectAppearanceV1.shared.app
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.endEditing(true); window.isHidden = true; window.rootViewController = nil
            DirectAppearanceV1.shared.app = previous; previousWindow?.makeKeyAndVisible(); store.clearTransactions()
        }
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        func capture(_ name: String) {
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            })
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        func savedProfile(_ mode: DirectControlMode) throws -> Data? {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "media.jenny.maccompanion.direct-actions.v1",
                kSecAttrAccount as String: mode.profileID.uuidString.lowercased(),
                kSecAttrSynchronizable as String: false, kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            XCTAssertEqual(status, errSecSuccess)
            return try XCTUnwrap(result as? Data)
        }
        for mode in DirectControlMode.allCases {
            let original = try savedProfile(mode)
            let draft = Draft(); draft.actions = mode.defaults
            DirectAppearanceV1.shared.app = .light
            let host = UIHostingController(rootView: NavigationStack {
                ScrollViewReader { scroll in
                    ScrollView {
                        DirectQuickActionsEditor(actions: Binding(get: { draft.actions }, set: { draft.actions = $0 }), mode: mode,
                            selectionChanged: { scroll.scrollTo("quick-action-inspector", anchor: .top) })
                            .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 20)).padding(16)
                    }.background(Color(uiColor: .systemGroupedBackground))
                }
                    .navigationTitle(mode.title + " Controls").navigationBarTitleDisplayMode(.inline)
            }.directAppearance())
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(350))
            let preview = try XCTUnwrap(descendants(host.view).compactMap { $0 as? CompanionVNCControls }.first)
            XCTAssertTrue(preview.editingPreview); XCTAssertNil(preview.actionHandler)
            capture("quick-actions-" + mode.rawValue + "-default")
            let custom = VNCQuickAction(title: mode == .terminal ? "Clear" : "Copy", kind: .shortcut,
                key: mode == .terminal ? 0x6c : 0x63, modifiers: [mode == .terminal ? 0xffe3 : 0xffeb])
            draft.actions.append(custom)
            try await Task.sleep(for: .milliseconds(200))
            let choices = try XCTUnwrap(preview.value(forKey: "choices") as? [UIButton])
            XCTAssertEqual(choices.count, draft.actions.filter(\.enabled).count, "Preview contains only the editable actions")
            let button = try XCTUnwrap(choices.first { $0.accessibilityIdentifier == "preview-action-" + custom.id.uuidString })
            button.sendActions(for: .touchUpInside)
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertEqual(preview.selectedPreviewID, custom.id.uuidString)
            XCTAssertNil(preview.actionHandler, "Editing must never acquire a session input callback")
            XCTAssertEqual(try savedProfile(mode), original, "The draft must not write the saved profile")
            XCTAssertTrue(descendants(host.view).contains { $0 === preview }, "Retain the native preview while editing")
            capture("quick-actions-" + mode.rawValue + "-editing")
            DirectAppearanceV1.shared.app = .dark
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertEqual(host.traitCollection.userInterfaceStyle, .dark)
            capture("quick-actions-" + mode.rawValue + "-dark")
            let text = VNCQuickAction(title: "Synthetic Text", kind: .text, text: "first line\n  indented line\nlast line\n")
            draft.actions.append(text)
            try await Task.sleep(for: .milliseconds(200))
            let textButton = try XCTUnwrap((preview.value(forKey: "choices") as? [UIButton])?.first {
                $0.accessibilityIdentifier == "preview-action-" + text.id.uuidString
            })
            textButton.sendActions(for: .touchUpInside)
            try await Task.sleep(for: .milliseconds(250))
            capture("quick-actions-" + mode.rawValue + "-saved-text")
            XCTAssertEqual(draft.actions.last?.text, text.text, "Rendering must preserve spaces and trailing newlines")
        }
    }
}
