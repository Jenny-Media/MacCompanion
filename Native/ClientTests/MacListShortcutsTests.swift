#if os(iOS)
import XCTest
@testable import Mac_Companion

@MainActor final class MacListShortcutsTests: XCTestCase {
    func testLegacyRecordsKeepTapAndGainSwipeDefaultsWithoutRewritingOnRead() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for version in 1...5 {
            let url = folder.appending(path: "legacy-\(version).json")
            let record: [String: Any] = ["id": UUID().uuidString, "name": "Synthetic Legacy", "address": "legacy.invalid", "preferredConnection": "terminal"]
            let bytes = try JSONSerialization.data(withJSONObject: ["version": version, "macs": [record]])
            try bytes.write(to: url)
            let library = DirectMacLibraryV1(url: url)
            let mac = try XCTUnwrap(library.macs.first)
            XCTAssertTrue(library.readable)
            XCTAssertEqual(mac.preferredConnection, .terminal)
            XCTAssertEqual(mac.swipeLeft.connection, .terminal)
            XCTAssertEqual(mac.swipeRight.connection, .trackpad)
            XCTAssertEqual(try Data(contentsOf: url), bytes, "Loading must not rewrite the library or touch a login")
        }
    }

    func testIndependentShortcutsPersistThroughRenameAddressEditAndReorder() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "macs.json")
        var loginRemovals = 0
        let library = DirectMacLibraryV1(url: url, removeLogin: { _ in loginRemovals += 1 })
        let first = UUID(), second = UUID()
        XCTAssertTrue(library.save(id: first, name: "First", addresses: ["first.invalid"], preferredConnection: .trackpad,
                                   swipeLeft: .disabled, swipeRight: .terminal))
        XCTAssertTrue(library.save(id: second, name: "Second", addresses: ["second.invalid"], preferredConnection: .terminal,
                                   swipeLeft: .desktop, swipeRight: .disabled))
        XCTAssertTrue(library.save(id: first, name: "Renamed", addresses: ["new.invalid"], port: 5901, sshPort: 2222))
        XCTAssertTrue(library.move(fromOffsets: IndexSet(integer: 0), toOffset: 2))
        let reloaded = DirectMacLibraryV1(url: url)
        XCTAssertEqual(reloaded.macs.map(\.id), [second, first])
        XCTAssertEqual(reloaded.macs[0].preferredConnection, .terminal)
        XCTAssertEqual(reloaded.macs[0].swipeLeft, .desktop)
        XCTAssertEqual(reloaded.macs[0].swipeRight, .disabled)
        XCTAssertEqual(reloaded.macs[1].preferredConnection, .trackpad)
        XCTAssertEqual(reloaded.macs[1].swipeLeft, .disabled)
        XCTAssertEqual(reloaded.macs[1].swipeRight, .terminal)
        XCTAssertEqual(reloaded.macs[1].addresses, ["new.invalid"])
        XCTAssertEqual(loginRemovals, 0)
    }

    func testEverySwipeActionRoundTripsIncludingExplicitNone() throws {
        for action in DirectMacSwipeAction.allCases {
            var mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Choice", addresses: ["choice.invalid"])
            mac.swipeLeft = action; mac.swipeRight = action
            let restored = try JSONDecoder().decode(DirectMacRecordV1.self, from: JSONEncoder().encode(mac))
            XCTAssertEqual(restored, mac)
            XCTAssertEqual(restored.swipeLeft.connection, action.connection)
        }
        XCTAssertNil(DirectMacSwipeAction.disabled.connection)
    }

    func testUnknownSwipeActionProtectsTheExistingFileFromOverwrite() throws {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let mac: [String: Any] = ["id": UUID().uuidString, "name": "Synthetic Future", "addresses": ["future.invalid"], "swipeLeft": "unsupported"]
        let bytes = try JSONSerialization.data(withJSONObject: ["version": 5, "macs": [mac]])
        try bytes.write(to: url)
        let library = DirectMacLibraryV1(url: url)
        XCTAssertFalse(library.readable)
        XCTAssertFalse(library.save(id: nil, name: "Overwrite", addresses: ["overwrite.invalid"]))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testOptionalMetadataSyncKeepsBothSwipeChoices() throws {
        var mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Sync", addresses: ["sync.invalid"])
        mac.preferredConnection = .terminal; mac.swipeLeft = .trackpad; mac.swipeRight = .disabled
        let version = DirectCloudVersion(id: mac.id, writer: UUID(), revision: 1, mac: mac, preferences: .init(mac: mac.id))
        let restored = try JSONDecoder().decode(DirectCloudVersion.self, from: JSONEncoder().encode(version))
        XCTAssertNoThrow(try restored.validate())
        XCTAssertEqual(DirectCloudVersion.winners(try DirectCloudVersion.merge([], [restored]))[mac.id]?.mac, mac)
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DirectMacLibraryV1(url: folder.appending(path: "macs.json"))
        try library.applyCloud([mac])
        XCTAssertEqual(DirectMacLibraryV1(url: library.storageURL).macs, [mac])
    }
}

private final class RecordingInterfaceFeedback: CompanionVNCInterfaceFeedback {
    var active = true
    var events: [String] = []
    override var foreground: Bool { active }
    override func emitFeedback(_ kind: String) { events.append(kind) }
}

@MainActor final class InterfaceFeedbackTests: XCTestCase {
    private func withFeedback(_ test: (UserDefaults, RecordingInterfaceFeedback) -> Void) {
        let suite = "synthetic-interface-feedback-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        test(defaults, RecordingInterfaceFeedback(defaults: defaults))
    }
    func testExistingPreferenceDefaultsOnAndDisablingItSuppressesEveryInterfaceEvent() {
        withFeedback { defaults, feedback in
            feedback.feedback("open")
            XCTAssertEqual(feedback.events, ["open"])
            defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
            for kind in ["selection", "open", "commit", "end", "success", "error"] { feedback.feedback(kind) }
            XCTAssertEqual(feedback.events, ["open"])
            defaults.set(true, forKey: CompanionVNCControlsHapticsPreference)
            feedback.feedback("selection")
            XCTAssertEqual(feedback.events, ["open", "selection"])
        }
    }
    func testRepeatedAcceptedActionsEmitOnceEachAndIgnoreDismissOrAutomaticActivity() {
        withFeedback { _, feedback in
            for kind in ["open", "open", "selection", "end", "success", "error"] { feedback.feedback(kind) }
            XCTAssertEqual(feedback.events, ["open", "open", "selection", "end", "success", "error"])
            for kind in ["back", "dismiss", "reconnect", "pointer", "typing"] { feedback.feedback(kind) }
            XCTAssertEqual(feedback.events.count, 6)
        }
    }
    func testInactiveAppEmitsNothingAndTrackpadPreferenceRemainsIndependent() {
        withFeedback { defaults, feedback in
            defaults.set(false, forKey: "direct-controls-trackpad-haptics")
            feedback.feedback("open")
            XCTAssertEqual(feedback.events, ["open"])
            feedback.active = false
            feedback.feedback("success"); feedback.feedback("end")
            XCTAssertEqual(feedback.events, ["open"])
            feedback.active = true
            feedback.feedback("end")
            XCTAssertEqual(feedback.events, ["open", "end"])
            XCTAssertFalse(defaults.bool(forKey: "direct-controls-trackpad-haptics"))
        }
    }
}

#endif
