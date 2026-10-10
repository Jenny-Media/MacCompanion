import XCTest
import Crypto
import Citadel
import StoreKit
import StoreKitTest
import Security
import UIKit
@testable import Mac_Companion

@MainActor final class KeyLibraryAndProTests: XCTestCase {
    private let libraryID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(root["clientAdditions"] as? [String: Any])
    }
    func testNamedSharedKeysKeepPerMacUsernamesAndSurviveMacRemoval() throws {
        let key = TerminalSSHKey.create(), a = UUID(), b = UUID()
        let id = try TerminalKeyLibraryStore.add(key, name: "Shared Test Key")
        defer { try? TerminalSecretStore.remove(a); try? TerminalSecretStore.remove(b); try? TerminalKeyLibraryStore.delete(id) }
        XCTAssertEqual(try TerminalKeyLibraryStore.add(key, name: "Duplicate Import"), id)
        try TerminalKeyLibraryStore.associate(id, macID: a, username: "alice")
        try TerminalKeyLibraryStore.associate(id, macID: b, username: "bob")
        try TerminalKeyLibraryStore.rename(id, name: "Renamed Test Key")
        XCTAssertEqual(try TerminalKeyLibraryStore.selected(a)?.key.username, "alice")
        XCTAssertEqual(try TerminalKeyLibraryStore.selected(b)?.key.username, "bob")
        XCTAssertEqual(try TerminalKeyLibraryStore.selected(b)?.name, "Renamed Test Key")
        try TerminalSecretStore.remove(a)
        XCTAssertNil(try TerminalKeyLibraryStore.selected(a))
        XCTAssertEqual(try TerminalKeyLibraryStore.selected(b)?.key.seed, key.seed)
        try TerminalKeyLibraryStore.delete(id)
        XCTAssertNil(try TerminalKeyLibraryStore.selected(b))
    }
    func testLegacyMigrationIsDurableIdempotentAndCorruptDataIsPreserved() throws {
        let id = UUID(), corrupt = UUID(), key = TerminalSSHKey.create()
        var legacy = key; legacy.username = "legacy-user"
        defer { try? TerminalSecretStore.remove(id); try? TerminalSecretStore.removeLegacyKey(corrupt); try? TerminalKeyLibraryStore.delete(id) }
        try TerminalSecretStore.write(JSONEncoder().encode(legacy), id: id, kind: "private-key")
        try TerminalKeyLibraryStore.migrate(id, name: "Legacy")
        try TerminalKeyLibraryStore.migrate(id, name: "Should Not Rename")
        XCTAssertEqual(try TerminalKeyLibraryStore.selected(id)?.key.seed, key.seed)
        XCTAssertEqual(try TerminalKeyLibraryStore.selected(id)?.key.username, "legacy-user")
        XCTAssertNil(try TerminalSecretStore.read(id, kind: "private-key"))
        XCTAssertEqual(try TerminalKeyLibraryStore.load().keys.filter { $0.id == id }.count, 1)
        try TerminalSecretStore.write(Data("corrupt-synthetic".utf8), id: corrupt, kind: "private-key")
        XCTAssertThrowsError(try TerminalKeyLibraryStore.migrate(corrupt))
        XCTAssertEqual(try TerminalSecretStore.read(corrupt, kind: "private-key"), Data("corrupt-synthetic".utf8))
        let original = try XCTUnwrap(TerminalSecretStore.read(libraryID, kind: "key-library-v2"))
        defer { try? TerminalSecretStore.write(original, id: libraryID, kind: "key-library-v2") }
        try TerminalSecretStore.write(Data("corrupt-library".utf8), id: libraryID, kind: "key-library-v2")
        XCTAssertThrowsError(try TerminalKeyLibraryStore.add(.create(), name: "Must Not Overwrite"))
        XCTAssertEqual(try TerminalSecretStore.read(libraryID, kind: "key-library-v2"), Data("corrupt-library".utf8))
    }
    func testEncryptedExportRoundTripAndExternalOpenSSHArtifacts() async throws {
        let key = TerminalSSHKey.create(), folder = URL.documentsDirectory.appending(path: "synthetic-key-interop")
        let exported = try await Task.detached {
            let parsed = try Curve25519.Signing.PrivateKey(rawRepresentation: key.seed)
            let a = try parsed.makeEncryptedSSHRepresentation(passphrase: "synthetic-export-only", comment: "Synthetic QA")
            let b = try parsed.makeEncryptedSSHRepresentation(passphrase: "synthetic-export-only", comment: "Synthetic QA")
            XCTAssertNotEqual(a, b)
            XCTAssertEqual(try TerminalSSHKey.importOpenSSH(a, passphrase: "synthetic-export-only").seed, key.seed)
            XCTAssertThrowsError(try TerminalSSHKey.importOpenSSH(a, passphrase: "wrong"))
            XCTAssertThrowsError(try parsed.makeEncryptedSSHRepresentation(passphrase: ""))
            let fullBlock = try parsed.makeEncryptedSSHRepresentation(passphrase: "synthetic-export-only", comment: "Synthetic QAA")
            XCTAssertEqual(try TerminalSSHKey.importOpenSSH(fullBlock, passphrase: "synthetic-export-only").seed, key.seed)
            var payload = try XCTUnwrap(Data(base64Encoded: a.split(separator: "\n").dropFirst().dropLast().joined()))
            payload[payload.count - 1] ^= 1 // AES-CTR flips only the last padding byte.
            let invalidPadding = ("-----BEGIN OPENSSH " + "PRIVATE KEY-----\n") + payload.base64EncodedString() + "\n" + ("-----END OPENSSH " + "PRIVATE KEY-----\n")
            XCTAssertThrowsError(try TerminalSSHKey.importOpenSSH(invalidPadding, passphrase: "synthetic-export-only"))
            return a
        }.value
        // Only fresh synthetic artifacts, removed by the host verification script.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(exported.utf8).write(to: folder.appending(path: "encrypted-key"), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: folder.appending(path: "encrypted-key").path)
        try Data(key.publicKey.utf8).write(to: folder.appending(path: "expected-public"))
        let entry = TerminalNamedKey(id: UUID(), name: "Synthetic Install", key: key)
        try Data(TerminalKeyInstallation.command(for: entry).utf8).write(to: folder.appending(path: "installation-command"))
    }
    func testIndexedTerminalKeysOneShotLockAndProtectedSettings() throws {
        let policy = try XCTUnwrap(fixture()["terminalKeyboard"] as? [String: Any])
        for value in try XCTUnwrap(policy["cases"] as? [[String: Any]]) {
            var mods: TerminalModifiers = []
            if value["ctrl"] as? Bool == true { mods.insert(.ctrl) }; if value["alt"] as? Bool == true { mods.insert(.alt) }
            if value["shift"] as? Bool == true { mods.insert(.shift) }
            let bytes = TerminalKeyboardState.text(try XCTUnwrap(value["text"] as? String), modifiers: mods)
            XCTAssertEqual(bytes.map { String(format: "%02x", $0) }.joined(), value["expectedHex"] as? String)
        }
        for value in try XCTUnwrap(policy["backspaceCases"] as? [[String: Any]]) {
            var mods: TerminalModifiers = []
            if value["ctrl"] as? Bool == true { mods.insert(.ctrl) }; if value["alt"] as? Bool == true { mods.insert(.alt) }
            XCTAssertEqual(TerminalKeyboardState.backspace(modifiers: mods).map { String(format: "%02x", $0) }.joined(), value["expectedHex"] as? String)
        }
        var state = TerminalKeyboardState(); state.toggle(.ctrl)
        XCTAssertEqual(state.consume(), .ctrl); XCTAssertTrue(state.active.isEmpty)
        state.toggle(.alt, lock: true); XCTAssertEqual(state.consume(), .alt); XCTAssertEqual(state.active, .alt)
        state.reset(); XCTAssertTrue(state.active.isEmpty)
        XCTAssertEqual(TerminalAccessoryKey.up.bytes(applicationCursor: true), Array("\u{1b}OA".utf8))
        XCTAssertEqual(TerminalAccessoryKey.left.bytes(modifiers: [.ctrl, .shift]), Array("\u{1b}[1;6D".utf8))
        let id = UUID(); defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "media.jenny.maccompanion.ssh-terminal-keyboard-v1.v1", kSecAttrAccount as String: id.uuidString.lowercased()] as CFDictionary) }
        let prefs = TerminalKeyboardPreferences(keys: [.f1, .home], snippets: [.init(name: "Synthetic", text: "echo synthetic")])
        try prefs.save(id); XCTAssertEqual(try TerminalKeyboardPreferences.load(id).snippets, prefs.snippets)
        XCTAssertThrowsError(try TerminalKeyboardPreferences(keys: [.f1, .f1]).save(id))
        XCTAssertEqual(try TerminalKeyboardPreferences.load(id).keys, prefs.keys)
        let terminal = SessionTerminalView(frame: .zero)
        let accessory = TerminalKeyboardBar(terminal: terminal, preferences: .init())
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let numbers = descendants(accessory).first { $0.accessibilityIdentifier == "terminal-number-row" } as? UIStackView
        XCTAssertEqual(numbers?.arrangedSubviews.compactMap { ($0 as? UIButton)?.configuration?.title }, ["1","2","3","4","5","6","7","8","9","0"])
        terminal.keyboardState.toggle(.ctrl); terminal.insertText("c"); XCTAssertTrue(terminal.keyboardState.active.isEmpty)
        terminal.keyboardState.toggle(.alt); terminal.deleteBackward(); XCTAssertTrue(terminal.keyboardState.active.isEmpty)
        terminal.insertText("a"); terminal.keyboardState.toggle(.shift); terminal.deleteBackward(); XCTAssertFalse(terminal.hasText)
        terminal.keyboardState.toggle(.alt, lock: true); terminal.resetModifiers(); XCTAssertTrue(terminal.keyboardState.active.isEmpty)
    }
    func testIndexedProPolicyAndPermanentFreeSelection() throws {
        let policy = try XCTUnwrap(fixture()["lifetimePro"] as? [String: Any])
        for value in try XCTUnwrap(policy["cases"] as? [[String: Any]]) {
            let decision = DirectProEntitlement(verified: value["verified"] as? Bool == true, matchingProduct: value["matchingProduct"] as? Bool == true, nonConsumable: value["nonConsumable"] as? Bool == true, revoked: value["revoked"] as? Bool == true)
            XCTAssertEqual(decision.unlocked, value["unlocked"] as? Bool)
        }
        let suite = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite)), a = UUID(), b = UUID()
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = DirectProAccess(defaults: defaults)
        XCTAssertTrue(access.canAddMac(count: 0)); XCTAssertFalse(access.canAddMac(count: 1))
        XCTAssertTrue(access.canUseMac(a, among: [a,b])); XCTAssertFalse(access.canUseMac(b, among: [a,b]))
        access.chooseFreeMac(b); access.chooseFreeKey(b)
        XCTAssertTrue(DirectProAccess(defaults: defaults).canUseMac(b, among: [a,b]))
        XCTAssertTrue(access.canUseKey(b, among: [a,b])); XCTAssertFalse(access.canUseKey(a, among: [a,b]))
    }
    func testRealStoreKitPurchaseRestoreAndRefundWithoutDataDeletion() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url); store.disableDialogs = true; store.clearTransactions()
        defer { store.clearTransactions() }
        let access = DirectProAccess(); access.start(); await access.loadProduct()
        let product = try XCTUnwrap(access.product, access.message ?? "StoreKit configuration unavailable")
        XCTAssertEqual(product.type, .nonConsumable); XCTAssertEqual(product.price, Decimal(string: "9.99"))
        await access.refresh(); XCTAssertFalse(access.hasPro)
        await access.purchase(); XCTAssertTrue(access.hasPro, access.message ?? "Purchase not verified")
        let relaunched = DirectProAccess(); await relaunched.refresh(); XCTAssertTrue(relaunched.hasPro)
        await relaunched.restore(); XCTAssertTrue(relaunched.hasPro)
        let transaction = try XCTUnwrap(store.allTransactions().first)
        try store.refundTransaction(identifier: transaction.identifier)
        for _ in 0..<200 { if !access.hasPro { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(access.hasPro); await relaunched.refresh(); XCTAssertFalse(relaunched.hasPro)
    }

    func testIndexedTrialAdmissionAndExactExpiry() throws {
        let policy = try XCTUnwrap(fixture()["lifetimePro"] as? [String: Any])
        let trial = try XCTUnwrap(policy["trial"] as? [String: Any])
        XCTAssertEqual(trial["durationSeconds"] as? Double, DirectProTrial.duration)
        for value in try XCTUnwrap(trial["cases"] as? [[String: Any]]) {
            let entitlement = DirectProEntitlement(verified: value["verified"] as? Bool == true,
                matchingProduct: value["matchingProduct"] as? Bool == true,
                nonConsumable: value["nonConsumable"] as? Bool == true, revoked: value["revoked"] as? Bool == true)
            let start = Date(timeIntervalSince1970: try XCTUnwrap(value["originalPurchaseTimestamp"] as? Double))
            let now = Date(timeIntervalSince1970: try XCTUnwrap(value["nowTimestamp"] as? Double))
            XCTAssertEqual(DirectProTrial(entitlement: entitlement, originalPurchaseDate: start).active(at: now),
                           value["active"] as? Bool, value["name"] as? String ?? "")
        }
    }

    func testStoreKitTrialRestoreExpiryAndLifetimeUpgrade() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url); store.disableDialogs = true; store.clearTransactions()
        defer { store.clearTransactions() }
        var now = Date()
        let suite = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite)), a = UUID(), b = UUID()
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = DirectProAccess(defaults: defaults, now: { now }); await access.loadProduct()
        XCTAssertEqual(try XCTUnwrap(access.trialProduct).price, 0)
        XCTAssertTrue(access.canStartTrial); XCTAssertFalse(access.hasPro)
        await access.startTrial(); now = Date(); access.reevaluateTrial()
        XCTAssertTrue(access.trialIsActive, access.message ?? "Trial not verified")
        XCTAssertFalse(access.hasLifetimePro); XCTAssertTrue(access.canAddMac(count: 1)); XCTAssertFalse(access.canStartTrial)
        let end = try XCTUnwrap(access.trial).endDate
        let restored = DirectProAccess(defaults: defaults, now: { now }); await restored.restore()
        XCTAssertTrue(restored.trialIsActive); XCTAssertEqual(restored.trial?.endDate, end)
        await access.startTrial(); XCTAssertEqual(access.trial?.endDate, end)
        access.chooseFreeMac(b); access.chooseFreeKey(b)
        now = end; access.reevaluateTrial()
        XCTAssertFalse(access.hasPro); XCTAssertFalse(access.canAddMac(count: 1))
        XCTAssertTrue(access.canUseMac(b, among: [a,b])); XCTAssertTrue(access.canUseKey(b, among: [a,b]))
        XCTAssertFalse(access.canUseMac(a, among: [a,b]))
        let relaunched = DirectProAccess(defaults: defaults, now: { now }); await relaunched.loadProduct()
        XCTAssertFalse(relaunched.hasPro); XCTAssertFalse(relaunched.canStartTrial)
        XCTAssertEqual(relaunched.trial?.endDate, end)
        // A backwards clock change in this process cannot reopen an ended trial.
        now = end.addingTimeInterval(-60); access.reevaluateTrial(); XCTAssertFalse(access.hasPro)
        await relaunched.purchase(); XCTAssertTrue(relaunched.hasLifetimePro, relaunched.message ?? "Upgrade not verified")
        now = end.addingTimeInterval(86400); relaunched.reevaluateTrial(); XCTAssertTrue(relaunched.hasPro)
    }

    func testRevokedTrialCannotRestart() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url); store.disableDialogs = true; store.clearTransactions()
        defer { store.clearTransactions() }
        let access = DirectProAccess(); await access.loadProduct(); await access.startTrial()
        XCTAssertTrue(access.trialIsActive)
        let purchase = try XCTUnwrap(store.allTransactions().first)
        try store.refundTransaction(identifier: purchase.identifier)
        // Refund delivery is asynchronous. As in the lifetime refund test,
        // allow Transaction.updates to refresh access before checking revocation.
        for _ in 0..<200 {
            if !access.hasPro { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await access.refresh()
        XCTAssertFalse(access.hasPro); XCTAssertNotNil(access.trial); XCTAssertFalse(access.canStartTrial)
        await access.startTrial(); XCTAssertFalse(access.hasPro)
    }
}
