import XCTest
import Security
import StoreKitTest
import SwiftUI
@testable import Mac_Companion

@MainActor final class DirectMacLibraryTests: XCTestCase {
    func testSessionSelectionKeepsTappedModeWhileLibraryChanges() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "macs.json")
        let library = DirectMacLibraryV1(url: url)
        let id = UUID()
        for mode in DirectMacConnection.allCases {
            XCTAssertTrue(library.save(id: id, name: "Synthetic Tap", addresses: ["tap-mode-qa.invalid"], preferredConnection: mode))
            let reopened = DirectMacLibraryV1(url: url)
            let tapped = try XCTUnwrap(reopened.macs.first)
            let selection = DirectMacSessionSelection(mac: tapped, connection: tapped.preferredConnection)
            XCTAssertEqual(selection.connection, mode)
            XCTAssertEqual(selection.mac.preferredConnection, mode)
            var cloudMac = tapped
            cloudMac.preferredConnection = mode == .desktop ? .trackpad : .desktop
            try reopened.applyCloud([cloudMac])
            XCTAssertEqual(reopened.macs.first?.preferredConnection, cloudMac.preferredConnection)
            XCTAssertEqual(selection.connection, mode, "An already selected mode must not drift with a later library update")
            XCTAssertEqual(selection.mac, tapped)
            XCTAssertNotEqual(selection.id, DirectMacSessionSelection(mac: tapped, connection: mode).id,
                              "Reopening the same Mac creates a fresh presentation")
        }
    }

    func testIndexedConnectionActionsUseDistinctSupportedSymbols() throws {
        let cases = try XCTUnwrap(profile()["connectionActionCases"] as? [[String: String]])
        for vector in cases {
            let mode = try XCTUnwrap(DirectMacConnection(rawValue: try XCTUnwrap(vector["mode"])))
            XCTAssertEqual(mode.actionTitle, vector["title"])
            XCTAssertEqual(mode.symbol, vector["symbol"])
            XCTAssertNotNil(UIImage(systemName: mode.symbol))
        }
        XCTAssertNotEqual(DirectMacConnection.desktop.symbol, DirectMacFamily.unknown.symbol)
    }
    func testManualOrderPersistsThroughReloadRenameDiscoveryAndCloudMerge() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "macs.json")
        var removed: [UUID] = []
        let library = DirectMacLibraryV1(url: url, removeLogin: { removed.append($0) })
        let ids = (0..<3).map { _ in UUID() }
        for (index, name) in ["Alpha", "Bravo", "Charlie"].enumerated() {
            XCTAssertTrue(library.save(id: ids[index], name: name, address: "synthetic\(index).local"))
        }
        let scope = "mac-order-free-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: scope))
        defer { defaults.removePersistentDomain(forName: scope) }
        let access = DirectProAccess(defaults: defaults)
        access.chooseFreeMac(ids[0])
        XCTAssertTrue(library.move(fromOffsets: [2], toOffset: 0))
        XCTAssertEqual(library.macs.map(\.id), [ids[2], ids[0], ids[1]])
        XCTAssertTrue(access.canUseMac(ids[0], among: library.macs.map(\.id)))
        XCTAssertFalse(access.canUseMac(ids[2], among: library.macs.map(\.id)))
        XCTAssertEqual(DirectMacLibraryV1(url: url).macs, library.macs)
        XCTAssertTrue(library.save(id: ids[0], name: "Zulu", address: "synthetic0.local"))
        library.updateDetectedMetadata([.init(name: "Detected", host: "synthetic2.local", addresses: ["synthetic2.local"], port: 5900, connection: .desktop, modelIdentifier: "MacBookPro18,1")])
        let extra = try DirectMacRecordV1.normalized(name: "New", address: "new.local")
        var updated = library.macs[0]; updated.name = "Cloud Rename"
        try library.applyCloud([library.macs[2], extra, updated, library.macs[1]])
        XCTAssertEqual(library.macs.map(\.id), [ids[2], ids[0], ids[1], extra.id])
        XCTAssertEqual(library.macs.first?.name, "Cloud Rename")
        XCTAssertEqual(DirectMacLibraryV1(url: url).macs, library.macs)
        XCTAssertTrue(removed.isEmpty, "Reordering and metadata merges must not touch credentials")
        XCTAssertFalse(library.move(fromOffsets: [99], toOffset: 0))
        XCTAssertFalse(library.move(fromOffsets: [0], toOffset: 99))
    }
    func testLegacyOrderMigratesToAlphabeticalAndFailedMoveKeepsOriginalFile() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "macs.json")
        let bravo = try DirectMacRecordV1.normalized(name: "Bravo", address: "bravo.local")
        let alpha = try DirectMacRecordV1.normalized(name: "Alpha", address: "alpha.local")
        struct Legacy: Encodable { let version = 4; let macs: [DirectMacRecordV1] }
        try JSONEncoder().encode(Legacy(macs: [bravo, alpha])).write(to: url)
        let library = DirectMacLibraryV1(url: url)
        XCTAssertEqual(library.macs.map(\.id), [alpha.id, bravo.id])
        XCTAssertTrue(library.move(fromOffsets: [0], toOffset: 2))
        XCTAssertEqual(DirectMacLibraryV1(url: url).macs.map(\.id), [bravo.id, alpha.id])
        let data = try Data(contentsOf: url)
        let policy = try XCTUnwrap(profile()["macLibraryPolicy"] as? [String: Any])
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(envelope["version"] as? Int, policy["fileVersion"] as? Int)
        let before = library.macs
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        XCTAssertFalse(library.move(fromOffsets: [0], toOffset: 2))
        XCTAssertEqual(library.macs, before); XCTAssertNotNil(library.recovery)
    }
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
    func testModeProfilesKeepLegacyActionsUntilSavedAndRemainIndependent() throws {
        let policy = try XCTUnwrap(profile()["interfacePolicy"] as? [String: Any])
        XCTAssertEqual(policy["quickActionProfileScope"] as? String, "mode")
        XCTAssertEqual(policy["quickActionConfigurationRequiresConnection"] as? Bool, false)
        XCTAssertEqual(DirectControlMode.allCases.map(\.rawValue), policy["quickActionProfiles"] as? [String])
        XCTAssertEqual(DirectControlMode.terminal.defaults.map { $0.kind.rawValue }, policy["terminalDefaultQuickActionKinds"] as? [String])
        XCTAssertEqual(DirectControlMode.trackpad.defaults.map { $0.kind.rawValue }, policy["trackpadDefaultQuickActionKinds"] as? [String])
        let mac = UUID()
        let desktopID = DirectControlMode.desktop.profileID, terminalID = DirectControlMode.terminal.profileID, trackpadID = DirectControlMode.trackpad.profileID
        for id in [desktopID, terminalID, trackpadID] { VNCSessionPreferences.clear(id) }
        defer { for id in [mac, desktopID, terminalID, trackpadID] { VNCSessionPreferences.clear(id) } }
        let legacy = VNCQuickAction(title: "Legacy Shortcut", kind: .shortcut, key: 0x63, modifiers: [0xffeb])
        try VNCSessionPreferences.saveActions([legacy], mac: mac)
        XCTAssertEqual(try VNCSessionPreferences.profileActions(.desktop, legacyMac: mac), [legacy])
        XCTAssertEqual(try VNCSessionPreferences.profileActions(.terminal).map(\.kind), [.paste, .interrupt])
        XCTAssertEqual(try VNCSessionPreferences.profileActions(.trackpad, legacyMac: mac).map(\.kind), [.rightClick, .returnKey])
        let shared = VNCQuickAction(title: "Fit", kind: .fit)
        try VNCSessionPreferences.saveProfile([shared], mode: .desktop)
        XCTAssertEqual(try VNCSessionPreferences.profileActions(.desktop, legacyMac: mac), [shared])
        XCTAssertEqual(try VNCSessionPreferences.readActions(mac), [legacy], "Do not delete the legacy record")
        XCTAssertEqual(try VNCSessionPreferences.profileActions(.terminal).map(\.kind), [.paste, .interrupt])
        try VNCSessionPreferences.saveProfile([], mode: .terminal)
        XCTAssertTrue(try VNCSessionPreferences.profileActions(.terminal).isEmpty, "An intentionally empty profile must not restore defaults")
    }
    func testQuickActionsRejectIncompatibleKeysAndProtectUnreadableProfiles() throws {
        let mode = DirectControlMode.terminal, id = mode.profileID
        VNCSessionPreferences.clear(id); defer { VNCSessionPreferences.clear(id) }
        XCTAssertThrowsError(try VNCSessionPreferences.saveProfile([.init(title: "Fit", kind: .fit)], mode: mode))
        XCTAssertThrowsError(try VNCSessionPreferences.saveProfile([.init(title: "Command", kind: .shortcut, key: 0x63, modifiers: [0xffeb])], mode: mode))
        XCTAssertThrowsError(try VNCSessionPreferences.saveProfile([.init(title: "Unsafe text", kind: .text, text: "\u{1b}[A")], mode: mode))
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "media.jenny.maccompanion.direct-actions.v1", kSecAttrAccount as String: id.uuidString.lowercased(), kSecAttrSynchronizable as String: false, kSecValueData as String: Data("unreadable".utf8)]
        XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)
        XCTAssertThrowsError(try VNCSessionPreferences.saveProfile(mode.defaults, mode: mode))
        XCTAssertThrowsError(try VNCSessionPreferences.profileActions(mode))
    }
    func testTerminalQuickShortcutsUseShellEncodingAndNoRemoteCommandModifier() {
        XCTAssertEqual(VNCQuickAction(title: "Interrupt", kind: .shortcut, key: 0x63, modifiers: [0xffe3]).terminalBytes(), [3])
        XCTAssertEqual(VNCQuickAction(title: "Alt Left", kind: .shortcut, key: 0xff51, modifiers: [0xffe9]).terminalBytes(), Array("\u{1b}[1;3D".utf8))
        XCTAssertEqual(VNCQuickAction(title: "Up", kind: .shortcut, key: 0xff52).terminalBytes(applicationCursor: true), Array("\u{1b}OA".utf8))
        XCTAssertTrue(VNCQuickAction(title: "Command", kind: .shortcut, key: 0x63, modifiers: [0xffeb]).terminalBytes().isEmpty)
    }
    func testAllModeControlsCanBeConfiguredWithoutAConnectedMac() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url); store.disableDialogs = true; store.clearTransactions()
        defer { store.clearTransactions() }
        let access = DirectProAccess.shared
        await access.refresh()
        for pro in [false, true] {
            if pro {
                _ = try await store.buyProduct(identifier: DirectProAccess.productID)
                await access.refresh()
                for _ in 0..<100 where !access.hasPro { try await Task.sleep(for: .milliseconds(10)) }
                XCTAssertTrue(access.hasPro, "Synthetic StoreKit entitlement must be verified")
            }
            for mode in DirectControlMode.allCases {
                let host = UIHostingController(rootView: VNCInputSettings(mode: mode).directAppearance())
                window.rootViewController = host; window.makeKeyAndVisible(); window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(200))
                XCTAssertNotNil(host.view.window)
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let attachment = XCTAttachment(image: image); attachment.name = mode.rawValue + (pro ? "-pro" : "-free") + "-offline-controls"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
        store.clearTransactions(); await access.refresh()
        for _ in 0..<100 where access.hasPro { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(access.hasPro)
    }
    func testStoppedDesktopViewerDoesNotReceiveControlProfileUpdates() throws {
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["studio.local"])
        let viewer = CompanionVNCViewer()
        let coordinator = VNCRemoteDesktopView.Coordinator(mac: mac)
        coordinator.viewer = viewer; coordinator.observeActivity()
        defer { coordinator.stopObserving(); coordinator.activity.finish() }
        viewer.quickActions = [["title": "Sentinel"]]
        NotificationCenter.default.post(name: VNCSessionPreferences.actionsChanged, object: DirectControlMode.desktop)
        XCTAssertNotEqual(viewer.quickActions.first?["title"] as? String, "Sentinel")
        coordinator.stopObserving()
        viewer.quickActions = [["title": "Sentinel"]]
        NotificationCenter.default.post(name: VNCSessionPreferences.actionsChanged, object: DirectControlMode.desktop)
        XCTAssertEqual(viewer.quickActions.first?["title"] as? String, "Sentinel")
    }
    func testAuditedAppSymbolsExistOnSupportedRuntime() throws {
        guard let path = ProcessInfo.processInfo.environment["MACCOMPANION_ICON_AUDIT_PATH"] else { throw XCTSkip("Opt-in source inventory audit") }
        let symbols = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        for name in symbols.keys { XCTAssertNotNil(UIImage(systemName: name), "Missing SF Symbol: " + name) }
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
