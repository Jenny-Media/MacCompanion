import XCTest
import Security
import SwiftUI
@testable import Mac_Companion

@MainActor final class DirectMacLibraryTests: XCTestCase {
    func testInputSettingsRendersTheSavedFollowCursorOptOut() throws {
        let id = UUID(); defer { VNCSessionPreferences.clear(id) }
        VNCSessionPreferences.setFollowCursor(false, mac: id)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: VNCInputSettings(macID: id, changed: {}))
        window.rootViewController = controller; window.makeKeyAndVisible(); window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertNotNil(controller.view.window); XCTAssertFalse(VNCSessionPreferences.followCursor(id))
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = "Synthetic Follow Cursor input settings"
        attachment.lifetime = .keepAlways; add(attachment)
        window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
    }
    private func profile() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    func testIndexedEditorPortsResolveBlankToDefaultAndRejectInvalidOverrides() throws {
        let cases = try XCTUnwrap(try profile()["editorPortCases"] as? [[String: Any]])
        for vector in cases {
            let text = try XCTUnwrap(vector["text"] as? String)
            XCTAssertEqual(DirectMacRecordV1.port(from: text), vector["resolvedPort"] as? Int, "Port vector: \(text)")
        }
    }
    func testClearingCustomPortPersistsDefaultWithoutRemovingSavedLogin() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString), id = UUID()
        defer { try? FileManager.default.removeItem(at: folder); try? DesktopCredentialStoreV1.remove(id) }
        let url = folder.appending(path: "macs.json"), library = DirectMacLibraryV1(url: url)
        XCTAssertTrue(library.save(id: id, name: "Test Mac", addresses: ["test.local"], port: 5901))
        let login = DesktopCredentialStoreV1.Login(username: "synthetic-account", password: "synthetic-only")
        try DesktopCredentialStoreV1.save(login, hostID: id)
        let clearedPort = try XCTUnwrap(DirectMacRecordV1.port(from: ""))
        XCTAssertTrue(library.save(id: id, name: "Test Mac", addresses: ["test.local"], port: clearedPort))
        XCTAssertEqual(DirectMacLibraryV1(url: url).macs.first?.port, 5900)
        XCTAssertEqual(library.macs.first?.id, id)
        XCTAssertEqual(DesktopCredentialStoreV1.read(id)?.username, login.username)
        XCTAssertEqual(DesktopCredentialStoreV1.read(id)?.password, login.password)
        let before = try Data(contentsOf: url)
        XCTAssertNil(DirectMacRecordV1.port(from: "0"))
        XCTAssertFalse(library.save(id: id, name: "Test Mac", addresses: ["test.local"], port: 0))
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(library.macs.first?.port, 5900)
        XCTAssertEqual(DesktopCredentialStoreV1.read(id)?.username, login.username)
    }
    func testIndexedAddressAndPortEditsKeepTheActualMacLogin() throws {
        let cases = try XCTUnwrap(try profile()["macLibraryEditCases"] as? [[String: Any]])
        for vector in cases {
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString), id = UUID()
            defer { try? FileManager.default.removeItem(at: folder); try? DesktopCredentialStoreV1.remove(id) }
            let library = DirectMacLibraryV1(url: folder.appending(path: "macs.json"))
            XCTAssertTrue(library.save(id: id, name: "Test Mac", addresses: try XCTUnwrap(vector["before"] as? [String]), port: try XCTUnwrap(vector["beforePort"] as? Int)))
            let login = DesktopCredentialStoreV1.Login(username: "synthetic-account", password: "synthetic-only")
            try DesktopCredentialStoreV1.save(login, hostID: id)
            XCTAssertTrue(library.save(id: id, name: "Renamed", addresses: try XCTUnwrap(vector["after"] as? [String]), port: try XCTUnwrap(vector["afterPort"] as? Int)))
            XCTAssertEqual(DesktopCredentialStoreV1.read(id)?.username, login.username)
            XCTAssertEqual(DesktopCredentialStoreV1.read(id)?.password, login.password)
            XCTAssertEqual(vector["retainsLogin"] as? Bool, true)
        }
    }
    func testSharedEndpointPersistsAndKeepsIndependentAccountLogins() throws {
        let policy = try XCTUnwrap(try profile()["macLibraryPolicy"] as? [String: Any])
        XCTAssertEqual(policy["sharedEndpointAcrossRecordsAllowed"] as? Bool, true)
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString), first = UUID(), second = UUID()
        defer { try? FileManager.default.removeItem(at: folder); try? DesktopCredentialStoreV1.remove(first); try? DesktopCredentialStoreV1.remove(second) }
        let url = folder.appending(path: "macs.json"), library = DirectMacLibraryV1(url: url)
        XCTAssertTrue(library.save(id: first, name: "Account A", addresses: ["shared.local"]))
        XCTAssertTrue(library.save(id: second, name: "Account B", addresses: ["SHARED.LOCAL"]))
        try DesktopCredentialStoreV1.save(.init(username: "synthetic-a", password: "synthetic-a-only"), hostID: first)
        try DesktopCredentialStoreV1.save(.init(username: "synthetic-b", password: "synthetic-b-only"), hostID: second)
        let reopened = DirectMacLibraryV1(url: url)
        XCTAssertTrue(reopened.readable); XCTAssertEqual(reopened.macs.count, 2)
        XCTAssertEqual(reopened.sharingEndpoint(addresses: [" SHARED.LOCAL "], port: 5900, excluding: second).map(\.id), [first])
        XCTAssertTrue(reopened.sharingEndpoint(addresses: ["shared.local"], port: 5901, excluding: second).isEmpty)
        XCTAssertEqual(DesktopCredentialStoreV1.read(first)?.username, "synthetic-a")
        XCTAssertEqual(DesktopCredentialStoreV1.read(second)?.username, "synthetic-b")
        reopened.forgetLogin(reopened.macs[0]); XCTAssertNil(DesktopCredentialStoreV1.read(first))
        XCTAssertEqual(DesktopCredentialStoreV1.read(second)?.username, "synthetic-b")
        reopened.remove(reopened.macs[1]); XCTAssertNil(DesktopCredentialStoreV1.read(second))
    }
    func testFailedAddressEditDoesNotDeleteTheSavedLogin() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString), id = UUID(), url = folder.appending(path: "macs.json")
        defer { try? FileManager.default.removeItem(at: folder); try? DesktopCredentialStoreV1.remove(id) }
        let library = DirectMacLibraryV1(url: url)
        XCTAssertTrue(library.save(id: id, name: "Test Mac", address: "first.local"))
        let before = library.macs
        try DesktopCredentialStoreV1.save(.init(username: "synthetic-account", password: "synthetic-only"), hostID: id)
        try FileManager.default.removeItem(at: url); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        XCTAssertFalse(library.save(id: id, name: "Test Mac", address: "changed.local"))
        XCTAssertEqual(library.macs, before)
        XCTAssertEqual(DesktopCredentialStoreV1.read(id)?.username, "synthetic-account")
    }
    func testUnreadableCustomActionsArePreservedInsteadOfOverwritten() throws {
        let id = UUID(), damaged = Data("invalid synthetic entry".utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "media.jenny.maccompanion.direct-actions.v1",
            kSecAttrAccount as String: id.uuidString.lowercased(), kSecAttrSynchronizable as String: false]
        defer { VNCSessionPreferences.clear(id) }
        XCTAssertEqual(SecItemAdd(query.merging([kSecValueData as String: damaged]) { _, new in new } as CFDictionary, nil), errSecSuccess)
        XCTAssertThrowsError(try VNCSessionPreferences.readActions(id))
        XCTAssertThrowsError(try VNCSessionPreferences.saveActions(VNCQuickAction.defaults, mac: id))
        var read = query; read[kSecReturnData as String] = true
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(read as CFDictionary, &result), errSecSuccess)
        XCTAssertEqual(result as? Data, damaged)
    }
    func testVersionOneMigrationKeepsMacIdentityAndReorderingKeepsLogin() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "macs.json"), id = UUID()
        let old: [String: Any] = ["version": 1, "macs": [["id": id.uuidString, "name": "Mac", "address": "mac.local"]]]
        try JSONSerialization.data(withJSONObject: old).write(to: url)
        var removed: [UUID] = []
        let library = DirectMacLibraryV1(url: url, removeLogin: { removed.append($0) })
        XCTAssertEqual(library.macs.first?.id, id); XCTAssertEqual(library.macs.first?.port, 5900)
        XCTAssertTrue(library.save(id: id, name: "Mac", addresses: ["mac.local", "100.100.20.30"]))
        XCTAssertTrue(removed.isEmpty)
        XCTAssertTrue(library.save(id: id, name: "Mac", addresses: ["100.100.20.30", "mac.local"]))
        XCTAssertTrue(removed.isEmpty)
        XCTAssertTrue(library.save(id: id, name: "Mac", addresses: ["100.100.20.30", "mac.local"], port: 5901))
        XCTAssertTrue(removed.isEmpty); XCTAssertEqual(DirectMacLibraryV1(url: url).macs, library.macs)
    }
    func testPreferencesAndCustomContentAreIsolatedByMacUUID() throws {
        let first = UUID(), second = UUID()
        defer { VNCSessionPreferences.clear(first); VNCSessionPreferences.clear(second) }
        VNCSessionPreferences.setSpeed(2.2, mac: first); VNCSessionPreferences.setDisplay(85, mac: first)
        VNCSessionPreferences.setTrackpad(true, mac: first)
        XCTAssertTrue(VNCSessionPreferences.followCursor(first))
        VNCSessionPreferences.setFollowCursor(false, mac: first)
        XCTAssertFalse(VNCSessionPreferences.followCursor(first)); XCTAssertTrue(VNCSessionPreferences.followCursor(second))
        XCTAssertEqual(VNCSessionPreferences.speed(second), 1.5); XCTAssertNil(VNCSessionPreferences.display(second))
        XCTAssertFalse(VNCSessionPreferences.trackpad(second))
        let action = VNCQuickAction(title: "Test", kind: .text, text: "Synthetic text")
        try VNCSessionPreferences.saveActions([action], mac: first)
        XCTAssertTrue(VNCSessionPreferences.actions(first).isEmpty); XCTAssertEqual(try VNCSessionPreferences.readActions(first), [action]); XCTAssertEqual(VNCSessionPreferences.actions(second).count, 3)
        XCTAssertFalse(VNCQuickAction(title: "Too long", kind: .text, text: String(repeating: "a", count: 257)).valid)
        XCTAssertThrowsError(try DirectMacRecordV1.normalized(name: "Mac", addresses: ["same.local", "same.local"]))
        XCTAssertThrowsError(try DirectMacRecordV1.normalized(name: "Mac", addresses: ["mac.local"], port: 0))
        VNCSessionPreferences.clear(first); XCTAssertTrue(VNCSessionPreferences.followCursor(first))
    }
    func testMultipleMacsPersistAndCredentialDeletionRequiresExplicitRemoval() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "macs.json")
        var removed: [UUID] = []
        let library = DirectMacLibraryV1(url: url, removeLogin: { removed.append($0) })
        XCTAssertTrue(library.save(id: nil, name: "First", address: " first.local "))
        XCTAssertTrue(library.save(id: nil, name: "Second", address: "second.local"))
        let first = try XCTUnwrap(library.macs.first)
        XCTAssertTrue(library.save(id: nil, name: "Shared Address", address: "FIRST.LOCAL"))
        XCTAssertEqual(library.macs.count, 3)
        XCTAssertTrue(library.save(id: first.id, name: "Renamed", address: first.address))
        XCTAssertTrue(removed.isEmpty)
        XCTAssertTrue(library.save(id: first.id, name: "Renamed", address: "changed.local"))
        XCTAssertTrue(removed.isEmpty)
        let reopened = DirectMacLibraryV1(url: url, removeLogin: { removed.append($0) })
        XCTAssertEqual(reopened.macs, library.macs)
        reopened.remove(reopened.macs[0])
        XCTAssertEqual(removed, [first.id])
        XCTAssertEqual(DirectMacLibraryV1(url: url).macs.count, 2)
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(contents.contains("password")); XCTAssertFalse(contents.contains("username"))
    }
    func testUnreadableLibraryCannotBeOverwrittenAndFailedDeletionPreservesRecord() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "macs.json"), damaged = Data("invalid".utf8)
        try damaged.write(to: url)
        let unreadable = DirectMacLibraryV1(url: url)
        XCTAssertFalse(unreadable.readable)
        XCTAssertFalse(unreadable.save(id: nil, name: "New", address: "new.local"))
        XCTAssertEqual(try Data(contentsOf: url), damaged)
        try FileManager.default.removeItem(at: url)
        let library = DirectMacLibraryV1(url: url, removeLogin: { _ in throw CocoaError(.fileWriteUnknown) })
        XCTAssertTrue(library.save(id: nil, name: "One", address: "one.local"))
        let first = try XCTUnwrap(library.macs.first), before = try Data(contentsOf: url)
        library.remove(first)
        XCTAssertEqual(library.macs, [first]); XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertNotNil(library.failure)
    }
}
