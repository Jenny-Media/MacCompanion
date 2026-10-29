import SwiftUI

/// Opt-in Simulator app. Uses the production file and Keychain stores inside
/// its own bundle/access group, with iCloud off and synthetic configuration.
@main @MainActor struct LocalBackupApplication: App {
    let library: DirectMacLibraryV1
    let observation: String
    init() {
        let env = ProcessInfo.processInfo.environment
        let role = env["MC_BACKUP_E2E_ROLE"] ?? "A"
        observation = env["MC_BACKUP_E2E_OBSERVATION"] ?? "current"
        precondition(["A", "B"].contains(role))
        library = DirectMacLibraryV1()
        DirectCloudSyncV1.shared.setEnabled(false)
        do {
            try FileManager.default.createDirectory(at: .documentsDirectory, withIntermediateDirectories: true)
            if !UserDefaults.standard.bool(forKey: "backup-e2e-seeded") {
                let name = role == "A" ? "E2E Source Mac" : "E2E Target Mac"
                precondition(library.save(id: nil, name: name,
                    addresses: [role == "A" ? "source.synthetic.invalid" : "target.synthetic.invalid", role == "A" ? "192.0.2.10" : "192.0.2.20"],
                    port: role == "A" ? 5901 : 5902, sshPort: role == "A" ? 2222 : 2223))
                let id = library.macs[0].id
                VNCSessionPreferences.setSpeed(role == "A" ? 2.0 : 1.25, mac: id)
                VNCSessionPreferences.setDesktopSize(role == "A" ? 2 : 1, mac: id)
                VNCSessionPreferences.setFollowCursor(role == "B", mac: id)
                VNCSessionPreferences.setTrackpad(role == "A", mac: id)
                try TerminalSecretStore.save(.init(username: "synthetic-user", password: "E2E-DEVICE-LOCAL-PASSWORD-" + role), id: id)
                try DesktopCredentialStoreV1.save(.init(username: "synthetic-user", password: "E2E-DEVICE-LOCAL-DESKTOP-" + role), hostID: id)
                for store in [TerminalControlsStore(), .remoteMac()] {
                    var profile = try store.load()
                    profile.freezeKeyboardLayout()
                    var rows = profile.resolvedRows
                    rows[0].alignment = role == "A" ? .right : .left
                    rows[0].scrollStart = role == "A" ? .right : .left
                    profile.keyboardRows = rows
                    let saved = TerminalControlAction(title: "E2E " + role + " Text", kind: .text,
                        text: "Synthetic notes from device " + role + ".\nSecond line: Kyoto weekend.", inMenu: true)
                    var shortcut = TerminalControlAction(title: "E2E " + role + " Shortcut", kind: .shortcut, inMenu: true)
                    shortcut.character = 0x73; shortcut.modifiers = [0xffe3]
                    profile.actions += [saved, shortcut]
                    let row = profile.addRow(title: "E2E " + role + " Row")!
                    profile.place(saved.id, in: row); profile.place(shortcut.id, in: row)
                    profile.menuPlacements = profile.resolvedMenuPlacements.filter { $0.actionID != saved.id && $0.actionID != shortcut.id }
                        + [.init(actionID: saved.id), .init(actionID: shortcut.id)]
                    _ = try store.save(profile)
                }
                try Data("Synthetic Files fixture.\n".utf8).write(to: URL.documentsDirectory.appending(path: "fixture-marker.txt"))
                UserDefaults.standard.set(true, forKey: "backup-e2e-seeded")
            }
            if env["MC_BACKUP_E2E_EDIT"] == "return-from-B" {
                let mac = library.macs[0]
                precondition(library.save(id: mac.id, name: "E2E Edited On B", addresses: mac.addresses,
                    port: mac.port, sshPort: 3333, requiresExisting: true))
                VNCSessionPreferences.setSpeed(1.5, mac: mac.id)
                for store in [TerminalControlsStore(), .remoteMac()] {
                    var profile = try store.load()
                    let action = TerminalControlAction(title: "E2E Return Text", kind: .text,
                        text: "Synthetic edit made on device B after restoring A.", inMenu: true)
                    profile.actions.append(action); profile.place(action.id, in: profile.resolvedRows[0].id)
                    profile.menuPlacements = profile.resolvedMenuPlacements.filter { $0.actionID != action.id } + [.init(actionID: action.id)]
                    _ = try store.save(profile)
                }
            }
            try Self.observe(library, name: observation)
        } catch { fatalError("Synthetic backup fixture failed: \(error)") }
    }
    private static func observe(_ library: DirectMacLibraryV1, name: String) throws {
        library.reload()
        let store = DirectLocalBackupStore(library: library)
        let backup = try store.makeBackup().encoded()
        try backup.write(to: URL.documentsDirectory.appending(path: "observation-" + name + ".json"), options: .atomic)
        let records: [[String: Any]] = try library.macs.map { mac in
            ["id": mac.id.uuidString, "name": mac.name,
             "sshLoginPresent": try TerminalSecretStore.login(mac.id) != nil,
             "desktopLoginPresent": try DesktopCredentialStoreV1.readChecked(mac.id) != nil]
        }
        let details: [String: Any] = ["macs": records, "syncEnabled": DirectCloudSyncV1.shared.enabled,
                                     "hasRecoveryCopy": store.hasRecoveryCopy]
        try JSONSerialization.data(withJSONObject: details, options: [.sortedKeys]).write(
            to: URL.documentsDirectory.appending(path: "details-" + name + ".json"), options: .atomic)
    }
    var body: some Scene {
        WindowGroup {
            NavigationStack { DirectLocalBackupSettings(library: library) }.directAppearance()
                .onReceive(NotificationCenter.default.publisher(for: DirectLocalBackupStore.changed)) { _ in
                    Task { @MainActor in
                        await Task.yield() // The restore transaction must finish before exporting an observation.
                        do { try Self.observe(library, name: observation + "-changed") }
                        catch { assertionFailure("Synthetic observation failed: \(error)") }
                    }
                }
        }
    }
}
