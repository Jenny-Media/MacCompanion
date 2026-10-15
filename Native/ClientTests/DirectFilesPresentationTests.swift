import XCTest
import SwiftUI
import Observation
import NIO
#if os(iOS)
import UIKit
@testable import Mac_Companion
#else
import AppKit
@testable import MacCompanion
#endif

@MainActor @Observable private final class FilesPresentationAdmission {
    var allowed = true
    var active = true
}

@MainActor final class DirectFilesPresentationTests: XCTestCase {
    func testRemovedMacRetainsDownloadsUntilSaveOrDiscardAndThenClosesPresentation() async throws {
        #if os(iOS)
        let origins = ["files", "terminal", "desktop", "trackpad"]
        #else
        let origins = ["files"]
        #endif
        for origin in origins {
            for save in [false, true] {
                let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
                let url = root.appendingPathComponent("library.json")
                let library = DirectMacLibraryV1(url: url, removeLogin: { _ in })
                let probe = FilesDirectoryTestProbe(), bytes = Data([1, 2, 3])
                let server = try await filesDirectoryTestServer(probe: probe, downloadBytes: bytes)
                defer { Task { await probe.shutdown(); try? await server.close() } }
                let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Download Recovery", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
                XCTAssertTrue(library.save(id: mac.id, name: mac.name, addresses: mac.addresses, sshPort: mac.sshPort))
                let owner = DirectFilesSession(mac: mac, libraryURL: url)
                defer { owner.close(); try? TerminalSecretStore.remove(mac.id) }
                var dismissals = 0
                let exit: @MainActor () -> Void = { dismissals += 1 }
                var view = AnyView(DirectFilesView(mac: mac, session: owner, retainWhenDismissed: true, closeOwnerWindow: exit))
                #if os(iOS)
                if origin == "terminal" { view = AnyView(DirectTerminalView(mac: mac, macLibrary: library, files: owner, autoConnect: false, exit: exit)) }
                if origin == "desktop" || origin == "trackpad" { view = AnyView(DirectDesktopSessionView(mac: mac, inputOnly: origin == "trackpad", files: owner, showMacs: exit)) }
                #endif
                let presentation = try FilesMountedPresentation(view.directAppearance()); defer { presentation.close() }
                owner.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: false)
                try await presentation.wait { owner.trust != nil || owner.phase == .interrupted }
                owner.answerTrust(true)
                try await presentation.wait { owner.phase == .ready || owner.phase == .interrupted }
                XCTAssertEqual(owner.phase, .ready)
                owner.download(.init(name: "pending.txt", kind: .file, size: UInt64(bytes.count)))
                try await presentation.wait { !owner.busy }
                let item = try XCTUnwrap(owner.results.first), download = try XCTUnwrap(item.localDownload)
                // Sync can remove a Mac while its retained Files sheet is hidden.
                try library.applyCloud([])
                try await Task.sleep(for: .milliseconds(200)); presentation.layout()
                XCTAssertTrue(owner.macRemoved); XCTAssertFalse(owner.isClosed)
                XCTAssertEqual(dismissals, 0, origin)
                XCTAssertEqual(try Data(contentsOf: download), bytes)
                XCTAssertEqual(owner.loginDraft.password, "")
                if save {
                    let exported = root.appendingPathComponent("exported.txt")
                    try FileManager.default.copyItem(at: download, to: exported)
                    owner.markSaved(item.id) // Native chooser reports successful export.
                    try await presentation.wait { dismissals > 0 }
                    owner.close()
                    XCTAssertEqual(try Data(contentsOf: exported), bytes)
                } else {
                    owner.discardResults()
                    try await presentation.wait { dismissals > 0 }
                }
                XCTAssertFalse(FileManager.default.fileExists(atPath: download.path))
            }
        }
    }
    #if os(macOS)
    func testCredentialWriteFailurePreservesOnlyAnAlreadySavedPasswordAcrossPresentation() async throws {
        for hidden in [false, true] {
            for edited in [false, true] {
                let probe = FilesDirectoryTestProbe()
                let server = try await filesDirectoryTestServer(probe: probe)
                defer { Task { await probe.shutdown(); try? await server.close() } }
                let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Retention Failure", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
                let savedPassword = edited ? "synthetic-old-password" : "synthetic-only"
                try TerminalSecretStore.save(.init(username: "synthetic", password: savedPassword), id: mac.id)
                var writes = 0
                let session = DirectFilesSession(mac: mac, saveLogin: { _, _ in writes += 1; throw TerminalSecretStore.Failure.storage })
                defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
                func view() -> DirectFilesView {
                    var view = DirectFilesView(mac: mac, session: session, retainWhenDismissed: true)
                    view.sessionAvailable = { true }
                    return view
                }
                let presentation = try FilesMountedPresentation(view()); defer { presentation.close() }
                try await presentation.wait { presentation.values().1 == savedPassword }
                if edited { try presentation.edit("synthetic", "synthetic-only") }
                session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: true)
                try await presentation.wait { session.trust != nil || session.phase == .interrupted }
                XCTAssertNotNil(session.trust)
                if hidden { presentation.hide(); try await presentation.wait { session.loginDraft.isSuspended } }
                session.answerTrust(true)
                try await presentation.wait { session.phase == .ready || session.phase == .interrupted }
                XCTAssertEqual(session.phase, .ready, session.message ?? "")
                XCTAssertEqual(writes, 1)
                XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.password, savedPassword)
                XCTAssertEqual(session.loginDraft.password, "")
                if hidden { presentation.mount(view()); try await presentation.wait { !session.loginDraft.isSuspended } }
                session.disconnect()
                try await presentation.wait { presentation.values().0 != nil }
                XCTAssertEqual(presentation.values().1, edited ? "" : savedPassword,
                               "Failed saving must neither forget an already saved password nor resurrect an older password after an edit")
                XCTAssertTrue(session.loginDraft.remember)
                XCTAssertEqual(session.phase, .interrupted, "No automatic reconnect")
            }
        }
    }
    #endif
    #if os(macOS)
    func testRemovalClosesAllMatchingOwnersAndCancelsPendingAuthentication() async throws {
        for synced in [false, true] {
            let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appendingPathComponent("library.json")
            let library = DirectMacLibraryV1(url: url, removeLogin: { _ in })
            let probe = FilesDirectoryTestProbe()
            let server = try await filesDirectoryTestServer(probe: probe)
            defer { Task { await probe.shutdown(); try? await server.close() } }
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Removed Owners", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
            XCTAssertTrue(library.save(id: mac.id, name: mac.name, addresses: mac.addresses, sshPort: mac.sshPort))
            var writes = 0, dismissals = 0
            let first = DirectFilesSession(mac: mac, libraryURL: url, saveLogin: { _, _ in writes += 1 })
            let second = DirectFilesSession(mac: mac, libraryURL: url)
            let other = DirectFilesSession(mac: .init(id: UUID(), name: "Synthetic Other Mac", addresses: ["fixture.local"]), libraryURL: url)
            let otherLibrary = DirectFilesSession(mac: mac, libraryURL: root.appendingPathComponent("other.json"))
            let terminal = DirectTerminalSession(mac: mac, libraryURL: url)
            defer { first.close(); second.close(); other.close(); otherLibrary.close(); terminal.stop(); try? TerminalSecretStore.remove(mac.id) }
            #if os(macOS)
            let desktop = MacVNCSession(mac: mac, libraryURL: url); defer { desktop.close() }
            #endif
            let presentation = try FilesMountedPresentation(DirectFilesView(mac: mac, session: first, retainWhenDismissed: true, closeOwnerWindow: { dismissals += 1 }))
            defer { presentation.close() }
            try await presentation.wait { presentation.values().0 != nil }
            try presentation.edit("synthetic", "synthetic-only"); first.loginDraft.remember = true
            first.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: true)
            try await presentation.wait { first.trust != nil }
            if synced { try library.applyCloud([]) } else { library.remove(mac) }
            XCTAssertTrue(first.isClosed); XCTAssertTrue(second.isClosed)
            XCTAssertTrue(terminal.macRemoved); XCTAssertFalse(terminal.connecting)
            #if os(macOS)
            XCTAssertTrue(desktop.macRemoved)
            desktop.connect(username: "synthetic", password: "synthetic-only", remember: true)
            XCTAssertFalse(desktop.connecting)
            #endif
            XCTAssertFalse(other.macRemoved); XCTAssertFalse(otherLibrary.macRemoved)
            first.answerTrust(true)
            first.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: true)
            terminal.connect(username: "synthetic", password: "synthetic-only", remember: true)
            try await presentation.wait { dismissals > 0 }
            XCTAssertEqual(writes, 0, "A removed owner's authentication cannot recreate a saved login")
            XCTAssertFalse(terminal.connecting); XCTAssertEqual(first.loginDraft.password, "")
            XCTAssertNil(try TerminalSecretStore.login(mac.id))
        }
    }
    #endif
    #if os(macOS)
    func testRetainedFilesRemountPreservesAccountMethodAndSaveChoice() async throws {
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Retained Draft", addresses: ["127.0.0.1"])
        try TerminalSecretStore.save(.init(username: "synthetic", password: "synthetic-only"), id: mac.id)
        let keyID = try TerminalKeyLibraryStore.add(.create(), name: "Synthetic Retained Key")
        try TerminalKeyLibraryStore.associate(keyID, macID: mac.id, username: "synthetic-key")
        let admission = FilesPresentationAdmission()
        let session = DirectFilesSession(mac: mac, canAccess: { admission.allowed })
        defer { session.close(); try? TerminalSecretStore.remove(mac.id); try? TerminalKeyLibraryStore.delete(keyID) }
        func view() -> DirectFilesView {
            var view = DirectFilesView(mac: mac, session: session, retainWhenDismissed: true)
            view.accessAllowed = { admission.allowed }; view.sessionAvailable = { admission.active }
            return view
        }
        let presentation = try FilesMountedPresentation(view())
        defer { presentation.close() }
        try await presentation.wait { presentation.values().0 == "synthetic-key" }
        session.loginDraft.selectMethod(.password)
        try await presentation.wait { presentation.values().0 == "synthetic" }
        try presentation.edit("synthetic-edited-account", "synthetic-edited-password")
        session.loginDraft.remember = false
        for _ in 0..<2 {
            presentation.hide()
            try await presentation.wait { session.loginDraft.isSuspended }
            XCTAssertEqual(session.loginDraft.password, "", "Hiding clears the visible secret")
            presentation.mount(view())
            try await presentation.wait { !session.loginDraft.isSuspended && presentation.values().0 != nil }
            XCTAssertEqual(presentation.values().0, "synthetic-edited-account", "Reopening the retained owner must not initialize another draft")
            XCTAssertEqual(presentation.values().1, "")
            XCTAssertEqual(session.loginDraft.method, .password); XCTAssertFalse(session.loginDraft.remember)
            XCTAssertEqual(session.phase, .signIn, "Reopening never connects automatically")
        }
        session.loginDraft.selectMethod(.sshKey)
        try await presentation.wait { presentation.values().0 == "synthetic-key" }
        session.loginDraft.username = "synthetic-edited-key-account"
        presentation.hide(); try await presentation.wait { session.loginDraft.isSuspended }
        presentation.mount(view()); try await presentation.wait { !session.loginDraft.isSuspended && presentation.values().0 != nil }
        XCTAssertEqual(presentation.values().0, "synthetic-edited-key-account")
        XCTAssertEqual(session.loginDraft.method, .sshKey); XCTAssertFalse(session.loginDraft.remember)
        XCTAssertEqual(try TerminalKeyLibraryStore.selected(mac.id)?.key.username, "synthetic-key")
        XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.password, "synthetic-only", "Draft edits do not change stored credentials")
        session.close()
        NotificationCenter.default.post(name: DirectClientPlatformV1.didBecomeActive, object: nil)
        try await Task.sleep(for: .milliseconds(150)); presentation.layout()
        XCTAssertTrue(session.loginDraft.isSuspended)
        XCTAssertEqual(session.loginDraft.username, ""); XCTAssertEqual(session.loginDraft.password, "", "Late activation cannot reload a closed owner's login")
    }
    #endif
    #if os(macOS)
    func testHiddenPasswordAuthenticationRestoresItsSavedLoginAfterRemount() async throws {
        let probe = FilesDirectoryTestProbe()
        let server = try await filesDirectoryTestServer(probe: probe)
        defer { Task { await probe.shutdown(); try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Hidden Login", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        try TerminalSecretStore.save(.init(username: "synthetic", password: "synthetic-old-password"), id: mac.id)
        let admission = FilesPresentationAdmission()
        let session = DirectFilesSession(mac: mac, canAccess: { admission.allowed })
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        #if os(macOS)
        let file = MacSSHKeyFileReference(id: UUID(), name: "Synthetic Hidden File Key", bookmark: Data([1]), fingerprint: "SHA256:synthetic")
        #endif
        func view() -> DirectFilesView {
            var view = DirectFilesView(mac: mac, session: session, retainWhenDismissed: true)
            view.accessAllowed = { admission.allowed }; view.sessionAvailable = { admission.active }
            #if os(macOS)
            view.selectedKeyFile = { _ in (file, "synthetic-file-account") }
            #endif
            return view
        }
        let presentation = try FilesMountedPresentation(view()); defer { presentation.close() }
        try await presentation.wait { presentation.values().1 == "synthetic-old-password" }
        session.loginDraft.selectMethod(.password)
        try await presentation.wait { presentation.values().0 == "synthetic" }
        try presentation.edit("synthetic", "synthetic-only")
        session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: true)
        try await presentation.wait { session.trust != nil || session.phase == .interrupted }
        XCTAssertNotNil(session.trust)
        presentation.hide()
        try await presentation.wait { session.loginDraft.isSuspended }
        session.answerTrust(true)
        try await presentation.wait { session.phase == .ready || session.phase == .interrupted }
        XCTAssertEqual(session.phase, .ready, session.message ?? "")
        XCTAssertEqual(session.loginDraft.password, "", "A hidden authentication must not refill visible secrets")
        XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.password, "synthetic-only")
        presentation.mount(view())
        try await presentation.wait { !session.loginDraft.isSuspended }
        session.disconnect()
        try await presentation.wait { presentation.values().0 != nil }
        XCTAssertEqual(presentation.values().0, "synthetic")
        XCTAssertEqual(presentation.values().1, "synthetic-only", "The owner, rather than a mounted-view callback, records verified saving")
        XCTAssertEqual(session.loginDraft.method, .password, "Key display refresh after a connected remount must preserve Password choice")
        XCTAssertEqual(session.phase, .interrupted, "Restoration requires explicit reconnect")
    }
    #endif
    #if os(macOS)
    func testRetainedDiskKeyRemountPreservesPasswordChoiceAndEditedAccount() async throws {
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Retained File Key", addresses: ["127.0.0.1"])
        try TerminalSecretStore.save(.init(username: "synthetic", password: "synthetic-only"), id: mac.id)
        let file = MacSSHKeyFileReference(id: UUID(), name: "Synthetic File Key", bookmark: Data([1]), fingerprint: "SHA256:synthetic")
        let session = DirectFilesSession(mac: mac)
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        func view() -> DirectFilesView {
            var view = DirectFilesView(mac: mac, session: session, retainWhenDismissed: true)
            view.selectedKeyFile = { _ in (file, "synthetic-file-account") }
            return view
        }
        let presentation = try FilesMountedPresentation(view()); defer { presentation.close() }
        try await presentation.wait { presentation.values().0 == "synthetic-file-account" }
        session.loginDraft.selectMethod(.password)
        try await presentation.wait { presentation.values().0 == "synthetic" }
        try presentation.edit("synthetic-edited-account", "synthetic-edited-password")
        session.loginDraft.remember = false
        presentation.hide(); try await presentation.wait { session.loginDraft.isSuspended }
        presentation.mount(view()); try await presentation.wait { !session.loginDraft.isSuspended && presentation.values().0 != nil }
        XCTAssertEqual(presentation.values().0, "synthetic-edited-account")
        XCTAssertEqual(session.loginDraft.method, .password, "Recreating key display state is not a new key selection")
        XCTAssertFalse(session.loginDraft.remember); XCTAssertEqual(presentation.values().1, "")
    }
    func testFilesResumesOnWorkspaceWakeAndWaitsForUnlock() async throws {
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Workspace Wake", addresses: ["127.0.0.1"])
        try TerminalSecretStore.save(.init(username: "synthetic", password: "synthetic-only"), id: mac.id)
        let admission = FilesPresentationAdmission()
        let session = DirectFilesSession(mac: mac, canAccess: { admission.allowed })
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        var view = DirectFilesView(mac: mac, session: session, retainWhenDismissed: true)
        view.accessAllowed = { admission.allowed }; view.sessionAvailable = { admission.active }
        let presentation = try FilesMountedPresentation(view); defer { presentation.close() }
        try await presentation.wait { presentation.values().1 == "synthetic-only" }
        for wake in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NotificationCenter.default.post(name: DirectClientPlatformV1.didEnterBackground, object: nil)
            try await presentation.wait { session.loginDraft.isSuspended && presentation.values().1 == "" }
            // No application activation is sent in this journey.
            NSWorkspace.shared.notificationCenter.post(name: wake, object: nil)
            try await presentation.wait { !session.loginDraft.isSuspended }
            XCTAssertEqual(presentation.values().1, "synthetic-only")
            XCTAssertNotEqual(session.phase, .ready, "Wake never reconnects automatically")
        }
        admission.allowed = false
        try await presentation.wait { session.loginDraft.isSuspended && presentation.values().1 == "" }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(150)); presentation.layout()
        XCTAssertTrue(session.loginDraft.isSuspended); XCTAssertEqual(presentation.values().1, "")
        admission.allowed = true
        try await presentation.wait { presentation.values().1 == "synthetic-only" }
        XCTAssertFalse(session.loginDraft.isSuspended); XCTAssertEqual(session.phase, .interrupted)
    }
    func testKeyChooserRenamingPreservesEditedFilesAccount() async throws {
        if !DirectProAccess.shared.ready { await DirectProAccess.shared.refresh() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Key Rename", addresses: ["127.0.0.1"])
        let keyID = try TerminalKeyLibraryStore.add(.create(), name: "Synthetic Before Rename")
        try TerminalKeyLibraryStore.associate(keyID, macID: mac.id, username: "synthetic-stored-account")
        let session = DirectFilesSession(mac: mac)
        defer {
            session.close()
            try? TerminalSecretStore.remove(mac.id)
            try? TerminalKeyLibraryStore.delete(keyID)
        }
        let host = NSHostingView(rootView: DirectFilesView(mac: mac, session: session))
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.makeFirstResponder(nil); window.contentView = nil; window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func account() -> NSTextField? { descendants(host).compactMap { $0 as? MacCredentialFields.Fields }.first?.account }
        func element(_ identifier: String) -> NSObject? {
            var pending: [Any] = [host] + window.sheets.compactMap(\.contentView), visited = Set<ObjectIdentifier>()
            while let item = pending.popLast() {
                guard let object = item as? NSObject, visited.insert(ObjectIdentifier(object)).inserted else { continue }
                if object.responds(to: NSSelectorFromString("accessibilityIdentifier")), object.value(forKey: "accessibilityIdentifier") as? String == identifier { return object }
                if object.responds(to: NSSelectorFromString("accessibilityChildren")) { pending.append(contentsOf: object.value(forKey: "accessibilityChildren") as? [Any] ?? []) }
            }
            return nil
        }
        func press(_ identifier: String) throws {
            let button = try XCTUnwrap(element(identifier)), selector = NSSelectorFromString("accessibilityPerformPress")
            XCTAssertTrue(button.responds(to: selector)); _ = button.perform(selector)
        }
        func wait(_ predicate: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(10)
            while !predicate() {
                guard Date() < deadline else { throw DirectFilesFailure.timedOut }
                try await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded()
                window.sheets.forEach { $0.contentView?.layoutSubtreeIfNeeded() }
            }
        }
        try await wait { account()?.stringValue == "synthetic-stored-account" }
        let field = try XCTUnwrap(account()); field.stringValue = "synthetic-edited-account"
        try press("files-choose-key")
        try await wait { element("ssh-key-detail-" + keyID.uuidString) != nil }
        try press("ssh-key-detail-" + keyID.uuidString)
        try await wait { element("ssh-key-save-name") != nil }
        let sheet = try XCTUnwrap(window.sheets.first), content = try XCTUnwrap(sheet.contentView)
        let name = try XCTUnwrap(descendants(content).compactMap { $0 as? NSTextField }.first { $0.isEditable })
        XCTAssertTrue(sheet.makeFirstResponder(name))
        let editor = try XCTUnwrap(name.currentEditor() as? NSTextView)
        editor.insertText("Synthetic After Rename", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        sheet.makeFirstResponder(nil)
        try await Task.sleep(for: .milliseconds(150))
        try press("ssh-key-save-name")
        try await wait { (try? TerminalKeyLibraryStore.selected(mac.id)?.name) == "Synthetic After Rename" }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(field.stringValue, "synthetic-edited-account", "Renaming does not select a different key or replace the edited account")
        XCTAssertEqual(try TerminalKeyLibraryStore.selected(mac.id)?.key.username, "synthetic-stored-account", "Editing the Files draft must not rewrite saved account settings")
    }
    func testCancelConnectionButtonPreservesSavedAndEditedPasswordDrafts() async throws {
        if !DirectProAccess.shared.ready { await DirectProAccess.shared.refresh() }
        // An owned socket accepts TCP but never begins SSH. The Cancel button
        // remains available without authenticating against a real machine.
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { $0.eventLoop.makeSucceededFuture(()) }.bind(host: "127.0.0.1", port: 0).get()
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Cancel Login", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        try TerminalSecretStore.save(.init(username: "synthetic-saved-account", password: "synthetic-saved-password"), id: mac.id)
        let session = DirectFilesSession(mac: mac)
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        let view = DirectFilesView(mac: mac, session: session, retainWhenDismissed: true)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.makeFirstResponder(nil); window.contentView = nil; window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func fields() -> MacCredentialFields.Fields? { descendants(host).compactMap { $0 as? MacCredentialFields.Fields }.first }
        func values() -> (String?, String?) { (fields()?.account.stringValue, fields()?.secret.stringValue) }
        func edit() throws {
            let fields = try XCTUnwrap(fields()); fields.account.stringValue = "synthetic-edited-account"; fields.secret.stringValue = "synthetic-edited-password"
        }
        func layout() { host.layoutSubtreeIfNeeded() }
        func element(_ identifier: String) -> NSObject? {
            var pending: [Any] = [host], visited = Set<ObjectIdentifier>()
            while let item = pending.popLast() {
                guard let object = item as? NSObject, visited.insert(ObjectIdentifier(object)).inserted else { continue }
                if object.responds(to: NSSelectorFromString("accessibilityIdentifier")), object.value(forKey: "accessibilityIdentifier") as? String == identifier { return object }
                if object.responds(to: NSSelectorFromString("accessibilityChildren")) { pending.append(contentsOf: object.value(forKey: "accessibilityChildren") as? [Any] ?? []) }
            }
            return nil
        }
        func press(_ button: NSObject) {
            let selector = NSSelectorFromString("accessibilityPerformPress")
            XCTAssertTrue(button.responds(to: selector)); _ = button.perform(selector)
        }
        func wait(_ predicate: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(10)
            while !predicate() {
                guard Date() < deadline else { throw DirectFilesFailure.timedOut }
                try await Task.sleep(for: .milliseconds(50)); layout()
            }
        }
        try await wait { values().1 == "synthetic-saved-password" }
        for edited in [false, true] {
            if edited { try edit(); try await Task.sleep(for: .milliseconds(150)) }
            let before = values()
            session.connect(username: try XCTUnwrap(before.0), password: try XCTUnwrap(before.1), key: nil, remember: true)
            try await wait { element("files-cancel-connection") != nil }
            // Invoke the mounted button action, rather than session.disconnect(),
            // which bypassed the draft-clearing regression.
            press(try XCTUnwrap(element("files-cancel-connection")))
            try await wait { session.phase == .interrupted && !session.busy }
            try await Task.sleep(for: .milliseconds(150)); layout()
            XCTAssertEqual(values().0, before.0); XCTAssertEqual(values().1, before.1)
            XCTAssertNotNil(element("files-connect"), "Cancellation must offer explicit reconnect without re-entry")
            XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.password, "synthetic-saved-password", "Cancellation must not rewrite stored credentials")
        }
        NotificationCenter.default.post(name: DirectClientPlatformV1.didEnterBackground, object: nil)
        try await wait { values().1 == "" }
    }
    #endif
    #if os(macOS)
    func testMountedFilesRestoresClearedSavedPasswordAndPreservesEditedRetryDraft() async throws {
        if !DirectProAccess.shared.ready { await DirectProAccess.shared.refresh() }
        let probe = FilesDirectoryTestProbe()
        let server = try await filesDirectoryTestServer(probe: probe)
        defer { Task { await probe.shutdown(); try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Remembered Login", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        try TerminalSecretStore.save(.init(username: "synthetic", password: "synthetic-only"), id: mac.id)
        let admission = FilesPresentationAdmission()
        let session = DirectFilesSession(mac: mac, canAccess: { admission.allowed })
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        var view = DirectFilesView(mac: mac, session: session, retainWhenDismissed: true)
        view.accessAllowed = { admission.allowed }
        view.sessionAvailable = { admission.active }
        #if os(iOS)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: view); window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        func account() -> UITextField? { descendants(window).compactMap { $0 as? UITextField }.first { !$0.isSecureTextEntry } }
        func secret() -> UITextField? { descendants(window).compactMap { $0 as? UITextField }.first { $0.isSecureTextEntry } }
        func values() -> (String?, String?) { (account()?.text, secret()?.text) }
        func edit(_ username: String, _ password: String) throws {
            let account = try XCTUnwrap(account()), secret = try XCTUnwrap(secret())
            account.text = username; account.sendActions(for: .editingChanged)
            secret.text = password; secret.sendActions(for: .editingChanged)
        }
        func layout() { window.layoutIfNeeded() }
        #else
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.makeFirstResponder(nil); window.contentView = nil; window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func fields() -> MacCredentialFields.Fields? { descendants(host).compactMap { $0 as? MacCredentialFields.Fields }.first }
        func values() -> (String?, String?) { (fields()?.account.stringValue, fields()?.secret.stringValue) }
        func edit(_ username: String, _ password: String) throws {
            let fields = try XCTUnwrap(fields())
            fields.account.stringValue = username; fields.secret.stringValue = password
        }
        func layout() { host.layoutSubtreeIfNeeded() }
        #endif
        func wait(_ predicate: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(10)
            while !predicate() {
                guard Date() < deadline else { throw DirectFilesFailure.timedOut }
                try await Task.sleep(for: .milliseconds(50)); layout()
            }
        }
        // Mount before the first connection: loaded=true must not block later reconnect.
        try await wait { values().0 == "synthetic" && values().1 == "synthetic-only" }
        func suspendAndReturn() async throws {
            admission.active = false
            NotificationCenter.default.post(name: DirectClientPlatformV1.didEnterBackground, object: nil)
            try await wait { values().1 == "" }
            admission.active = true
            NotificationCenter.default.post(name: DirectClientPlatformV1.didBecomeActive, object: nil)
            do { try await wait { values().1 == "synthetic-only" } }
            catch {
                XCTAssertEqual(values().1, "synthetic-only", "Returning must restore the remembered password without re-entry")
                throw error
            }
            XCTAssertEqual(values().0, "synthetic")
            XCTAssertNotEqual(session.phase, .ready, "Restoring a saved login must never reconnect automatically")
        }
        func lockAndUnlock() async throws {
            admission.allowed = false
            try await wait { values().1 == "" && session.phase == .interrupted }
            admission.allowed = true
            try await wait { values().1 == "synthetic-only" }
            XCTAssertEqual(values().0, "synthetic")
            XCTAssertEqual(session.phase, .interrupted, "Unlocking never reconnects automatically")
        }
        // Cover the whole round trip before any authentication, then repeat it
        // after successful authentication and Disconnect in this same view.
        try await suspendAndReturn()
        try await suspendAndReturn()
        try await lockAndUnlock()
        func connect() async throws {
            session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: true)
            try await wait { session.trust != nil || session.phase != .connecting }
            if session.trust != nil { session.answerTrust(true) }
            try await wait { session.phase == .ready || session.phase == .interrupted }
            XCTAssertEqual(session.phase, .ready, session.message ?? session.status)
            guard session.phase == .ready else { throw DirectFilesFailure.unavailable }
            // Give the mounted view's successful-connection observer time to clear the secret.
            try await Task.sleep(for: .milliseconds(150)); layout()
        }
        try await connect()
        session.disconnect()
        try await wait { values().1 == "synthetic-only" }
        XCTAssertEqual(values().0, "synthetic")
        XCTAssertEqual(session.phase, .interrupted, "Restoring the secret never reconnects automatically")
        try await suspendAndReturn()
        try await suspendAndReturn()
        try await lockAndUnlock()
        try edit("synthetic-edited-account", "synthetic-edited-password")
        try await Task.sleep(for: .milliseconds(150))
        session.connect(username: "synthetic-edited-account", password: "synthetic-edited-password", key: nil, remember: true)
        try await wait { session.phase == .interrupted } // Real password rejection from the owned peer.
        try await Task.sleep(for: .milliseconds(150)); layout()
        XCTAssertEqual(values().0, "synthetic-edited-account")
        XCTAssertEqual(values().1, "synthetic-edited-password")
        admission.allowed = false
        try await wait { values().1 == "" }
        admission.allowed = true
        try await Task.sleep(for: .milliseconds(150)); layout()
        XCTAssertEqual(values().0, "synthetic-edited-account", "Unlock must preserve the edited account")
        XCTAssertEqual(values().1, "", "Privacy cleanup cannot replace an edited password with an older saved login")
        try edit("synthetic", "synthetic-only")
        try await connect()
        await probe.shutdown() // Authenticated network loss in the same mounted view.
        try await wait { session.phase == .interrupted && values().1 == "synthetic-only" }
        XCTAssertEqual(values().0, "synthetic")
        try await connect()
        try TerminalSecretStore.forgetLogin(mac.id)
        session.disconnect()
        try await wait { values().0 == "synthetic" }
        XCTAssertEqual(values().1, "", "A removed saved login must never be restored")
    }
    #endif
    #if os(iOS)
    #if os(macOS)
    func testMountedFilesDefersFirstLoginUntilSignInBecomesAvailable() async throws {
        if !DirectProAccess.shared.ready { await DirectProAccess.shared.refresh() }
        // Keep the SSH handshake pending on an owned loopback socket, so the
        // new sheet's initial task runs while loading credentials is ineligible.
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { $0.eventLoop.makeSucceededFuture(()) }.bind(host: "127.0.0.1", port: 0).get()
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Deferred Login", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        try TerminalSecretStore.save(.init(username: "synthetic-saved-account", password: "synthetic-saved-password"), id: mac.id)
        let session = DirectFilesSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: DirectFilesView(mac: mac, session: session, retainWhenDismissed: true)); window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        func fields() -> [UITextField] { descendants(window).compactMap { $0 as? UITextField } }
        try await Task.sleep(for: .milliseconds(300)); window.layoutIfNeeded()
        XCTAssertTrue(session.busy); XCTAssertFalse(fields().contains { $0.text == "synthetic-saved-account" })
        session.disconnect()
        let deadline = Date().addingTimeInterval(5)
        while !fields().contains(where: { $0.text == "synthetic-saved-account" }) {
            guard Date() < deadline else { XCTFail("Deferred saved login was not initialized"); return }
            try await Task.sleep(for: .milliseconds(50)); window.layoutIfNeeded()
        }
        XCTAssertTrue(fields().contains { $0.text == "synthetic-saved-password" })
        XCTAssertEqual(session.phase, .interrupted, "Showing saved credentials must not reconnect automatically")
    }
    #endif
    #endif
    #if os(macOS)
    func testMountedFilesRefreshesExternalDiskKeyChangesWithoutReloadingDrafts() async throws {
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Key Selection", addresses: ["127.0.0.1"], sshPort: 1)
        let session = DirectFilesSession(mac: mac)
        defer { session.close(); try? TerminalSecretStore.forgetLogin(mac.id) }
        try TerminalSecretStore.save(.init(username: "synthetic-password-account", password: "synthetic-saved-password"), id: mac.id)
        let first = MacSSHKeyFileReference(id: UUID(), name: "Synthetic A", bookmark: Data([1]), fingerprint: "SHA256:synthetic-a")
        let second = MacSSHKeyFileReference(id: UUID(), name: "Synthetic B", bookmark: Data([2]), fingerprint: "SHA256:synthetic-b")
        var selection: (file: MacSSHKeyFileReference, username: String)? = (first, "synthetic-key-a")
        var view = DirectFilesView(mac: mac, session: session)
        // Synthetic references avoid real file grants and shared-library writes.
        view.selectedKeyFile = { _ in selection }
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.makeFirstResponder(nil); window.contentView = nil; window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func fields() -> MacCredentialFields.Fields? { descendants(host).compactMap { $0 as? MacCredentialFields.Fields }.first }
        func phrase() -> NSTextField? {
            let pair = fields()
            // SwiftUI's secure control may use a separate prompt and a different
            // NSTextField subclass. Exclude the native account/password pair.
            return descendants(host).compactMap { $0 as? NSTextField }.first {
                $0.isEditable && $0 !== pair?.account && $0 !== pair?.secret
            }
        }
        func settle() async throws { try await Task.sleep(for: .milliseconds(150)); host.layoutSubtreeIfNeeded() }
        let deadline = Date().addingTimeInterval(10)
        while fields()?.account.stringValue != "synthetic-key-a" || phrase() == nil {
            guard Date() < deadline else {
                XCTFail("Mounted Files login did not become available")
                return
            }
            try await settle()
        }
        func edit(_ field: NSTextField, _ value: String) async throws {
            XCTAssertTrue(window.makeFirstResponder(field))
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            window.makeFirstResponder(nil); try await settle()
        }
        let pair = try XCTUnwrap(fields())
        pair.secret.stringValue = "synthetic-edited-password" // Real autofill/KVO binding path.
        pair.account.stringValue = "synthetic-edited-account"
        try await edit(try XCTUnwrap(phrase()), "synthetic-passphrase-a")
        selection = (first, "unrelated-account-update")
        NotificationCenter.default.post(name: MacSSHKeyFileStore.changed, object: nil); try await settle()
        XCTAssertEqual(phrase()?.stringValue, "synthetic-passphrase-a", "Same-reference notifications preserve the draft")
        XCTAssertEqual(pair.account.stringValue, "synthetic-edited-account")
        XCTAssertEqual(pair.secret.stringValue, "synthetic-edited-password")
        selection = (second, "synthetic-key-b")
        NotificationCenter.default.post(name: MacSSHKeyFileStore.changed, object: nil); try await settle()
        XCTAssertEqual(pair.account.stringValue, "synthetic-key-b")
        XCTAssertEqual(phrase()?.stringValue, "", "A new file cannot inherit the previous file's passphrase")
        XCTAssertEqual(pair.secret.stringValue, "synthetic-edited-password")
        try await edit(try XCTUnwrap(phrase()), "synthetic-passphrase-b")
        selection = nil
        NotificationCenter.default.post(name: MacSSHKeyFileStore.changed, object: nil); try await settle()
        XCTAssertNil(phrase())
        XCTAssertEqual(pair.secret.stringValue, "synthetic-edited-password", "Removing a key must not reload the saved password")
        XCTAssertEqual(pair.account.stringValue, "synthetic-password-account")
        XCTAssertEqual(session.phase, .signIn, "Key-selection notifications never connect automatically")
        selection = (first, "synthetic-key-a")
        NotificationCenter.default.post(name: MacSSHKeyFileStore.changed, object: nil); try await settle()
        try await edit(try XCTUnwrap(phrase()), "synthetic-deferred-passphrase")
        // The owner is busy immediately; retire it before yielding, so this
        // cancellation test never authenticates or contacts a real Mac.
        session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: true)
        XCTAssertTrue(session.busy)
        selection = (second, "synthetic-deferred-key-b")
        NotificationCenter.default.post(name: MacSSHKeyFileStore.changed, object: nil)
        session.disconnect(); try await settle()
        XCTAssertEqual(fields()?.account.stringValue, "synthetic-deferred-key-b", "Returning to sign-in reconciles a key change missed while busy")
        XCTAssertEqual(phrase()?.stringValue, "")
        XCTAssertEqual(fields()?.secret.stringValue, "synthetic-edited-password")
        XCTAssertEqual(session.phase, .interrupted)
    }
    #endif
    func testFilesSignInAtNarrowWidthAndAccessibilitySize() async throws {
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Mac", addresses: ["fixture.local"])
        for large in [false, true] {
            let session = DirectFilesSession(mac: mac); defer { session.close() }
            let view = DirectFilesView(mac: mac, session: session).environment(\.dynamicTypeSize, large ? .accessibility3 : .large)
            #if os(iOS)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = UIHostingController(rootView: view); window.makeKeyAndVisible()
            defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
            try await Task.sleep(for: .milliseconds(200))
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            #else
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(200)); host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = NSImage(size: host.bounds.size); image.addRepresentation(bitmap)
            #endif
            let attachment = XCTAttachment(image: image); attachment.name = "files-sign-in-" + (large ? "accessibility" : "default"); attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertEqual(session.phase, .signIn, "Presentation must never authenticate automatically")
            XCTAssertFalse(session.busy)
        }
    }
}

/// Recreate the actual Files presentation around a retained owner. This covers
/// the host lifetime that a same-view foreground/background test cannot exercise.
@MainActor private final class FilesMountedPresentation {
    #if os(iOS)
    private let window: UIWindow
    private let previous: UIWindow?
    init(_ view: some View) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previous = scene.windows.first { $0.isKeyWindow }
        window = UIWindow(windowScene: scene); window.frame = .init(x: 0, y: 0, width: 390, height: 844)
        mount(view); window.makeKeyAndVisible()
    }
    func mount(_ view: some View) { window.rootViewController = UIHostingController(rootView: view) }
    func hide() { window.endEditing(true); window.rootViewController = nil }
    func close() { hide(); window.isHidden = true; previous?.makeKeyAndVisible() }
    func layout() { window.layoutIfNeeded() }
    private func fields() -> [UITextField] {
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        return descendants(window).compactMap { $0 as? UITextField }
    }
    func values() -> (String?, String?) { (fields().first { !$0.isSecureTextEntry }?.text, fields().first { $0.isSecureTextEntry }?.text) }
    func edit(_ username: String, _ password: String) throws {
        let account = try XCTUnwrap(fields().first { !$0.isSecureTextEntry }), secret = try XCTUnwrap(fields().first { $0.isSecureTextEntry })
        account.text = username; account.sendActions(for: .editingChanged)
        secret.text = password; secret.sendActions(for: .editingChanged)
    }
    #else
    private let window: NSWindow
    init(_ view: some View) throws {
        window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; mount(view); window.orderFront(nil)
    }
    func mount(_ view: some View) { window.contentView = NSHostingView(rootView: view) }
    func hide() { window.makeFirstResponder(nil); window.contentView = nil }
    func close() { hide(); window.close() }
    func layout() { window.contentView?.layoutSubtreeIfNeeded() }
    private func fields() -> MacCredentialFields.Fields? {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        return window.contentView.map(descendants)?.compactMap { $0 as? MacCredentialFields.Fields }.first
    }
    func values() -> (String?, String?) { (fields()?.account.stringValue, fields()?.secret.stringValue) }
    func edit(_ username: String, _ password: String) throws {
        let fields = try XCTUnwrap(fields()); fields.account.stringValue = username; fields.secret.stringValue = password
    }
    #endif
    func wait(_ predicate: () -> Bool) async throws {
        let end = Date().addingTimeInterval(10)
        while !predicate() {
            guard Date() < end else { throw DirectFilesFailure.timedOut }
            try await Task.sleep(for: .milliseconds(50)); layout()
        }
        layout()
    }
}
