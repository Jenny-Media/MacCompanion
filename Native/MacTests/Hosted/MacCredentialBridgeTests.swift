import AppKit
import Observation
import SwiftUI
import XCTest
@testable import MacCompanion

@MainActor @Observable private final class CredentialDraft {
    var username = ""
    var password = ""
    var enabled = true
    var tick = 0
    var submissions = 0
}

private struct CredentialFixtureView: View {
    @Bindable var draft: CredentialDraft
    var body: some View {
        VStack {
            MacCredentialFields(username: $draft.username, password: $draft.password,
                enabled: draft.enabled, prefix: "synthetic-fill", submit: { draft.submissions += 1 })
            Text("\(draft.tick)")
        }.frame(width: 420, height: 180)
    }
}

@MainActor final class MacCredentialBridgeTests: XCTestCase {
    @MainActor private final class Fixture {
        let draft = CredentialDraft()
        let window: NSWindow
        let host: NSHostingView<CredentialFixtureView>
        init() {
            host = NSHostingView(rootView: CredentialFixtureView(draft: draft))
            window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 480, height: 260),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        }
        func fields() -> MacCredentialFields.Fields? {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            return descendants(host).compactMap { $0 as? MacCredentialFields.Fields }.first
        }
        func close() { window.makeFirstResponder(nil); window.contentView = nil; window.close() }
    }
    private func settle() async throws { try await Task.sleep(for: .milliseconds(100)) }
    private func assign(_ value: String, to field: NSTextField, path: Int) {
        switch path {
        case 0: field.stringValue = value
        case 1: field.objectValue = value
        default: field.attributedStringValue = NSAttributedString(string: value)
        }
    }
    func testNativeProviderValuePathsFillBothBindingsWhileFocusedInEitherOrder() async throws {
        for path in 0..<3 {
            for passwordFirst in [false, true] {
                let fixture = Fixture(); defer { fixture.close() }
                try await settle(); let fields = try XCTUnwrap(fixture.fields())
                XCTAssertTrue(fixture.window.makeFirstResponder(fields.secret))
                XCTAssertNotNil(fields.secret.currentEditor())
                if passwordFirst { assign("synthetic-only", to: fields.secret, path: path) }
                assign("synthetic-account", to: fields.account, path: path)
                if !passwordFirst { assign("synthetic-only", to: fields.secret, path: path) }
                try await settle()
                XCTAssertEqual(fixture.draft.username, "synthetic-account")
                XCTAssertEqual(fixture.draft.password, "synthetic-only")
                fixture.draft.tick += 1; try await settle()
                XCTAssertTrue(fixture.fields() === fields, "An unrelated redraw must retain the credential pair")
                XCTAssertEqual(fields.account.stringValue, "synthetic-account")
                XCTAssertEqual(fields.secret.stringValue, "synthetic-only")
                fixture.window.makeFirstResponder(nil); try await settle()
                XCTAssertEqual(fixture.draft.password, "synthetic-only", "Committing editing must retain the provider value")
            }
        }
    }
    func testActualFieldEditorInsertionAndReplacementReachBindings() async throws {
        let fixture = Fixture(); defer { fixture.close() }; try await settle()
        let fields = try XCTUnwrap(fixture.fields())
        XCTAssertTrue(fixture.window.makeFirstResponder(fields.secret))
        let editor = try XCTUnwrap(fields.secret.currentEditor() as? NSTextView)
        editor.insertText("synthetic-only", replacementRange: NSRange(location: 0, length: 0))
        try await settle(); XCTAssertEqual(fixture.draft.password, "synthetic-only")
        editor.insertText("replacement-only", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        try await settle(); XCTAssertEqual(fixture.draft.password, "replacement-only")
    }
    func testExplicitClearDuringEditingCannotReturnAtLaterCommit() async throws {
        let fixture = Fixture(); defer { fixture.close() }; try await settle()
        let fields = try XCTUnwrap(fixture.fields())
        fixture.window.makeFirstResponder(fields.secret)
        fields.secret.currentEditor()?.insertText("synthetic-only")
        try await settle(); XCTAssertEqual(fixture.draft.password, "synthetic-only")
        fixture.draft.password = ""; try await settle()
        XCTAssertEqual(fields.secret.stringValue, "")
        fixture.window.makeFirstResponder(nil); try await settle()
        XCTAssertEqual(fixture.draft.password, "")
    }
    func testProviderReplyAfterDisableCannotReviveClearedSecret() async throws {
        let fixture = Fixture(); defer { fixture.close() }; try await settle()
        let fields = try XCTUnwrap(fixture.fields())
        fields.secret.objectValue = "synthetic-only"; try await settle()
        fixture.draft.password = ""; fixture.draft.enabled = false; try await settle()
        fields.secret.objectValue = "late-synthetic-only"; try await settle()
        XCTAssertEqual(fixture.draft.password, ""); XCTAssertEqual(fields.secret.stringValue, "")
        fixture.draft.enabled = true; fixture.draft.tick += 1; try await settle()
        fixture.window.makeFirstResponder(nil)
        XCTAssertEqual(fixture.draft.password, "")
    }
    func testReturnActionSynchronizesFilledPairAndSubmitsOnce() async throws {
        let fixture = Fixture(); defer { fixture.close() }; try await settle()
        let fields = try XCTUnwrap(fixture.fields())
        fields.secret.objectValue = "synthetic-only"; fields.account.objectValue = "synthetic-account"
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(fields.secret.action), to: fields.secret.target, from: fields.secret))
        XCTAssertEqual(fixture.draft.submissions, 1)
        XCTAssertEqual(fixture.draft.username, "synthetic-account"); XCTAssertEqual(fixture.draft.password, "synthetic-only")
    }
}
