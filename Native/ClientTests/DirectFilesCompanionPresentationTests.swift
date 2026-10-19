#if os(iOS)
import XCTest
import SwiftUI
import UIKit
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
    private func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(8)
        while !condition() { guard Date() < end else { throw DirectFilesFailure.timedOut }; try await Task.sleep(for: .milliseconds(20)) }
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
    func show(_ view: some View) { window.rootViewController = UIHostingController(rootView: view) }
    func hide() { window.endEditing(true); window.rootViewController = nil }
    func close() { hide(); window.isHidden = true; previous?.makeKeyAndVisible() }
    func layout() { window.layoutIfNeeded() }
}
#endif
