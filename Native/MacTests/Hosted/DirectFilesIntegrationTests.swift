import XCTest
import Foundation
import Crypto
import NIO
import NIOSSH
import Citadel
import SwiftUI
import AppKit
import Observation
@testable import MacCompanion

/// The only server here is a disposable XCTest transport to macOS's own SFTP
/// executable. No server, shell process or helper is linked into either client.
private final class FilesTestSFTPProcess: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData
    private let root: URL
    private let allowSFTP: Bool
    private let responseDelay: TimeAmount
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    init(root: URL, allowSFTP: Bool, responseDelay: TimeAmount) { self.root = root; self.allowSFTP = allowSFTP; self.responseDelay = responseDelay }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        guard let request = event as? SSHChannelRequestEvent.SubsystemRequest else { context.fireUserInboundEventTriggered(event); return }
        guard allowSFTP, request.subsystem == "sftp", process == nil else { context.triggerUserOutboundEvent(ChannelFailureEvent(), promise: nil); return }
        let process = Process(), input = Pipe(), output = Pipe(), channel = context.channel
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/sftp-server")
        process.arguments = ["-d", root.path]; process.currentDirectoryURL = root
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        self.process = process; self.input = input; self.output = output
        let delay = responseDelay
        output.fileHandleForReading.readabilityHandler = { handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil; channel.close(promise: nil) }
            else {
                channel.eventLoop.scheduleTask(in: delay) {
                    guard channel.isActive else { return }
                    channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(ByteBuffer(bytes: bytes))), promise: nil)
                }
            }
        }
        do { try process.run(); context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil) }
        catch { context.triggerUserOutboundEvent(ChannelFailureEvent(), promise: nil); stop() }
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case .byteBuffer(let buffer) = unwrapInboundIn(data).data, let input else { context.close(promise: nil); return }
        do { try input.fileHandleForWriting.write(contentsOf: Data(buffer.readableBytesView)) }
        catch { context.close(promise: nil) }
    }
    func channelInactive(context: ChannelHandlerContext) { stop(); context.fireChannelInactive() }
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
    private func stop() {
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close(); try? output?.fileHandleForReading.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil; input = nil; output = nil
    }
}

@MainActor @Observable private final class FilesTestAccess { var allowed = true }

@MainActor final class DirectFilesIntegrationTests: XCTestCase {
    private func wait(_ predicate: () -> Bool, seconds: Double = 10) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate() {
            guard Date() < deadline else { throw DirectFilesFailure.timedOut }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    private func open(_ session: DirectFilesSession) async throws {
        session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: false)
        try await wait { session.trust != nil || session.phase != .connecting }
        if session.trust != nil { session.answerTrust(true) }
        try await wait { session.phase != .connecting }
        XCTAssertEqual(session.phase, .ready, session.message ?? session.status)
        guard session.phase == .ready else { throw DirectFilesFailure.unavailable }
    }
    private func server(root: URL, record: SSHTestRecord, allowSFTP: Bool = true, responseDelay: TimeAmount = .nanoseconds(0)) async throws -> Channel {
        let hostKey = NIOSSHPrivateKey(ed25519Key: .init())
        return try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
            record.openedTransport(channel)
            return channel.pipeline.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [hostKey], userAuthDelegate: SSHTestAuth(record, usernames: ["synthetic", "synthetic-second"]))), allocator: channel.allocator,
                inboundChildChannelInitializer: { child, _ in child.pipeline.addHandler(FilesTestSFTPProcess(root: root, allowSFTP: allowSFTP, responseDelay: responseDelay)) }))
        }.bind(host: "127.0.0.1", port: 0).get()
    }
    func testMacOSSFTPBrowseFolderUploadKeepBothReplaceDownloadAndIsolation() async throws {
        let root = try DirectFilesLocalStore.root(), local = try DirectFilesLocalStore.root()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: local) }
        let server = try await self.server(root: root, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let first = DirectFilesSession(mac: mac), second = DirectFilesSession(mac: mac)
        defer { first.close(); second.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(first); try await open(second)
        let home = try XCTUnwrap(first.directory?.path)
        XCTAssertEqual(URL(fileURLWithPath: home).standardizedFileURL.resolvingSymlinksInPath(), root.resolvingSymlinksInPath())
        first.createFolder("Uploads"); try await wait { !first.busy }
        XCTAssertTrue(first.directory?.entries.contains { $0.name == "Uploads" && $0.kind == .folder } == true)
        let folder = try DirectFilesPolicy.child("Uploads", of: home)
        first.browse(folder); try await wait { !first.busy }; XCTAssertEqual(first.directory?.path, folder)
        try await captureBrowser(first, name: "mac-files-empty-folder")
        let source = try DirectFilesLocalStore.emptyFile(in: local, name: "report.txt")
        let original = Data((0..<100_000).map { UInt8($0 % 251) }); try original.write(to: source)
        first.upload([source], to: folder); try await wait { !first.busy }
        XCTAssertEqual(first.results.first?.outcome, .completed, first.results.first?.message ?? "")
        let remote = URL(fileURLWithPath: folder).appendingPathComponent("report.txt")
        XCTAssertEqual(try Data(contentsOf: remote), original)
        try await captureBrowser(first, name: "mac-files-upload-completed")
        let changed = Data(repeating: 7, count: 70_000); try changed.write(to: source)
        first.upload([source], to: folder); try await wait { first.conflict != nil }; first.answerConflict(.keepBoth); try await wait { !first.busy }
        XCTAssertEqual(first.results.first?.outcome, .completed)
        XCTAssertEqual(first.results.first?.destinationName, "report (2).txt")
        XCTAssertEqual(try Data(contentsOf: remote), original)
        XCTAssertEqual(try Data(contentsOf: remote.deletingLastPathComponent().appendingPathComponent("report (2).txt")), changed)
        first.upload([source], to: folder); try await wait { first.conflict != nil }; first.answerConflict(.replace); try await wait { !first.busy }
        XCTAssertEqual(first.results.first?.outcome, .completed, first.results.first?.message ?? "")
        XCTAssertEqual(try Data(contentsOf: remote), changed)
        let entry = try XCTUnwrap(first.directory?.entries.first { $0.name == "report.txt" })
        first.download(entry); try await wait { !first.busy }
        XCTAssertEqual(first.results.first?.outcome, .completed)
        let downloaded = try XCTUnwrap(first.results.first?.localDownload)
        XCTAssertEqual(try Data(contentsOf: downloaded), changed)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder).contains { $0.hasPrefix(".maccompanion-upload-") })
        first.close(); XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.path))
        second.browse(home); try await wait { !second.busy }; XCTAssertEqual(second.phase, .ready)
    }
    private func captureBrowser(_ session: DirectFilesSession, name: String) async throws {
        let host = NSHostingView(rootView: DirectFilesView(mac: session.mac, session: session, retainWhenDismissed: true))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(250)); host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: host.bounds.size); image.addRepresentation(bitmap)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testInterruptionRequiresExplicitReconnectAndRetryWithNoAutomaticReplay() async throws {
        let root = try DirectFilesLocalStore.root(), local = try DirectFilesLocalStore.root()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: local) }
        let server = try await self.server(root: root, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac)
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        let source = try DirectFilesLocalStore.emptyFile(in: local, name: "interrupted.txt")
        let bytes = Data(repeating: 8, count: 300_000); try bytes.write(to: source)
        let folder = session.home
        let staged = try await session.prepare([source])
        var stopped = false, dismissRequested = true
        session.activityChanged = { [weak session] _ in
            if !stopped, (session?.results.first?.bytes ?? 0) > 0 {
                stopped = true; dismissRequested = session?.confirmExit(.disconnect, retainWhenDismissed: false) ?? true
            }
        }
        session.upload(staged, to: folder); try await wait { stopped && !session.busy }
        XCTAssertFalse(dismissRequested); XCTAssertTrue(FileManager.default.fileExists(atPath: staged[0].path))
        XCTAssertEqual(session.results.first?.outcome, .interrupted)
        let destination = URL(fileURLWithPath: folder).appendingPathComponent("interrupted.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        session.activityChanged = nil
        session.connect(username: "synthetic-second", password: "synthetic-only", key: nil, remember: false)
        try await wait { session.phase != .connecting }
        XCTAssertEqual(session.phase, .ready)
        let resultID = try XCTUnwrap(session.results.first?.id)
        session.upload([source], to: folder)
        session.download(.init(name: "another.txt", kind: .file, size: 1))
        XCTAssertEqual(session.results.first?.id, resultID); XCTAssertFalse(session.busy)
        session.retry(try XCTUnwrap(session.results.first?.id))
        XCTAssertFalse(session.busy); XCTAssertEqual(session.results.first?.outcome, .interrupted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "A retry cannot change accounts")
        session.disconnect()
        try await open(session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(session.results.first?.outcome, .interrupted)
        session.retry(try XCTUnwrap(session.results.first?.id)); try await wait { !session.busy }
        XCTAssertEqual(session.results.first?.outcome, .completed, session.results.first?.message ?? "")
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
        session.discardResults()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testPendingDownloadsRequireSaveOrDiscardBeforeNewTransfers() async throws {
        let root = try DirectFilesLocalStore.root(), local = try DirectFilesLocalStore.root()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: local) }
        let remoteA = root.appendingPathComponent("a.txt"), remoteB = root.appendingPathComponent("b.txt")
        try Data([1]).write(to: remoteA); try Data([2]).write(to: remoteB)
        let server = try await self.server(root: root, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac)
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        let a = try XCTUnwrap(session.directory?.entries.first { $0.name == "a.txt" })
        let b = try XCTUnwrap(session.directory?.entries.first { $0.name == "b.txt" })
        let source = try DirectFilesLocalStore.emptyFile(in: local, name: "upload.txt"); try Data([3]).write(to: source)
        session.download(a); try await wait { !session.busy }
        let id = try XCTUnwrap(session.results.first?.id), download = try XCTUnwrap(session.results.first?.localDownload)
        XCTAssertTrue(session.hasPendingResults); XCTAssertTrue(session.hasUnsavedDownloads)
        session.download(b); session.upload([source], to: session.home)
        XCTAssertEqual(session.results.first?.id, id); XCTAssertEqual(try Data(contentsOf: download), Data([1]))
        XCTAssertFalse(session.busy)
        do { _ = try await session.prepare([source]); XCTFail("Pending downloads must survive upload preparation") } catch {}
        XCTAssertEqual(session.results.first?.id, id)
        session.discardResults()
        XCTAssertTrue(session.results.isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath: download.path))
        XCTAssertEqual(try Data(contentsOf: remoteA), Data([1]))
        session.download(b); try await wait { !session.busy }
        let secondID = try XCTUnwrap(session.results.first?.id), secondDownload = try XCTUnwrap(session.results.first?.localDownload)
        let exported = local.appendingPathComponent("exported.txt"); try FileManager.default.copyItem(at: secondDownload, to: exported)
        session.markSaved(secondID); XCTAssertFalse(session.hasPendingResults)
        let staged = try await session.prepare([source])
        session.upload(staged, to: session.home); try await wait { !session.busy }
        XCTAssertEqual(session.results.first?.outcome, .completed, session.results.first?.message ?? "")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("upload.txt")), Data([3]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondDownload.path))
        XCTAssertEqual(try Data(contentsOf: exported), Data([2])); XCTAssertEqual(try Data(contentsOf: source), Data([3]))
        XCTAssertFalse(session.confirmExit(.close, retainWhenDismissed: true))
        XCTAssertTrue(session.confirmExit(.close, retainWhenDismissed: false))
    }
    func testFilesUnsavedPasswordRemovesPreviousLoginButPreservesHostTrust() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let server = try await self.server(root: root, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try TerminalSecretStore.save(.init(username: "old-synthetic", password: "old-synthetic"), id: mac.id)
        try await open(session); XCTAssertNil(try TerminalSecretStore.login(mac.id))
        let pin = try XCTUnwrap(TerminalSecretStore.hostKey(mac.id)); session.disconnect()
        session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: true)
        try await wait { session.phase != .connecting }; XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.password, "synthetic-only")
        session.disconnect(); try await open(session)
        XCTAssertNil(try TerminalSecretStore.login(mac.id)); XCTAssertEqual(try TerminalSecretStore.hostKey(mac.id), pin)
    }
    func testConfirmedCloseReleasesPendingDownloadAndNativeDismissalProtection() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("pending.txt"))
        let server = try await self.server(root: root, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Pending Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        session.download(try XCTUnwrap(session.directory?.entries.first { $0.name == "pending.txt" }))
        try await wait { !session.busy }
        let download = try XCTUnwrap(session.results.first?.localDownload)
        XCTAssertTrue(DirectFilesPolicy.preventsDismissal(retained: false, active: session.transferActive, pending: session.hasPendingResults))
        XCTAssertFalse(session.confirmExit(.close, retainWhenDismissed: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: download.path)); XCTAssertTrue(session.hasPendingResults)
        XCTAssertTrue(session.confirmExit(.close, retainWhenDismissed: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: download.path)); XCTAssertFalse(session.hasPendingResults)
        XCTAssertFalse(DirectFilesPolicy.preventsDismissal(retained: false, active: session.transferActive, pending: session.hasPendingResults))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("pending.txt").path))
    }
    func testProgressingSFTPListingOutlastsIdleDeadlineAndStalledResponseTimesOut() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<512 { try Data().write(to: root.appendingPathComponent("file-\(index).txt")) }
        let server = try await self.server(root: root, record: SSHTestRecord(), responseDelay: .milliseconds(200))
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac, idleTimeout: .milliseconds(900))
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        let began = ContinuousClock.now
        session.browse(session.home); try await wait { !session.busy }
        XCTAssertGreaterThan(began.duration(to: .now), .milliseconds(900))
        XCTAssertEqual(session.phase, .ready, session.message ?? ""); XCTAssertEqual(session.directory?.entries.count, 512)
        session.disconnect()
        let stalledServer = try await self.server(root: root, record: SSHTestRecord(), responseDelay: .seconds(2))
        defer { Task { try? await stalledServer.close() } }
        let stalledMac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(stalledServer.localAddress?.port))
        let stalled = DirectFilesSession(mac: stalledMac, idleTimeout: .milliseconds(900))
        defer { stalled.close(); try? TerminalSecretStore.remove(stalledMac.id) }
        stalled.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: false)
        try await wait { stalled.trust != nil || stalled.phase != .connecting }; stalled.answerTrust(true)
        try await wait { stalled.phase != .connecting }
        XCTAssertEqual(stalled.phase, .interrupted); XCTAssertTrue(stalled.message?.contains("stopped responding") == true)
    }
    func testSFTPAdmissionAndMissingUploadDestinationEachResetIdleDeadline() async throws {
        let root = try DirectFilesLocalStore.root(), local = try DirectFilesLocalStore.root()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: local) }
        // Every response is within the idle budget; VERSION + REALPATH, and
        // missing-destination LSTAT + OPEN, each exceed it if activity is lost.
        let server = try await self.server(root: root, record: SSHTestRecord(), responseDelay: .milliseconds(600))
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Slow Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac, idleTimeout: .milliseconds(1000))
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        let source = try DirectFilesLocalStore.emptyFile(in: local, name: "new.txt"), bytes = Data([1, 2, 3])
        try bytes.write(to: source)
        session.upload([source], to: session.home); try await wait({ !session.busy }, seconds: 20)
        XCTAssertEqual(session.phase, .ready, session.message ?? "")
        XCTAssertEqual(session.results.first?.outcome, .completed, session.results.first?.message ?? "")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("new.txt")), bytes)
    }
    func testCachedRegularFileChangedToSymlinkIsRejectedBeforeDownloadingTarget() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("selected.txt"), target = root.appendingPathComponent("target.txt")
        try Data([1]).write(to: selected); try Data([2]).write(to: target)
        let server = try await self.server(root: root, record: SSHTestRecord())
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        let stale = try XCTUnwrap(session.directory?.entries.first { $0.name == "selected.txt" })
        XCTAssertEqual(stale.kind, .file)
        try FileManager.default.removeItem(at: selected); try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: target)
        session.download(stale); try await wait { !session.busy }
        XCTAssertEqual(session.results.first?.outcome, .interrupted); XCTAssertNil(session.results.first?.localDownload)
        XCTAssertEqual(session.results.first?.message, DirectFilesFailure.notRegular.localizedDescription)
        XCTAssertEqual(try Data(contentsOf: target), Data([2]))
    }
    func testLifecycleStopsHiddenOwnerAndChangedHostPinRejectsBeforeAuthentication() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let record = SSHTestRecord(), server = try await self.server(root: root, record: record)
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let access = FilesTestAccess()
        let session = DirectFilesSession(mac: mac, canAccess: { access.allowed })
        defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        try await open(session)
        access.allowed = false; try await wait { session.phase == .interrupted }
        access.allowed = true
        XCTAssertEqual(session.phase, .interrupted, "Unlock must not reconnect automatically")
        try await open(session)
        NotificationCenter.default.post(name: DirectClientPlatformV1.didEnterBackground, object: nil)
        XCTAssertEqual(session.phase, .interrupted)
        try await open(session)
        session.disconnect()
        let replacementRecord = SSHTestRecord(), replacement = try await self.server(root: root, record: replacementRecord)
        defer { Task { try? await replacement.close() } }
        let changedMac = DirectMacRecordV1(id: mac.id, name: mac.name, addresses: mac.addresses, sshPort: try XCTUnwrap(replacement.localAddress?.port))
        let changed = DirectFilesSession(mac: changedMac); defer { changed.close() }
        changed.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: false)
        try await wait { changed.phase != .connecting }
        XCTAssertEqual(changed.phase, .interrupted)
        XCTAssertTrue(changed.message?.contains("identity changed") == true, changed.message ?? "")
        XCTAssertNil(changed.trust); XCTAssertEqual(replacementRecord.passwordRequests, 0)
    }
    func testRejectedLoginAndUnavailableSFTPHaveSeparateGuidance() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let server = try await self.server(root: root, record: SSHTestRecord(), allowSFTP: false)
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Files", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectFilesSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "incorrect-synthetic", key: nil, remember: false)
        try await wait { session.trust != nil || session.phase != .connecting }
        session.answerTrust(true); try await wait { session.phase != .connecting }
        XCTAssertTrue(session.message?.contains("did not accept") == true, session.message ?? "")
        session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: false)
        try await wait { session.phase != .connecting }
        XCTAssertTrue(session.message?.contains("SSH connected, but Files") == true, session.message ?? "")
        XCTAssertFalse(session.message?.contains("did not accept") == true)
    }
}
