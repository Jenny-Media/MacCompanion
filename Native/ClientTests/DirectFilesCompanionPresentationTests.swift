#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import Vision
@preconcurrency @testable import Citadel
@testable import Mac_Companion

@MainActor final class DirectFilesCompanionPresentationTests: XCTestCase {
    func testFilesUsesNoSeparateCredentialFormAtNarrowAndAccessibilitySizes() async throws {
        for large in [false, true] {
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files Companion", addresses: ["127.0.0.1"])
            let session = DirectFilesSession(mac: mac)
            defer { session.close() }
            var view = DirectFilesView(mac: mac, session: session, retainWhenDismissed: true)
            view.sessionAvailable = { false }
            let mount = try CompanionFilesMount(view.dynamicTypeSize(large ? .accessibility5 : .large))
            defer { mount.close() }
            try await Task.sleep(for: .milliseconds(150))
            mount.layout()
            XCTAssertTrue(mount.fields.isEmpty, "Files must not add its own account, password or key-selection form")
            XCTAssertEqual(session.phase, .signIn); XCTAssertFalse(session.busy)
            XCTAssertFalse(DirectMacConnections.shared.isActive(mac.id))
            XCTAssertGreaterThan(mount.window.bounds.height, 0)
        }
    }
    func testSheetDismissalAndRemountKeepAuthenticatedFilesAndDirectory() async throws {
        let probe = FilesDirectoryTestProbe()
        let server = try await filesDirectoryTestServer(probe: probe)
        defer { Task { await probe.shutdown(); try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Retained Companion", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let client = try await SSHClient.connect(to: .init(host: "127.0.0.1", port: mac.sshPort,
            authenticationMethod: { .passwordBased(username: "synthetic", password: "synthetic-only") }, hostKeyValidator: .acceptAnything()))
        defer { Task { try? await client.close() } }
        let files = DirectFilesSession(mac: mac); defer { files.close() }
        let context = DirectFilesConnectionContext(client: client, macID: mac.id, account: "synthetic", keyID: nil, generation: UUID())
        files.connectBorrowed(context)
        try await wait { !files.busy }
        XCTAssertEqual(files.phase, .ready)
        let path = files.directory?.path
        let mount = try CompanionFilesMount(DirectFilesView(mac: mac, session: files, retainWhenDismissed: true))
        defer { mount.close() }
        try await Task.sleep(for: .milliseconds(100))
        mount.hide()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(files.phase, .ready); XCTAssertFalse(files.isClosed)
        XCTAssertEqual(files.directory?.path, path)
        mount.show(DirectFilesView(mac: mac, session: files, retainWhenDismissed: true))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(files.phase, .ready); XCTAssertEqual(files.directory?.path, path)
        XCTAssertTrue(mount.fields.isEmpty)
    }
    func testDownloadsStayWithTheirAccountAndSurviveMacRemoval() async throws {
        let probe = FilesDirectoryTestProbe(), bytes = Data([1, 2, 3])
        let server = try await filesDirectoryTestServer(probe: probe, downloadBytes: bytes)
        defer { Task { await probe.shutdown(); try? await server.close() } }
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let library = DirectMacLibraryV1(url: root.appendingPathComponent("macs.json"), removeLogin: { _ in })
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Account Boundary", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        XCTAssertTrue(library.save(id: mac.id, name: mac.name, addresses: mac.addresses, sshPort: mac.sshPort))
        let client = try await SSHClient.connect(to: .init(host: "127.0.0.1", port: mac.sshPort,
            authenticationMethod: { .passwordBased(username: "synthetic", password: "synthetic-only") }, hostKeyValidator: .acceptAnything()))
        defer { Task { try? await client.close() } }
        let files = DirectFilesWorkspace.session(mac, libraryURL: library.storageURL); defer { files.close() }
        let context = DirectFilesConnectionContext(client: client, macID: mac.id, account: "synthetic", keyID: nil, generation: UUID())
        files.connectBorrowed(context); try await wait { !files.busy }
        XCTAssertEqual(files.phase, .ready)
        files.download(.init(name: "sample.bin", kind: .file, size: UInt64(bytes.count)))
        try await wait { !files.busy }
        XCTAssertTrue(files.hasUnsavedDownloads)
        let download = try XCTUnwrap(files.results.first?.localDownload)
        XCTAssertEqual(try Data(contentsOf: download), bytes)
        files.disconnectBorrowed(context.generation)
        files.connectBorrowed(.init(client: client, macID: mac.id, account: "another-account", keyID: nil, generation: UUID()))
        XCTAssertEqual(files.phase, .interrupted); XCTAssertEqual(files.resultsAccount, "synthetic")
        XCTAssertEqual(files.account, "synthetic"); XCTAssertEqual(probe.authentications, 1)
        try library.applyCloud([])
        try await wait { files.macRemoved }
        XCTAssertFalse(files.isClosed); XCTAssertTrue(files.hasUnsavedDownloads)
        XCTAssertEqual(DirectFilesWorkspace.recoverableDownloads(libraryURL: library.storageURL).map(\.mac.id), [mac.id])
        XCTAssertTrue(DirectFilesWorkspace.recoverableDownloads(libraryURL: root.appendingPathComponent("another-library.json")).isEmpty)
        XCTAssertEqual(try Data(contentsOf: download), bytes)
        files.discardResults()
        XCTAssertTrue(files.shouldCloseAfterRemoval)
        XCTAssertTrue(DirectFilesWorkspace.recoverableDownloads(libraryURL: library.storageURL).isEmpty)
    }
    func testRemovedMacDownloadsReplaceNativeTerminalLoginUntilSavedOrDiscarded() async throws {
        for save in [false, true] {
            let outcome = save ? "export" : "discard"
            let probe = FilesDirectoryTestProbe(), bytes = Data([7, 8, 9])
            let server = try await filesDirectoryTestServer(probe: probe, downloadBytes: bytes)
            defer { Task { await probe.shutdown(); try? await server.close() } }
            let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
            let library = DirectMacLibraryV1(url: root.appendingPathComponent("macs.json"), removeLogin: { _ in })
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Terminal Download Recovery", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
            XCTAssertTrue(library.save(id: mac.id, name: mac.name, addresses: mac.addresses, sshPort: mac.sshPort))
            let client = try await SSHClient.connect(to: .init(host: "127.0.0.1", port: mac.sshPort,
                authenticationMethod: { .passwordBased(username: "synthetic", password: "synthetic-only") }, hostKeyValidator: .acceptAnything()))
            defer { Task { try? await client.close() } }
            let files = DirectFilesWorkspace.session(mac, libraryURL: library.storageURL)
            let terminal = DirectTerminalSession(mac: mac, libraryURL: library.storageURL)
            defer { files.close(); terminal.stop(); try? TerminalSecretStore.remove(mac.id) }
            let context = DirectFilesConnectionContext(client: client, macID: mac.id, account: "synthetic", keyID: nil, generation: UUID())
            files.connectBorrowed(context)
            try await waitForRecovery(outcome + ": borrowed Files ready", diagnostics: { files.message ?? files.phase.rawValue }) { !files.busy }
            XCTAssertEqual(files.phase, .ready)
            files.download(.init(name: "sample.bin", kind: .file, size: UInt64(bytes.count)))
            try await waitForRecovery(outcome + ": completed download", diagnostics: { files.message ?? files.phase.rawValue }) { !files.busy }
            let result = try XCTUnwrap(files.results.first), download = try XCTUnwrap(result.localDownload)
            // Completed downloads can outlive their original shell. Reopening
            // Terminal must not let its native login portal cover removal recovery.
            files.disconnectBorrowed(context.generation)
            let panel = DirectConnectionPanelHost()
            var exits = 0
            let mount = try CompanionFilesMount(TerminalDownloadRecoveryHarness(mac: mac, library: library,
                terminal: terminal, files: files, panel: panel, exited: { exits += 1 }).directAppearance())
            do {
                try await waitForRecovery(outcome + ": native login panel presented") {
                    panel.isVisible && mount.window.rootViewController?.presentedViewController != nil
                }
                try library.applyCloud([])
                try await waitForRecovery(outcome + ": owners observe cloud removal") { terminal.macRemoved && files.macRemoved }
                try await waitForRecovery(outcome + ": native login panel dismissed", diagnostics: {
                    "visible=\(panel.isVisible), presented=\(String(describing: mount.window.rootViewController?.presentedViewController))"
                }) { !panel.isVisible && mount.window.rootViewController?.presentedViewController == nil }
                var recoveryImage: UIImage?, recoveryText = ""
                try await waitForRecovery(outcome + ": recovery message visibly rendered", diagnostics: { recoveryText }) {
                    let image = mount.snapshot()
                    do { recoveryText = try mount.recognizedText(in: image).lowercased() }
                    catch { recoveryText = "OCR failed: \(error)" }
                    let visible = recoveryText.contains("save or discard your downloads") && recoveryText.contains("close files")
                    if visible { recoveryImage = image }
                    return visible
                }
                XCTAssertFalse(terminal.connected); XCTAssertFalse(terminal.connecting)
                XCTAssertEqual(exits, 0, "Removal keeps the recovery owner until its downloads are handled")
                XCTAssertTrue(files.hasUnsavedDownloads); XCTAssertFalse(files.isClosed)
                XCTAssertEqual(try Data(contentsOf: download), bytes)
                XCTAssertFalse(mount.fields.contains { $0.accessibilityIdentifier == "terminal-login-username" || $0.accessibilityIdentifier == "terminal-login-password" })
                let attachment = XCTAttachment(image: try XCTUnwrap(recoveryImage))
                attachment.name = "terminal-native-panel-download-recovery-" + outcome
                attachment.lifetime = .keepAlways; add(attachment)
                if save {
                    let exported = root.appendingPathComponent("exported.bin")
                    try FileManager.default.copyItem(at: download, to: exported)
                    files.markSaved(result.id)
                    XCTAssertEqual(try Data(contentsOf: exported), bytes)
                } else { files.discardResults() }
                try await waitForRecovery(outcome + ": parent exits after download handled") { exits > 0 }
                XCTAssertTrue(files.shouldCloseAfterRemoval)
                try await waitForRecovery(outcome + ": unmounted owner clears staged download") { !FileManager.default.fileExists(atPath: download.path) }
                await mount.close(afterDismissing: panel)
            } catch {
                let attachment = XCTAttachment(image: mount.snapshot())
                attachment.name = "terminal-native-panel-download-recovery-failure-" + outcome
                attachment.lifetime = .keepAlways; add(attachment)
                await mount.close(afterDismissing: panel)
                throw error
            }
        }
    }
    func testUnsavedQuickConnectDownloadsRemainReachableAfterParentExit() async throws {
        for export in [false, true] {
            let probe = FilesDirectoryTestProbe(), bytes = Data([4, 5, 6])
            let server = try await filesDirectoryTestServer(probe: probe, downloadBytes: bytes)
            defer { Task { await probe.shutdown(); try? await server.close() } }
            let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
            let libraryURL = root.appendingPathComponent("macs.json")
            let library = DirectMacLibraryV1(url: libraryURL, removeLogin: { _ in })
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Unsaved Quick Connect", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
            let client = try await SSHClient.connect(to: .init(host: "127.0.0.1", port: mac.sshPort,
                authenticationMethod: { .passwordBased(username: "synthetic", password: "synthetic-only") }, hostKeyValidator: .acceptAnything()))
            defer { Task { try? await client.close() } }
            let files = DirectFilesWorkspace.session(mac, libraryURL: libraryURL); defer { files.close() }
            files.connectBorrowed(.init(client: client, macID: mac.id, account: "synthetic", keyID: nil, generation: UUID()))
            try await wait { !files.busy }; XCTAssertEqual(files.phase, .ready)
            files.download(.init(name: "sample.bin", kind: .file, size: UInt64(bytes.count)))
            try await wait { !files.busy }
            let result = try XCTUnwrap(files.results.first), download = try XCTUnwrap(result.localDownload)
            XCTAssertTrue(library.macs.isEmpty)
            XCTAssertTrue(DirectFilesWorkspace.recoverableDownloads(libraryURL: libraryURL).isEmpty)
            DirectFilesWorkspace.endTemporarySession(mac.id, libraryURL: libraryURL)
            try await wait { !DirectMacConnections.shared.isActive(mac.id) }
            XCTAssertFalse(files.isClosed); XCTAssertTrue(files.macRemoved)
            XCTAssertEqual(DirectFilesWorkspace.recoverableDownloads(libraryURL: libraryURL).map(\.mac.id), [mac.id])
            XCTAssertTrue(DirectFilesWorkspace.session(mac, libraryURL: libraryURL) === files)
            XCTAssertEqual(try Data(contentsOf: download), bytes)
            // A new quick connection has a different UUID and cannot claim the download.
            let next = DirectMacRecordV1(id: UUID(), name: mac.name, addresses: mac.addresses, sshPort: mac.sshPort)
            let nextFiles = DirectFilesWorkspace.session(next, libraryURL: libraryURL); defer { nextFiles.close() }
            XCTAssertTrue(nextFiles.results.isEmpty)
            if export {
                let saved = root.appendingPathComponent("exported.bin")
                try FileManager.default.copyItem(at: download, to: saved)
                files.markSaved(result.id)
                XCTAssertEqual(try Data(contentsOf: saved), bytes)
            } else { files.discardResults() }
            XCTAssertTrue(files.shouldCloseAfterRemoval)
            XCTAssertTrue(DirectFilesWorkspace.recoverableDownloads(libraryURL: libraryURL).isEmpty)
            files.close(); XCTAssertFalse(FileManager.default.fileExists(atPath: download.path))
            DirectFilesWorkspace.endTemporarySession(next.id, libraryURL: libraryURL)
            XCTAssertTrue(nextFiles.isClosed, "An ended temporary session with no downloads needs no recovery owner")
        }
    }
    private func waitForRecovery(_ label: String, file: StaticString = #filePath, line: UInt = #line,
                                 diagnostics: () -> String = { "" }, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(8)
        while !condition() {
            guard Date() < end else {
                XCTFail("Timed out waiting for " + label + ". " + diagnostics(), file: file, line: line)
                throw DirectFilesFailure.timedOut
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
    private func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(8)
        while !condition() { guard Date() < end else { throw DirectFilesFailure.timedOut }; try await Task.sleep(for: .milliseconds(20)) }
    }
}

/// Match the library's exit ownership: handling the last download removes the
/// whole Terminal subtree, rather than merely recording an exit callback.
@MainActor private struct TerminalDownloadRecoveryHarness: View {
    let mac: DirectMacRecordV1
    let library: DirectMacLibraryV1
    let terminal: DirectTerminalSession
    let files: DirectFilesSession
    let panel: DirectConnectionPanelHost
    let exited: @MainActor () -> Void
    @State private var showingTerminal = true
    init(mac: DirectMacRecordV1, library: DirectMacLibraryV1, terminal: DirectTerminalSession,
         files: DirectFilesSession, panel: DirectConnectionPanelHost, exited: @escaping @MainActor () -> Void) {
        self.mac = mac; self.library = library; self.terminal = terminal
        self.files = files; self.panel = panel; self.exited = exited
    }
    var body: some View {
        ZStack {
            // An opacity-zero recovery surface must not pass as visible content.
            Color(uiColor: .magenta).ignoresSafeArea()
            if showingTerminal {
                DirectTerminalView(mac: mac, macLibrary: library, session: terminal, files: files,
                    autoConnect: false, connectionPanel: panel, exit: {
                        panel.close(); showingTerminal = false; exited()
                    })
            }
        }.background(DirectConnectionPanelAnchor(host: panel).frame(width: 0, height: 0))
    }
}

@MainActor private final class CompanionFilesMount {
    let window: UIWindow
    private let previous: UIWindow?
    init(_ view: some View) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previous = scene.windows.first { $0.isKeyWindow }
        window = UIWindow(windowScene: scene); window.frame = .init(x: 0, y: 0, width: 390, height: 844)
        show(view); window.makeKeyAndVisible()
    }
    var fields: [UITextField] {
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        return descendants(window).compactMap { $0 as? UITextField }
    }
    func snapshot() -> UIImage {
        layout()
        return UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
    func recognizedText(in image: UIImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: try XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
    func close(afterDismissing panel: DirectConnectionPanelHost) async {
        // Do not deinitialize SwiftUI's sheet host during UIKit's animated
        // dismissal; otherwise a timeout's real failure can be masked by deinit.
        panel.close()
        for _ in 0..<100 {
            if window.rootViewController?.presentedViewController == nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        await Task.yield()
        close()
    }
    func show(_ view: some View) { window.rootViewController = UIHostingController(rootView: view) }
    func hide() { window.endEditing(true); window.rootViewController = nil }
    func close() { hide(); window.isHidden = true; previous?.makeKeyAndVisible() }
    func layout() { window.layoutIfNeeded() }
}
#endif
