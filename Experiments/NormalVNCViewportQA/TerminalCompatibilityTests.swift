import XCTest
import UIKit
import Observation
import SwiftTerm
import NIO
import NIOSSH
import Citadel
@testable import Mac_Companion

/// The selection API resolves extended graphemes and skips wide-cell padding.
/// getBufferAsData exports raw cells, including NUL continuations and atom IDs.
@MainActor func terminalCompatibilityText(_ terminal: Terminal) -> String {
    terminal.getText(start: .init(col: 0, row: 0),
                     end: .init(col: terminal.cols, row: terminal.getTopVisibleRow() + terminal.rows - 1))
}

/// Golden protocol scenarios over real SSH and the production hosted surface.
/// Tool certification additionally requires the real-tool and device lanes.
@MainActor final class TerminalCompatibilityTests: XCTestCase {
    private struct Vectors: Decodable {
        struct Key: Decodable { let name: String; let text: String; var ctrl: Bool?; var alt: Bool?; let expectedHex: String }
        struct Arrow: Decodable { let enable: String; let expectedUpHex: String; let expectedCtrlLeftHex: String }
        struct Queries: Decodable { let request: String; let keyboardReplyHex: String; let cursorReplyPrefixHex: String }
        struct Screen: Decodable { let enter: String; let leave: String; let normalText: String; let alternateText: String }
        struct Paste: Decodable { let enable: String; let text: String; let expectedHex: String }
        struct Enhanced: Decodable { let enable: String; var text: String?; let expectedHex: String }
        let legacyKeys: [Key]; let applicationArrow: Arrow; let queries: Queries
        let screen: Screen; let paste: Paste; let modeSeed: String
        struct Encoding: Decodable { let name: String; let key: String; let text: String?; let modifiers: Int; let flags: Int; let expectedHex: String; let applicationCursor: Bool? }
        let enhancedEscape: Enhanced; let enhancedQuickAction: Enhanced
        let encodingCases: [Encoding]; let replacementParserSeeds: [String]
        struct ModeQuery: Decodable { let request: String; let expectedHex: String }
        let freshModeQuery: ModeQuery
        struct Grid: Decodable { let columns: Int; let rows: Int }
        let replacementGrid: Grid
        struct NativeInput: Decodable {
            struct Commit: Decodable { let flags: Int; let text: String; let expectedHex: String }
            let hardware: Commit; let composition: Commit; let multiCharacter: Commit
        }
        let nativeInput: NativeInput
    }
    private func vectors() throws -> Vectors {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "terminal-compatibility-v1", withExtension: "json"))
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }
    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    func testLegacyMultiplexerPrefixesAndApplicationArrowsReachPTY() async throws {
        let fixture = try vectors()
        try await withHarness { rig in
            for key in fixture.legacyKeys {
                rig.record.clearReceived()
                if key.ctrl == true { rig.controller.terminal.keyboardState.toggle(.ctrl) }
                if key.alt == true { rig.controller.terminal.keyboardState.toggle(.alt) }
                rig.controller.terminal.insertText(key.text)
                try await terminalWait(key.name) { !rig.record.received.isEmpty }
                XCTAssertEqual(self.hex(rig.record.received), key.expectedHex, key.name)
                XCTAssertTrue(rig.controller.terminal.keyboardState.active.isEmpty)
            }
            try await rig.record.emit(fixture.applicationArrow.enable)
            try await terminalWait("application cursor mode") { rig.controller.terminal.getTerminal().applicationCursor }
            rig.record.clearReceived()
            try rig.tap("↑")
            try await terminalWait("application Up reaches PTY") { !rig.record.received.isEmpty }
            XCTAssertEqual(self.hex(rig.record.received), fixture.applicationArrow.expectedUpHex)
            rig.record.clearReceived()
            rig.controller.terminal.keyboardState.toggle(.ctrl)
            try rig.tap("←")
            try await terminalWait("modified Left reaches PTY") { !rig.record.received.isEmpty }
            XCTAssertEqual(self.hex(rig.record.received), fixture.applicationArrow.expectedCtrlLeftHex)
        }
    }

    func testQueriesAlternateScreenUnicodeAndPTYResize() async throws {
        let fixture = try vectors()
        try await withHarness { rig in
            rig.record.clearReceived()
            try await rig.record.emit(fixture.queries.request)
            try await terminalWait("keyboard and cursor replies") { self.hex(rig.record.received).contains(fixture.queries.keyboardReplyHex) && rig.record.received.last == 82 }
            XCTAssertTrue(self.hex(rig.record.received).hasPrefix(fixture.queries.keyboardReplyHex))
            XCTAssertTrue(self.hex(rig.record.received).dropFirst(fixture.queries.keyboardReplyHex.count).hasPrefix(fixture.queries.cursorReplyPrefixHex))
            try await rig.record.emit(fixture.screen.normalText)
            try await terminalWait("normal buffer output") { rig.text.contains(fixture.screen.normalText) }
            try await rig.record.emit(fixture.screen.enter + fixture.screen.alternateText)
            try await terminalWait("alternate Unicode output") { rig.text.contains(fixture.screen.alternateText) }
            XCTAssertTrue(rig.controller.terminal.getTerminal().isCurrentBufferAlternate)
            XCTAssertFalse(rig.text.contains(fixture.screen.normalText))
            rig.session.resize(columns: 96, rows: 28)
            try await terminalWait("PTY window change") { rig.record.size == [96, 28] }
            try await rig.record.emit(fixture.screen.leave)
            try await terminalWait("normal buffer restored") { rig.text.contains(fixture.screen.normalText) }
            XCTAssertFalse(rig.controller.terminal.getTerminal().isCurrentBufferAlternate)
        }
    }

    func testBracketedPasteIsOneOrderedPTYWriteWithoutImplicitReturn() async throws {
        let fixture = try vectors()
        try await withHarness { rig in
            try await rig.record.emit(fixture.paste.enable)
            try await terminalWait("paste mode") { rig.controller.terminal.getTerminal().bracketedPasteMode }
            rig.record.clearReceived()
            let prepared = try DirectComposedText(fixture.paste.text, mode: .terminal)
            var completed = false
            rig.session.sendComposedText(prepared.terminalBytes(bracketedPaste: rig.controller.terminal.getTerminal().bracketedPasteMode),
                                         generation: rig.session.composeGeneration) { issue in
                XCTAssertNil(issue); completed = true
            }
            try await terminalWait("complete paste") { completed && !rig.record.received.isEmpty }
            XCTAssertEqual(self.hex(rig.record.received), fixture.paste.expectedHex)
        }
    }

    func testSamePTYBackgroundResumePreservesModesAndNeverReplaysInput() async throws {
        let fixture = try vectors()
        try await withHarness { rig in
            try await rig.record.emit(fixture.modeSeed)
            try await terminalWait("multiplexer modes") { rig.controller.terminal.getTerminal().keyboardEnhancementFlags.rawValue == 1 }
            let generation = rig.session.outputGeneration
            let surface = rig.controller.terminal
            rig.controller.applyAppearance(.dark); rig.controller.applyAppearance(.light)
            XCTAssertEqual(rig.controller.preparedGeneration, generation)
            // DECSET 1004 immediately reports focus. Drain that legitimate
            // emulator reply before measuring whether paused user input replays.
            // The cursor reply is an ordered barrier over the same SSH stream.
            try await rig.record.emit(fixture.queries.request)
            try await terminalWait("mode replies drained") { rig.record.received.last == 82 }
            rig.record.clearReceived()
            rig.session.background(); await rig.session.waitForLifecycleUpdates()
            rig.session.send(Array("must-not-replay".utf8))
            rig.session.resize(columns: 100, rows: 30)
            XCTAssertTrue(rig.session.connected); XCTAssertTrue(rig.record.received.isEmpty, "Unexpected synthetic PTY bytes: " + self.hex(rig.record.received))
            rig.session.foreground(); await rig.session.waitForLifecycleUpdates()
            try await terminalWait("latest grid after resume") { rig.record.size == [100, 30] }
            XCTAssertEqual(rig.record.shellRequests, 1)
            XCTAssertEqual(rig.session.outputGeneration, generation)
            XCTAssertEqual(rig.controller.preparedGeneration, generation)
            XCTAssertTrue(surface === rig.controller.terminal)
            XCTAssertTrue(rig.controller.terminal.getTerminal().isCurrentBufferAlternate)
            XCTAssertTrue(rig.controller.terminal.getTerminal().bracketedPasteMode)
            XCTAssertEqual(rig.controller.terminal.getTerminal().keyboardEnhancementFlags.rawValue, 1)
            XCTAssertTrue(rig.record.received.isEmpty, "Unexpected synthetic PTY bytes: " + self.hex(rig.record.received))
        }
    }

    func testReplacementPTYStartsWithFreshEmulatorModes() async throws {
        let fixture = try vectors()
        try await withHarness { rig in
            try await rig.record.emit(fixture.modeSeed)
            try await terminalWait("old PTY modes") { rig.controller.terminal.getTerminal().keyboardEnhancementFlags.rawValue == 1 }
            let prepare = rig.session.prepareTerminal
            rig.session.prepareTerminal = { [weak rig] generation in
                prepare?(generation)
                rig?.session.resize(columns: fixture.replacementGrid.columns, rows: fixture.replacementGrid.rows)
            }
            let oldSizeCount = rig.record.sizes.count
            rig.session.stop()
            try await terminalWait("disconnected UI") { !rig.controller.terminal.isUserInteractionEnabled }
            rig.connect()
            try await terminalWait("replacement PTY") { rig.session.connected && rig.record.shellRequests == 2 }
            try await terminalWait("replacement surface") { rig.controller.terminal.isUserInteractionEnabled }
            try await terminalWait("grid changed during PTY preparation reaches writer") {
                rig.record.sizes.dropFirst(oldSizeCount).contains([fixture.replacementGrid.columns, fixture.replacementGrid.rows])
            }
            let grid = rig.controller.terminal.getTerminal()
            XCTAssertFalse(grid.isCurrentBufferAlternate)
            XCTAssertFalse(grid.applicationCursor)
            XCTAssertFalse(grid.bracketedPasteMode)
            XCTAssertEqual(grid.mouseMode, .off)
            XCTAssertTrue(grid.keyboardEnhancementFlags.isEmpty)
            rig.record.clearReceived()
            try await rig.record.emit(fixture.freshModeQuery.request)
            try await terminalWait("fresh cursor, focus and mouse protocols") { rig.record.received.count >= fixture.freshModeQuery.expectedHex.count / 2 }
            XCTAssertEqual(self.hex(rig.record.received), fixture.freshModeQuery.expectedHex)
        }
    }

    func testEnhancedToolbarEscapeUsesNegotiatedEncoding() async throws {
        let value = try vectors().enhancedEscape
        try await withHarness { rig in
            try await rig.record.emit(value.enable)
            try await terminalWait("enhanced keyboard") { !rig.controller.terminal.getTerminal().keyboardEnhancementFlags.isEmpty }
            rig.record.clearReceived(); try rig.tap("Esc")
            try await terminalWait("toolbar Escape write") { !rig.record.received.isEmpty }
            XCTAssertEqual(self.hex(rig.record.received), value.expectedHex)
        }
    }

    func testEnhancedSavedShortcutUsesNegotiatedEncoding() async throws {
        let value = try vectors().enhancedQuickAction
        try await withHarness { rig in
            try await rig.record.emit(value.enable)
            try await terminalWait("enhanced keyboard") { !rig.controller.terminal.getTerminal().keyboardEnhancementFlags.isEmpty }
            rig.record.clearReceived()
            let action = VNCQuickAction(title: "Synthetic prefix", kind: .shortcut, key: 98, modifiers: [0xffe3])
            rig.controller.terminal.sendShortcut(action)
            try await terminalWait("saved shortcut write") { !rig.record.received.isEmpty }
            XCTAssertEqual(self.hex(rig.record.received), value.expectedHex)
        }
    }

    func testUppercaseSavedKeysUseUnshiftedIdentityAndRequestedShiftMetadata() async throws {
        let cases = try vectors().encodingCases.filter {
            $0.name.hasPrefix("saved-uppercase-") || $0.name == "all-text-uppercase"
        }
        XCTAssertEqual(cases.count, 10)
        try await withHarness { rig in
            for value in cases {
                try await rig.record.emit("\u{1b}[=\(value.flags)u")
                try await terminalWait(value.name + " negotiation") {
                    rig.controller.terminal.getTerminal().keyboardEnhancementFlags.rawValue == value.flags
                }
                let scalar = try XCTUnwrap(value.text?.unicodeScalars.first)
                let modifiers: [UInt32] = [(1, UInt32(0xffe1)), (2, 0xffe9), (4, 0xffe3)]
                    .compactMap { value.modifiers & $0.0 != 0 ? $0.1 : nil }
                let action = VNCQuickAction(title: "Synthetic uppercase", kind: .shortcut,
                                            key: scalar.value, modifiers: modifiers)
                XCTAssertTrue(action.valid, value.name)
                rig.controller.terminal.keyboardState.toggle(.ctrl)
                rig.record.clearReceived()
                rig.controller.terminal.sendShortcut(action)
                try await terminalWait(value.name + " saved-key packet") {
                    !rig.record.received.isEmpty
                }
                XCTAssertEqual(self.hex(rig.record.received), value.expectedHex, value.name)
                XCTAssertTrue(rig.controller.terminal.keyboardState.active.isEmpty)
            }
        }
    }

    func testNegotiatedExplicitKeysMatchGoldenVectors() async throws {
        let fixture = try vectors()
        try await withHarness { rig in
            for value in fixture.encodingCases {
                let applicationCursor = value.applicationCursor == true
                try await rig.record.emit("\u{1b}[?1" + (applicationCursor ? "h" : "l") + "\u{1b}[=\(value.flags)u")
                try await terminalWait(value.name + " negotiation") {
                    rig.controller.terminal.getTerminal().keyboardEnhancementFlags.rawValue == value.flags &&
                    rig.controller.terminal.getTerminal().applicationCursor == applicationCursor
                }
                let key: TerminalKeyInput
                switch value.key {
                case "enter": key = .enter
                case "backspace": key = .backspace
                case "text": key = .text(try XCTUnwrap(value.text))
                default: key = .accessory(try XCTUnwrap(TerminalAccessoryKey(rawValue: value.key)))
                }
                rig.record.clearReceived()
                rig.controller.terminal.sendKey(key, modifiers: .init(rawValue: value.modifiers))
                try await terminalWait(value.name + " complete packet") { rig.record.received.count >= value.expectedHex.count / 2 }
                XCTAssertEqual(self.hex(rig.record.received), value.expectedHex, value.name)
                let control: String? = value.modifiers == 0 ? ["escape": "escape", "tab": "tab", "enter": "returnKey"][value.key] :
                    (value.key == "text" && value.text == "c" && value.modifiers == 4 ? "interrupt" : nil)
                if let control {
                    rig.record.clearReceived()
                    rig.controller.controls.actionHandler?(["kind": control])
                    try await terminalWait(value.name + " menu packet") { rig.record.received.count >= value.expectedHex.count / 2 }
                    XCTAssertEqual(self.hex(rig.record.received), value.expectedHex, "Session menu " + value.name)
                }
            }
        }
    }

    func testSoftwareModifiersPreserveNativeEditingCompositionAndLock() async throws {
        let fixture = try vectors()
        try await withHarness { rig in
            let terminal = rig.controller.terminal
            try await rig.record.emit(fixture.enhancedEscape.enable)
            try await terminalWait("enhanced keyboard") { terminal.getTerminal().keyboardEnhancementFlags.rawValue == 1 }
            terminal.keyboardState.toggle(.shift); terminal.keyboardState.toggle(.ctrl)
            rig.record.clearReceived(); terminal.insertText("b")
            let expected = try XCTUnwrap(fixture.encodingCases.first { $0.name == "ctrl-shift-b" }).expectedHex
            try await terminalWait("Ctrl Shift text") { !rig.record.received.isEmpty }
            XCTAssertEqual(self.hex(rig.record.received), expected)
            XCTAssertTrue(terminal.hasText, "Modified text keeps native range bookkeeping")
            XCTAssertTrue(terminal.keyboardState.active.isEmpty)
            terminal.keyboardState.toggle(.alt, lock: true)
            terminal.keyboardState.toggle(.ctrl)
            rig.record.clearReceived(); terminal.deleteBackward()
            let deletion = try XCTUnwrap(fixture.encodingCases.first { $0.name == "ctrl-alt-backspace" }).expectedHex
            try await terminalWait("modified deletion") { !rig.record.received.isEmpty }
            XCTAssertEqual(self.hex(rig.record.received), deletion)
            XCTAssertFalse(terminal.hasText); XCTAssertEqual(terminal.keyboardState.active, .alt)
            terminal.resetModifiers()
            terminal.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0))
            rig.record.clearReceived(); terminal.keyboardState.toggle(.ctrl); terminal.deleteBackward()
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertTrue(rig.record.received.isEmpty, "Editing preedit must remain local")
            terminal.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0))
            terminal.unmarkText()
            try await terminalWait("IME commit") { !rig.record.received.isEmpty }
            XCTAssertEqual(rig.record.received, Array("中文".utf8))
        }
    }

    func testReplacementDiscardsPartialParserAndCompositionBeforeFirstOutput() async throws {
        let fixture = try vectors()
        try await withHarness { rig in
            let seeds = fixture.replacementParserSeeds.map { Array($0.utf8) } + [[0xf0, 0x9f]]
            for seed in seeds {
                let terminal = rig.controller.terminal
                terminal.setMarkedText("retired-preedit", selectedRange: NSRange(location: 0, length: 0))
                terminal.keyboardState.toggle(.alt, lock: true)
                let oldGeneration = rig.session.outputGeneration
                let rendered = rig.renderedBytes.count
                try await rig.record.emit(bytes: seed)
                try await terminalWait("old parser bytes consumed") { rig.renderedBytes.count >= rendered + seed.count }
                rig.session.stop(); let count = rig.record.shellRequests
                rig.connect()
                try await terminalWait("replacement shell output") {
                    rig.record.shellRequests == count + 1 && rig.session.connected && rig.text.contains("synthetic-ready")
                }
                XCTAssertNotEqual(rig.session.outputGeneration, oldGeneration)
                XCTAssertEqual(rig.controller.preparedGeneration, rig.session.outputGeneration)
                XCTAssertFalse(terminal === rig.controller.terminal)
                XCTAssertNil(rig.controller.terminal.markedTextRange); XCTAssertFalse(rig.controller.terminal.hasText)
                XCTAssertTrue(rig.controller.terminal.keyboardState.active.isEmpty)
                XCTAssertNil(rig.controller.presentedViewController, "A retired OSC must not produce a prompt")
                rig.record.clearReceived()
                terminal.insertText("retired-view-input")
                XCTAssertNil(terminal.customInputEpoch())
                XCTAssertFalse(terminal.performCustomInput { terminal.sendKey(.text("retired-accessory")) })
                rig.controller.send(source: terminal, data: Array("retired-callback".utf8)[...])
                rig.controller.terminal.insertText("x")
                try await terminalWait("fresh input") { !rig.record.received.isEmpty }
                XCTAssertEqual(rig.record.received, [0x78], "No reset bytes or old composition may reach SSH")
            }
        }
    }

    func testNativeHardwareKeysKeepTheirOwnPressAndRelease() async throws {
        let value = try vectors().nativeInput.hardware
        try await withHarness { rig in
            let terminal = rig.controller.terminal
            try await rig.record.emit("\u{1b}[=\(value.flags)u")
            try await terminalWait("native event mode") { terminal.getTerminal().keyboardEnhancementFlags.rawValue == value.flags }
            for modifier: TerminalModifiers in [.ctrl, .alt, .shift] {
                terminal.keyboardState.toggle(modifier, lock: true)
                rig.record.clearReceived()
                let press = CompatibilityPress(CompatibilityKey(value.text))
                terminal.pressesBegan([press], with: nil)
                terminal.insertText(value.text)
                terminal.pressesEnded([press], with: nil)
                try await terminalWait("native press and release") { rig.record.received.count >= value.expectedHex.count / 2 }
                try await Task.sleep(for: .milliseconds(30))
                XCTAssertEqual(self.hex(rig.record.received), value.expectedHex)
                XCTAssertTrue(terminal.keyboardState.active.isEmpty)
            }
        }
    }

    func testNativeCompositionAndMultiCharacterCommitsIgnoreShortcutModifiers() async throws {
        let values = try vectors().nativeInput
        try await withHarness { rig in
            let terminal = rig.controller.terminal
            try await rig.record.emit("\u{1b}[=\(values.composition.flags)u")
            try await terminalWait("native commit mode") { terminal.getTerminal().keyboardEnhancementFlags.rawValue == values.composition.flags }
            for modifier: TerminalModifiers in [.ctrl, .alt, .shift] {
                for marked in [true, false] {
                    let value = marked ? values.composition : values.multiCharacter
                    terminal.resetModifiers()
                    terminal.keyboardState.toggle(modifier, lock: true)
                    rig.record.clearReceived()
                    if marked {
                        terminal.setMarkedText(value.text, selectedRange: NSRange(location: value.text.utf16.count, length: 0))
                        terminal.unmarkText()
                    } else { terminal.insertText(value.text) }
                    try await terminalWait("native text commit") { rig.record.received.count >= value.expectedHex.count / 2 }
                    try await Task.sleep(for: .milliseconds(30))
                    XCTAssertEqual(self.hex(rig.record.received), value.expectedHex)
                    XCTAssertNil(terminal.markedTextRange)
                    XCTAssertEqual(terminal.keyboardState.active, modifier)
                }
            }
        }
    }

    func testRetiredQueuedInputAndComposerCannotReachReplacementPTY() async throws {
        try await withHarness { rig in
            let oldGeneration = rig.session.composeGeneration
            rig.session.send(Array("retired-queued-input".utf8))
            rig.session.stop(); rig.record.clearReceived(); rig.connect()
            try await terminalWait("replacement ready") { rig.session.connected && rig.record.shellRequests == 2 }
            var completed = false
            rig.session.sendComposedText(Array("retired-composer".utf8), generation: oldGeneration) { issue in
                XCTAssertNotNil(issue); completed = true
            }
            try await terminalWait("retired composer rejected") { completed }
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertTrue(rig.record.received.isEmpty)
        }
    }

    private func withHarness(_ body: (TerminalCompatibilityHarness) async throws -> Void) async throws {
        let rig = try await TerminalCompatibilityHarness.make()
        do { try await body(rig); await rig.close() }
        catch { await rig.close(); throw error }
    }
}

@MainActor private final class CompatibilityKey: UIKey {
    private let value: String
    init(_ value: String) { self.value = value; super.init() }
    required init?(coder: NSCoder) { fatalError("Synthetic keys are not decoded") }
    override var keyCode: UIKeyboardHIDUsage { .keyboardB }
    override var characters: String { value }
    override var charactersIgnoringModifiers: String { value }
    override var modifierFlags: UIKeyModifierFlags { [] }
}
private final class CompatibilityPress: UIPress {
    private let sample: UIKey
    init(_ key: UIKey) { sample = key; super.init() }
    override var key: UIKey? { sample }
}

@MainActor private func terminalWait(_ description: String, seconds: Double = 8, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Timed out waiting for " + description)
    throw POSIXError(.ETIMEDOUT)
}

@MainActor private final class TerminalCompatibilityHarness {
    let record: SSHTestRecord
    let server: Channel
    let session: DirectTerminalSession
    let window: UIWindow
    let previous: UIWindow?
    let host: TerminalController
    var controller: TerminalController { host }
    private var observingSession = true
    var renderedBytes = [UInt8]()
    var text: String { terminalCompatibilityText(controller.terminal.getTerminal()) }
    private init(record: SSHTestRecord, server: Channel, mac: DirectMacRecordV1, scene: UIWindowScene) {
        self.record = record; self.server = server
        session = DirectTerminalSession(mac: mac)
        previous = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene)
        // Protocol cases exercise the production native surface directly. The
        // native journey target separately covers the complete SwiftUI flow.
        // A second SwiftUI root during application launch can enter an unrelated
        // appearance cycle before a representable controller is ever created.
        host = TerminalController(session: session, customize: {})
        window.rootViewController = host; window.makeKeyAndVisible()
        host.loadViewIfNeeded(); window.layoutIfNeeded()
        projectSessionState()
    }
    static func make() async throws -> TerminalCompatibilityHarness {
        // Query replies must not be echoed back as new terminal requests.
        let record = SSHTestRecord(echoInput: false), key = NIOSSHPrivateKey(ed25519Key: .init())
        let auth = SSHTestAuth(record)
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
            record.openedTransport(channel)
            return channel.pipeline.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [key], userAuthDelegate: auth)), allocator: channel.allocator,
                inboundChildChannelInitializer: { child, _ in child.pipeline.addHandler(SSHTestPTY(record)) }))
        }.bind(host: "127.0.0.1", port: 0).get()
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Compatibility", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        do {
            try TerminalSecretStore.write(Data(String(openSSHPublicKey: key.publicKey).utf8), id: mac.id, kind: "host-key")
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            try await terminalWait("active QA window") {
                UIApplication.shared.applicationState == .active && scene.activationState == .foregroundActive
                    && scene.windows.contains { $0.isKeyWindow && $0.rootViewController?.viewIfLoaded?.window != nil }
            }
            let rig = TerminalCompatibilityHarness(record: record, server: server, mac: mac, scene: scene)
            do {
                try await terminalWait("hosted terminal") {
                    rig.host.viewIfLoaded?.window === rig.window && rig.session.received != nil && rig.session.prepareTerminal != nil
                }
                let receive = rig.session.received
                rig.session.received = { [weak rig] bytes in receive?(bytes); rig?.renderedBytes += bytes }
                rig.connect()
                try await terminalWait("authenticated compatibility PTY") { rig.session.connected || rig.session.recovery != nil }
                XCTAssertTrue(rig.session.connected, rig.session.status)
                try await terminalWait("initial shell output") { rig.text.contains("synthetic-ready") }
                return rig
            } catch { await rig.close(); throw error }
        } catch { try? TerminalSecretStore.remove(mac.id); try? await server.close(); throw error }
    }
    func connect() { session.connect(username: "synthetic", password: "synthetic-only", remember: false) }
    private func projectSessionState() {
        guard observingSession else { return }
        // Mirror TerminalSurface.updateUIViewController's observed projection.
        // Keep genuine session state, input admission and controller callbacks.
        withObservationTracking {
            controller.terminal.isUserInteractionEnabled = session.connected
            controller.updateControls()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.projectSessionState() }
        }
    }
    func tap(_ title: String) throws {
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        if let button = descendants(controller.keyboardBar).compactMap({ $0 as? UIButton }).first(where: { $0.configuration?.title == title }) {
            button.sendActions(for: .touchUpInside)
        } else {
            let key = try XCTUnwrap(TerminalAccessoryKey.allCases.first { $0.title == title })
            let menu = controller.makeMoreKeysMenu(), kind = "terminalKey-" + key.rawValue
            let item = try XCTUnwrap(menu.sections.flatMap { $0["items"] as? [[String: Any]] ?? [] }.first { $0["kind"] as? String == kind })
            menu.selectionHandler?(item)
        }
    }
    func close() async {
        observingSession = false
        window.endEditing(true)
        session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
        try? TerminalSecretStore.remove(session.mac.id)
        try? await server.close()
    }
}
