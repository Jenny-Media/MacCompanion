#if os(macOS)
import XCTest
@testable import MacCompanion

@MainActor final class MacToolApplicationModelTests: XCTestCase {
    private func withLibrary(_ body: (DirectMacLibraryV1, DirectMacRecordV1) async throws -> Void) async throws {
        let root = URL.temporaryDirectory.appending(path: "mac-tool-model-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DirectMacLibraryV1(url: root.appending(path: "existing-library.json"))
        XCTAssertTrue(library.save(id: nil, name: "Synthetic Mac", addresses: ["127.0.0.1"], usesAutomaticName: false))
        try await body(library, XCTUnwrap(library.macs.first))
    }
    private func settle(_ predicate: () -> Bool) async throws {
        for _ in 0..<1000 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Native handoff did not settle")
    }
    func testInstallPreservesExistingLibraryAndWaitsForExplicitAction() async throws {
        try await withLibrary { library, mac in
            var launches: [URL] = [], terminals: [UUID] = []
            let model = MacToolApplicationModel(library: library, openScreenSharing: { launches.append($0) }, canAccess: { true })
            model.install { _, id in terminals.append(id) }
            XCTAssertTrue(model.library === library)
            XCTAssertTrue(launches.isEmpty && terminals.isEmpty, "Model installation or restoration cannot launch tools")
            let request = MacToolApplicationModel.snapshot(mac)
            model.coordinator?.open(request, action: .desktop)
            try await settle { !launches.isEmpty }
            XCTAssertEqual(launches.map(\.absoluteString), ["vnc://127.0.0.1:5900"])
            XCTAssertTrue(terminals.isEmpty)
        }
    }
    func testRestoredTerminalReusesItsStableRequestWithoutLaunchingScreenSharing() async throws {
        try await withLibrary { library, mac in
            var terminals: [UUID] = [], launches = 0
            let model = MacToolApplicationModel(library: library, openScreenSharing: { _ in launches += 1 }, canAccess: { true })
            model.install { _, id in terminals.append(id) }
            let restored = MacSessionRequest(macID: mac.id, mode: .terminal)
            model.coordinator?.terminalOpened(macID: mac.id, windowID: restored.id)
            model.coordinator?.open(MacToolApplicationModel.snapshot(mac), action: .terminal)
            XCTAssertEqual(terminals, [restored.id]); XCTAssertEqual(launches, 0)
            let reopened = MacSessionRequest(id: terminals[0], macID: mac.id, mode: .terminal)
            XCTAssertEqual(restored, reopened)
        }
    }
    func testLockAndEditedRecordCannotLaunchThroughInstalledModel() async throws {
        try await withLibrary { library, mac in
            var allowed = false, launches = 0
            let model = MacToolApplicationModel(library: library, openScreenSharing: { _ in launches += 1 }, canAccess: { allowed })
            model.install { _, _ in XCTFail("Blocked action opened Terminal") }
            let original = MacToolApplicationModel.snapshot(mac)
            model.coordinator?.open(original, action: .desktop)
            XCTAssertTrue(model.coordinator?.states.isEmpty == true)
            allowed = true
            XCTAssertTrue(library.save(id: mac.id, name: mac.name, addresses: ["127.0.0.2"], usesAutomaticName: false))
            model.coordinator?.open(original, action: .desktop)
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertEqual(launches, 0)
        }
    }
}
#endif
