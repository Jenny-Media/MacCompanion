import XCTest
import SwiftUI
import Crypto
import NIO
import NIOSSH
import Citadel
import Darwin
import ActivityKit
import AppIntents
@testable import Mac_Companion

@MainActor private final class TerminalActivityTestBackend: RemoteSessionActivityBackend {
    var enabled = true
    var ids: [String] = []
    var attributes: RemoteSessionActivityAttributes?
    var phase: RemoteSessionActivityAttributes.Phase?
    func existingIDs() -> [String] { ids }
    func start(_ attributes: RemoteSessionActivityAttributes, content: ActivityContent<RemoteSessionActivityAttributes.ContentState>) throws -> String {
        self.attributes = attributes; phase = content.state.phase; ids = ["terminal-synthetic"]; return ids[0]
    }
    func update(_ id: String, content: ActivityContent<RemoteSessionActivityAttributes.ContentState>) async { phase = content.state.phase }
    func end(_ id: String) async { ids.removeAll { $0 == id } }
}
private final class SSHTestRecord: @unchecked Sendable {
    let respondToInstall: Bool
    init(respondToInstall: Bool = true) { self.respondToInstall = respondToInstall }
    private let lock=NSLock()
    private var auth=0, keyAuth=0
    private var execs=0
    private var input: [UInt8] = []
    private var shell: Channel?
    func opened(_ channel: Channel) { lock.lock(); shell = channel; lock.unlock() }
    func emit(_ text: String) async throws {
        let channel = activeShell()
        try await channel?.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(ByteBuffer(string: text)))).get()
    }
    private func activeShell() -> Channel? { lock.lock(); defer { lock.unlock() }; return shell }
    var received: [UInt8] { lock.lock(); defer { lock.unlock() }; return input }
    func received(_ bytes: [UInt8]) { lock.lock(); defer { lock.unlock() }; input.append(contentsOf: bytes.prefix(max(0, 512 - input.count))) }
    var commands: Int { lock.lock(); defer { lock.unlock() }; return execs }
    func executed() { lock.lock(); execs += 1; lock.unlock() }
    private var cols=0, rows=0
    var passwordRequests: Int { lock.lock(); defer { lock.unlock() }; return auth }
    var keyRequests: Int { lock.lock(); defer { lock.unlock() }; return keyAuth }
    func keyAuthenticated() { lock.lock(); keyAuth += 1; lock.unlock() }
    var size: [Int] { lock.lock(); defer { lock.unlock() }; return [cols,rows] }
    func authenticated() { lock.lock(); auth += 1; lock.unlock() }
    func resized(_ cols:Int,_ rows:Int) { lock.lock(); self.cols=cols; self.rows=rows; lock.unlock() }
}
private final class SSHTestAuth: NIOSSHServerUserAuthenticationDelegate, @unchecked Sendable {
    let record:SSHTestRecord
    let publicKey: NIOSSHPublicKey?
    var supportedAuthenticationMethods:NIOSSHAvailableUserAuthenticationMethods { publicKey == nil ? .password : [.publicKey, .password] }
    init(_ record:SSHTestRecord, publicKey: NIOSSHPublicKey? = nil) { self.record=record; self.publicKey=publicKey }
    func requestReceived(request:NIOSSHUserAuthenticationRequest,responsePromise:EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        switch request.request {
        case .publicKey(let login): record.keyAuthenticated(); responsePromise.succeed(request.username == "synthetic" && login.publicKey == publicKey ? .success : .failure)
        case .password(let login): record.authenticated(); responsePromise.succeed(request.username == "synthetic" && login.password == "synthetic-only" ? .success : .failure)
        default: responsePromise.succeed(.failure)
        }
    }
}
private final class SSHTestPTY: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn=SSHChannelData
    typealias OutboundIn=SSHChannelData
    typealias OutboundOut=SSHChannelData
    let record:SSHTestRecord
    init(_ record:SSHTestRecord) { self.record=record }
    func userInboundEventTriggered(context:ChannelHandlerContext,event:Any) {
        if let request=event as? SSHChannelRequestEvent.PseudoTerminalRequest {
            record.resized(request.terminalCharacterWidth,request.terminalRowHeight)
            context.triggerUserOutboundEvent(ChannelSuccessEvent(),promise:nil)
        } else if event is SSHChannelRequestEvent.ShellRequest {
            record.opened(context.channel)
            context.triggerUserOutboundEvent(ChannelSuccessEvent(),promise:nil)
            context.writeAndFlush(wrapOutboundOut(SSHChannelData(type:.channel,data:.byteBuffer(ByteBuffer(string:"synthetic-ready\r\n")))),promise:nil)
        } else if let request = event as? SSHChannelRequestEvent.ExecRequest {
            guard request.command.hasPrefix("/bin/sh -c '"), request.command.contains("authorized_keys"), request.command.contains("ssh-ed25519") else { context.close(promise: nil); return }
            record.executed(); guard record.respondToInstall else { return }
            context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
            context.writeAndFlush(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(ByteBuffer(string: "MC_KEY_INSTALLED\n")))), promise: nil)
            context.triggerUserOutboundEvent(SSHChannelRequestEvent.ExitStatus(exitStatus: 0), promise: nil)
            context.close(promise: nil)
        } else if let request=event as? SSHChannelRequestEvent.WindowChangeRequest { record.resized(request.terminalCharacterWidth,request.terminalRowHeight) }
        else { context.fireUserInboundEventTriggered(event) }
    }
    func channelRead(context:ChannelHandlerContext,data:NIOAny) {
        let value = unwrapInboundIn(data)
        if case .byteBuffer(let buffer) = value.data { record.received(Array(buffer.readableBytesView)) }
        context.writeAndFlush(wrapOutboundOut(value),promise:nil)
    }
    func errorCaught(context:ChannelHandlerContext,error:Error) { context.close(promise:nil) }
}
// Observe bytes, then forward them to the normal pipeline tail. Before the SSH
// parser exists this reproduces NIO's discarded early-banner path.
private final class SSHEarlyReadProbe: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    let record: SSHTestRecord
    init(_ record: SSHTestRecord) { self.record = record }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        record.received(Array(unwrapInboundIn(data).readableBytesView))
        context.fireChannelRead(data)
    }
}
@MainActor final class TerminalIntegrationTests:XCTestCase {
    func testSavedTerminalLoginStartsOnEntryAndRetainsTrustGateAndSingleAttempt() async throws {
        let record = SSHTestRecord(), key = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await server(record: record, key: key)
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Saved Login", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        try TerminalSecretStore.save(.init(username: "synthetic", password: "synthetic-only"), id: mac.id)
        let session = DirectTerminalSession(mac: mac)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, exit: {}).directAppearance())
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; try? TerminalSecretStore.remove(mac.id) }
        try await wait("saved login starts without tapping Connect") { session.trust != nil || session.recovery != nil }
        XCTAssertNotNil(session.trust); XCTAssertEqual(record.passwordRequests, 0)
        session.answerTrust(true)
        try await wait("saved login authenticates after identity approval") { session.connected || session.recovery != nil }
        XCTAssertTrue(session.connected, session.status); XCTAssertEqual(record.passwordRequests, 1)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(session.connected); XCTAssertEqual(record.passwordRequests, 1, "Trust-sheet dismissal must not trigger a second attempt")
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let controls = try XCTUnwrap(descendants(host.view).compactMap { $0 as? CompanionVNCControls }.first)
        controls.button.sendActions(for: .touchUpInside)
        let interrupt = try XCTUnwrap(descendants(controls).first { $0.accessibilityIdentifier == "session-action-interrupt" } as? UIButton)
        interrupt.sendActions(for: .touchUpInside)
        try await wait("floating Ctrl-C reaches the PTY") { record.received.contains(3) }
        XCTAssertEqual(record.passwordRequests, 1)
    }
    func testFailedSavedLoginRemainsVisibleWithoutAutomaticRetry() async throws {
        let record = SSHTestRecord(), key = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await server(record: record, key: key)
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Rejected Login", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        try TerminalSecretStore.save(.init(username: "synthetic", password: "wrong-synthetic-only"), id: mac.id)
        try TerminalSecretStore.write(Data(String(openSSHPublicKey: key.publicKey).utf8), id: mac.id, kind: "host-key")
        let session = DirectTerminalSession(mac: mac)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, exit: {}).directAppearance())
        window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; try? TerminalSecretStore.remove(mac.id) }
        try await wait("saved login rejection remains actionable") { session.recovery != nil }
        XCTAssertFalse(session.connected); XCTAssertFalse(session.connecting)
        XCTAssertEqual(session.recovery?.reason, .loginRejected)
        XCTAssertEqual(record.passwordRequests, 1)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(session.recovery?.reason, .loginRejected); XCTAssertEqual(record.passwordRequests, 1)
        XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.password, "wrong-synthetic-only", "A failed attempt must not erase the saved login")
    }
    func testConnectedSocketPreservesEarlyServerBannerUntilSSHHandlersExist() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let additions = try XCTUnwrap(fixture["clientAdditions"] as? [String: Any])
        let profile = try XCTUnwrap(additions["ssh"] as? [String: Any])
        let readBeforeParser = try XCTUnwrap(profile["automaticReadsBeforeParser"] as? Bool)
        XCTAssertFalse(readBeforeParser)
        XCTAssertEqual(profile["enableReadsAfterHandlersBeforeAuthentication"] as? Bool, true)
        for autoRead in [true, readBeforeParser] {
            let record = SSHTestRecord(), early = SSHTestRecord(), key = NIOSSHPrivateKey(ed25519Key: .init())
            let server = try await server(record: record, key: key)
            defer { _ = server.close() }
            let port = try XCTUnwrap(server.localAddress?.port)
            // Use the same already-connected-socket registration as production.
            let fd = try await Task.detached {
                let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
                guard fd >= 0 else { throw POSIXError(.ENOTCONN) }
                let address = try SocketAddress(ipAddress: "127.0.0.1", port: port)
                let result = address.withSockAddr { Darwin.connect(fd, $0, socklen_t($1)) }
                guard result == 0 else { Darwin.close(fd); throw POSIXError(.ENOTCONN) }
                return fd
            }.value
            let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .channelOption(ChannelOptions.autoRead, value: autoRead)
                .channelInitializer { $0.pipeline.addHandler(SSHEarlyReadProbe(early)) }
                .withConnectedSocket(fd).get()
            defer { _ = channel.close() }
            if autoRead {
                try await wait("banner discarded before parser attachment") { !early.received.isEmpty }
                XCTAssertTrue(String(decoding: early.received, as: UTF8.self).hasPrefix("SSH-2.0-"))
                XCTAssertEqual(record.passwordRequests, 0)
                continue
            }
            // An intentional scheduling gap used to lose the server's banner.
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(early.received.isEmpty)
            let readsPaused = try await channel.getOption(ChannelOptions.autoRead).get()
            XCTAssertFalse(readsPaused)
            var settings = SSHClientSettings(host: "127.0.0.1", port: port,
                authenticationMethod: { .passwordBased(username: "synthetic", password: "synthetic-only") },
                hostKeyValidator: .trustedKeys([key.publicKey]))
            settings.connectTimeout = .seconds(3)
            let client = try await SSHClient.connect(on: channel, settings: settings)
            let readsResumed = try await channel.getOption(ChannelOptions.autoRead).get()
            XCTAssertTrue(readsResumed)
            XCTAssertTrue(String(decoding: early.received, as: UTF8.self).hasPrefix("SSH-2.0-"))
            XCTAssertEqual(record.passwordRequests, 1)
            try await client.close()
        }
    }
    func testInstallUsesBootstrapThenFreshKeyLoginBeforeSelectionAndPreservesPassword() async throws {
        for valid in [true, false] {
            let record = SSHTestRecord(), key = TerminalSSHKey.create(), old = TerminalSSHKey.create()
            let id = try TerminalKeyLibraryStore.add(key, name: "Synthetic Target")
            let oldID = try TerminalKeyLibraryStore.add(old, name: "Synthetic Existing")
            let entry = TerminalNamedKey(id: id, name: "Synthetic Target", key: key)
            let publicKey = NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(rawRepresentation: (valid ? key : old).seed)).publicKey
            let server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()), publicKey: publicKey)
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Install", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
            let session = DirectTerminalSession(mac: mac)
            defer { session.stop(); try? TerminalSecretStore.remove(mac.id); try? TerminalKeyLibraryStore.delete(id); try? TerminalKeyLibraryStore.delete(oldID) }
            try TerminalKeyLibraryStore.associate(oldID, macID: mac.id, username: "original")
            try TerminalSecretStore.save(.init(username: "preserved", password: "saved-synthetic"), id: mac.id)
            session.connect(username: "synthetic", password: "synthetic-only", remember: false, installation: entry)
            try await wait("setup trust") { session.trust != nil || !session.connecting }
            XCTAssertEqual(record.passwordRequests, 0); XCTAssertEqual(record.commands, 0)
            session.answerTrust(true)
            try await wait("installation and verification") { !session.connecting }
            XCTAssertEqual(record.passwordRequests, 1); XCTAssertEqual(record.commands, 1)
            XCTAssertGreaterThan(record.keyRequests, 0)
            XCTAssertEqual(session.recovery?.reason, valid ? .setupVerified : .setupLoginUnverified)
            if !valid {
                XCTAssertTrue(session.recovery?.message.contains("automatic key-only login test failed") == true)
                XCTAssertTrue(session.recovery?.details.contains(.init(name: "Cause", value: "SSH key wasn’t accepted")) == true)
            }
            XCTAssertEqual(session.installedKey, valid ? id : nil, session.status)
            XCTAssertEqual(try TerminalKeyLibraryStore.selected(mac.id)?.id, valid ? id : oldID)
            XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.password, "saved-synthetic")
            try await server.close()
        }
    }
    func testVerificationOnlyNeverInstallsOrUsesPasswordAndPreservesPriorLoginOnRejection() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let policy = try XCTUnwrap((fixture["errorRecovery"] as? [String: Any])?["verificationOnly"] as? [String: Any])
        for valid in [true, false] {
            let record = SSHTestRecord(), target = TerminalSSHKey.create(), old = TerminalSSHKey.create()
            let targetID = try TerminalKeyLibraryStore.add(target, name: "Verification Target")
            let oldID = try TerminalKeyLibraryStore.add(old, name: "Prior Login")
            let entry = TerminalNamedKey(id: targetID, name: "Verification Target", key: target)
            let pub = NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(rawRepresentation: (valid ? target : old).seed)).publicKey
            let server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()), publicKey: pub)
            let mac = DirectMacRecordV1(id: UUID(), name: "Verification Mac", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
            let session = DirectTerminalSession(mac: mac)
            defer { session.stop(); try? TerminalSecretStore.remove(mac.id); try? TerminalKeyLibraryStore.delete(targetID); try? TerminalKeyLibraryStore.delete(oldID) }
            try TerminalKeyLibraryStore.associate(oldID, macID: mac.id, username: "prior")
            try TerminalSecretStore.save(.init(username: "prior", password: "preserved-synthetic"), id: mac.id)
            session.testKeyLogin(username: "synthetic", target: entry)
            try await wait("verification trust") { session.trust != nil || !session.connecting }
            XCTAssertNotNil(session.trust); XCTAssertEqual(record.passwordRequests, 0); XCTAssertEqual(record.keyRequests, 0); XCTAssertEqual(record.commands, 0)
            XCTAssertEqual(try TerminalKeyLibraryStore.selected(mac.id)?.id, oldID)
            session.answerTrust(true)
            try await wait("verification outcome") { !session.connecting }
            XCTAssertEqual(record.passwordRequests, policy["passwordRequests"] as? Int)
            XCTAssertEqual(record.commands, policy["commands"] as? Int)
            XCTAssertGreaterThan(record.keyRequests, 0)
            XCTAssertEqual(session.recovery?.reason, valid ? .setupVerified : .keyRejected)
            XCTAssertEqual(try TerminalKeyLibraryStore.selected(mac.id)?.id, valid ? targetID : oldID)
            XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.password, "preserved-synthetic")
            try await server.close()
        }
    }
    func testCancelledUnacknowledgedInstallRemainsUncertainAndRetryIsVerificationOnly() async throws {
        let record = SSHTestRecord(respondToInstall: false), target = TerminalSSHKey.create()
        let keyID = try TerminalKeyLibraryStore.add(target, name: "Unacknowledged Setup")
        let entry = TerminalNamedKey(id: keyID, name: "Unacknowledged Setup", key: target)
        let pub = NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(rawRepresentation: target.seed)).publicKey
        let server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()), publicKey: pub)
        let mac = DirectMacRecordV1(id: UUID(), name: "Cancelled Setup", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectTerminalSession(mac: mac)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id); try? TerminalKeyLibraryStore.delete(keyID) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false, installation: entry)
        try await wait("setup trust") { session.trust != nil }; session.answerTrust(true)
        try await wait("unacknowledged command") { record.commands == 1 }
        session.cancelConnection()
        XCTAssertEqual(session.recovery?.reason, .setupUncertain); XCTAssertNil(try TerminalKeyLibraryStore.selected(mac.id))
        session.testKeyLogin(username: "synthetic", target: entry)
        try await wait("verification only after cancel") { !session.connecting }
        XCTAssertEqual(session.installedKey, keyID, session.status)
        XCTAssertEqual(record.commands, 1); XCTAssertEqual(record.passwordRequests, 1)
        try await server.close()
    }
    private func server(record:SSHTestRecord,key:NIOSSHPrivateKey, publicKey: NIOSSHPublicKey? = nil) async throws -> Channel {
        let auth=SSHTestAuth(record, publicKey: publicKey)
        return try await ServerBootstrap(group:MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
            channel.pipeline.addHandler(NIOSSHHandler(role:.server(.init(hostKeys:[key],userAuthDelegate:auth)),allocator:channel.allocator,inboundChildChannelInitializer:{ child,type in
                child.pipeline.addHandler(SSHTestPTY(record))
            }))
        }.bind(host:"127.0.0.1",port:0).get()
    }
    private func wait(_ message: String = "synthetic SSH session", _ condition: @MainActor ()->Bool) async throws {
        for _ in 0..<500 { if condition() { return }; try await Task.sleep(for:.milliseconds(10)) }
        XCTFail("Timed out waiting for \(message)")
        throw POSIXError(.ETIMEDOUT)
    }
    func testEd25519AuthenticatesOnlyAfterHostTrustWithoutPasswordFallback() async throws {
        let record = SSHTestRecord(), key = TerminalSSHKey.create()
        let publicKey = NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(rawRepresentation: key.seed)).publicKey
        let server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()), publicKey: publicKey)
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Key SSH", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectTerminalSession(mac: mac)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "MUST-NOT-SEND", remember: false, key: key)
        try await wait("key host trust") { session.trust != nil || !session.connecting }
        XCTAssertNotNil(session.trust); XCTAssertEqual(record.keyRequests, 0); XCTAssertEqual(record.passwordRequests, 0)
        session.answerTrust(true); try await wait("key authentication success") { session.connected || !session.connecting }
        XCTAssertTrue(session.connected, session.status); XCTAssertGreaterThan(record.keyRequests, 0); XCTAssertEqual(record.passwordRequests, 0)
        XCTAssertEqual(try TerminalSecretStore.sshKey(mac.id)?.username, "synthetic")
        session.stop()
        session.connect(username: "synthetic", password: "synthetic-only", remember: true, key: .create())
        try await wait("wrong key rejection; status: \(session.status); key requests: \(record.keyRequests)") { !session.connecting }
        XCTAssertFalse(session.connected); XCTAssertEqual(record.passwordRequests, 0)
        try await server.close()
    }
    func testRealSSHTrustBeforeLoginInteractivePTYOrderedInputResizeAndPreservedShell() async throws {
        let record=SSHTestRecord(),key=NIOSSHPrivateKey(ed25519Key:.init())
        let server=try await server(record:record,key:key)
        let mac=DirectMacRecordV1(id:UUID(),name:"Synthetic SSH",addresses:["127.0.0.1"],sshPort:try XCTUnwrap(server.localAddress?.port))
        let session=DirectTerminalSession(mac:mac)
        var output=[UInt8](); session.received={ output += $0 }
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username:"synthetic",password:"synthetic-only",remember:true)
        try await wait { session.trust != nil || !session.connecting }
        XCTAssertNotNil(session.trust); XCTAssertEqual(record.passwordRequests,0)
        session.answerTrust(true); try await wait { session.connected || !session.connecting }
        XCTAssertTrue(session.connected,session.status); XCTAssertEqual(record.passwordRequests,1)
        try await wait { String(decoding:output,as:UTF8.self).contains("synthetic-ready") }
        session.send(Array("A".utf8)); session.send(Array("B".utf8)); session.resize(columns:100,rows:30)
        try await wait { String(decoding:output,as:UTF8.self).hasSuffix("AB") && record.size == [100,30] }
        XCTAssertEqual(record.size,[100,30]); XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.username,"synthetic")
        let controller = TerminalController(session: session, customize: {}); controller.loadViewIfNeeded()
        let render = session.received
        session.received = { render?($0); output += $0 }
        controller.terminal.insertText("a")
        controller.terminal.keyboardState.toggle(.alt); controller.terminal.deleteBackward()
        XCTAssertFalse(controller.terminal.hasText); XCTAssertTrue(controller.terminal.keyboardState.active.isEmpty)
        controller.terminal.insertText("c")
        controller.terminal.keyboardState.toggle(.shift); controller.terminal.insertText("1")
        try await wait { record.received.suffix(5) == [0x61, 0x1b, 0x7f, 0x63, 0x21] }
        controller.terminal.insertText("xy")
        try await wait { record.received.suffix(2) == [0x78, 0x79] }
        let beforeDeletion = record.received.count
        controller.terminal.selectedTextRange = controller.terminal.textRange(from: controller.terminal.beginningOfDocument, to: controller.terminal.endOfDocument)
        controller.terminal.keyboardState.toggle(.alt); controller.terminal.deleteBackward()
        XCTAssertFalse(controller.terminal.hasText)
        try await wait { record.received.count >= beforeDeletion + 2 }
        XCTAssertEqual(Array(record.received.dropFirst(beforeDeletion)), [0x1b, 0x7f])
        for attempt in 0..<4 {
            controller.terminal.keyboardState.toggle(.ctrl)
            let inputCount = record.received.count
            session.background(); await session.waitForLifecycleUpdates()
            XCTAssertTrue(session.connected); XCTAssertTrue(session.suspended)
            XCTAssertTrue(controller.terminal.keyboardState.active.isEmpty)
            session.send(Array("MUST-NOT-REPLAY".utf8))
            session.resize(columns: 110 + attempt, rows: 35 + attempt)
            let marker = "background-output-\(attempt)"
            let renderedCount = output.count
            try await record.emit(marker)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(output.count, renderedCount, "Paused output must not reach the terminal view")
            XCTAssertEqual(session.pausedOutputByteCount, 0, "Pausing transport reads should apply backpressure")
            XCTAssertEqual(record.received.count, inputCount)
            session.foreground(); await session.waitForLifecycleUpdates()
            XCTAssertTrue(session.connected); XCTAssertFalse(session.suspended)
            try await wait("same shell output and latest size resume") {
                String(decoding: output, as: UTF8.self).contains(marker) && record.size == [110 + attempt, 35 + attempt]
            }
            session.send(Array("resume-\(attempt)".utf8))
            try await wait { String(decoding: record.received, as: UTF8.self).hasSuffix("resume-\(attempt)") }
            XCTAssertEqual(record.passwordRequests, 1, "Foreground must retain the same authenticated shell")
        }
        session.background(); session.foreground(); session.background()
        await session.waitForLifecycleUpdates()
        XCTAssertTrue(session.connected); XCTAssertTrue(session.suspended)
        session.foreground(); await session.waitForLifecycleUpdates()
        XCTAssertFalse(session.suspended); XCTAssertEqual(record.passwordRequests, 1)
        session.background(); await session.waitForLifecycleUpdates()
        session.foreground(); session.stop(); await session.waitForLifecycleUpdates()
        XCTAssertFalse(session.connected); XCTAssertFalse(session.suspended)
        session.send(Array("MUST-NOT-REPLAY".utf8)); XCTAssertFalse(session.connected)
        try await server.close()
    }
    func testPausedOutputIsBoundedOrderedAndNotRenderedUntilForeground() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let ssh = try XCTUnwrap((fixture["clientAdditions"] as? [String: Any])?["ssh"] as? [String: Any])
        let lifecycle = try XCTUnwrap(ssh["lifecycle"] as? [String: Any])
        XCTAssertEqual(lifecycle["pendingOutputLimitBytes"] as? Int, DirectTerminalSession.maximumPausedOutputBytes)
        let record = SSHTestRecord(), serverKey = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await server(record: record, key: serverKey)
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Buffer", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let backend = TerminalActivityTestBackend(), defaults = UserDefaults(suiteName: "terminal-lifecycle-" + UUID().uuidString)!
        let session = DirectTerminalSession(mac: mac, activityDefaults: defaults, activityBackend: backend)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        var output = [UInt8](); session.received = { output += $0 }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil || !session.connecting }
        session.answerTrust(true); try await wait { session.connected || !session.connecting }
        try await wait { !output.isEmpty }; output.removeAll()
        await session.waitForLifecycleUpdates()
        XCTAssertEqual(backend.attributes?.kind, .terminal); XCTAssertEqual(backend.phase, .connected)
        session.background(); await session.waitForLifecycleUpdates()
        XCTAssertEqual(backend.phase, .paused)
        try session.receiveOutput([1, 2]); try session.receiveOutput([3, 4])
        XCTAssertTrue(output.isEmpty); XCTAssertEqual(session.pausedOutputByteCount, 4)
        XCTAssertThrowsError(try session.receiveOutput(Array(repeating: 0, count: DirectTerminalSession.maximumPausedOutputBytes))) {
            XCTAssertEqual($0 as? TerminalConnectionFailure, .pausedOutputLimit)
        }
        XCTAssertEqual(session.pausedOutputByteCount, 4)
        session.foreground(); await session.waitForLifecycleUpdates()
        XCTAssertEqual(output, [1, 2, 3, 4]); XCTAssertEqual(session.pausedOutputByteCount, 0)
        XCTAssertEqual(backend.phase, .connected); XCTAssertEqual(record.passwordRequests, 1)
        defaults.set(false, forKey: VNCSessionActivityController.preferenceKey)
        session.activity?.preferenceChanged(); await session.waitForLifecycleUpdates()
        XCTAssertTrue(backend.ids.isEmpty); XCTAssertTrue(session.connected, "Status opt-out must retain SSH")
        session.background(); await session.waitForLifecycleUpdates()
        session.foreground(); await session.waitForLifecycleUpdates()
        XCTAssertTrue(session.connected); XCTAssertEqual(record.passwordRequests, 1)
        defaults.set(true, forKey: VNCSessionActivityController.preferenceKey)
        session.activity?.preferenceChanged(); await session.waitForLifecycleUpdates()
        XCTAssertFalse(session.endActivity("unrelated")); XCTAssertTrue(session.connected)
        XCTAssertTrue(session.endActivity("terminal-synthetic"))
        await session.waitForLifecycleUpdates()
        XCTAssertFalse(session.connected); XCTAssertFalse(session.endActivity("terminal-synthetic"))
        XCTAssertEqual(session.pausedOutputByteCount, 0)
    }
    func testBackgroundCancelsIncompleteTrustWithoutSendingLogin() async throws {
        let record = SSHTestRecord(), server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()))
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Trust", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectTerminalSession(mac: mac)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil || !session.connecting }
        XCTAssertNotNil(session.trust)
        session.background(); session.answerTrust(true); session.foreground()
        await session.waitForLifecycleUpdates()
        XCTAssertFalse(session.connected); XCTAssertFalse(session.connecting)
        XCTAssertNil(session.activity); XCTAssertEqual(record.passwordRequests, 0)
        XCTAssertEqual(session.recovery?.reason, .connectionCancelled)
    }
    func testTerminalEndIntentExitsOnlyItsPausedShell() async throws {
        guard ActivityKitSessionBackend().enabled else { throw XCTSkip("Live Activities disabled in Simulator settings") }
        let record = SSHTestRecord(), server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()))
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Terminal End", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let defaults = UserDefaults(suiteName: "terminal-end-" + UUID().uuidString)!
        let session = DirectTerminalSession(mac: mac, activityDefaults: defaults)
        var exits = 0
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, autoConnect: false, exit: { exits += 1 }).directAppearance())
        window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; try? TerminalSecretStore.remove(mac.id) }
        try await Task.sleep(for: .milliseconds(200))
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil || !session.connecting }
        session.answerTrust(true); try await wait { session.connected || !session.connecting }
        await session.waitForLifecycleUpdates()
        let id = try XCTUnwrap(Activity<RemoteSessionActivityAttributes>.activities.first { $0.attributes.macID == mac.id }?.id)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        await session.waitForLifecycleUpdates(); XCTAssertTrue(session.connected); XCTAssertTrue(session.suspended)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await session.waitForLifecycleUpdates(); XCTAssertTrue(session.connected); XCTAssertFalse(session.suspended)
        XCTAssertEqual(record.passwordRequests, 1)
        session.background(); await session.waitForLifecycleUpdates()
        _ = try await EndRemoteSessionIntent(activityID: "unrelated").perform()
        XCTAssertTrue(session.connected); XCTAssertEqual(exits, 0)
        _ = try await EndRemoteSessionIntent(activityID: id).perform()
        XCTAssertFalse(session.connected); XCTAssertEqual(exits, 1)
        _ = try await EndRemoteSessionIntent(activityID: id).perform()
        XCTAssertEqual(exits, 1); XCTAssertFalse(ActivityKitSessionBackend().existingIDs().contains(id))
    }
    func testChangedHostKeyRejectsBeforeAnyPasswordAuthentication() async throws {
        let record=SSHTestRecord(), key=NIOSSHPrivateKey(ed25519Key:.init())
        let server=try await server(record:record,key:key)
        let mac=DirectMacRecordV1(id:UUID(),name:"Synthetic Changed SSH",addresses:["127.0.0.1"],sshPort:try XCTUnwrap(server.localAddress?.port))
        let other=NIOSSHPrivateKey(ed25519Key:.init())
        try TerminalSecretStore.write(Data(String(openSSHPublicKey:other.publicKey).utf8),id:mac.id,kind:"host-key")
        let session=DirectTerminalSession(mac:mac); defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username:"synthetic",password:"synthetic-only",remember:false)
        try await wait { !session.connecting }
        XCTAssertFalse(session.connected); XCTAssertEqual(record.passwordRequests,0); XCTAssertNil(session.trust)
        XCTAssertEqual(session.recovery?.reason, .serverChanged)
        try await server.close()
    }
    func testRejectedFirstHostKeyCancelsWithoutSavingOrSendingLogin() async throws {
        let record=SSHTestRecord(),key=NIOSSHPrivateKey(ed25519Key:.init()),server=try await server(record:record,key:key)
        let mac=DirectMacRecordV1(id:UUID(),name:"Synthetic Reject SSH",addresses:["127.0.0.1"],sshPort:try XCTUnwrap(server.localAddress?.port))
        let session=DirectTerminalSession(mac:mac); defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username:"synthetic",password:"synthetic-only",remember:false)
        try await wait { session.trust != nil || !session.connecting }; XCTAssertNotNil(session.trust,session.status); session.answerTrust(false)
        try await wait { !session.connecting }; XCTAssertEqual(record.passwordRequests,0); XCTAssertNil(try TerminalSecretStore.hostKey(mac.id))
        try await server.close()
    }
}
