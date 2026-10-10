import XCTest
import UIKit
import SwiftUI
import Crypto
@preconcurrency import NIO
@preconcurrency import NIOSSH
@preconcurrency import Citadel
import Darwin
@testable import Mac_Companion

/// Generated interoperability workload, never an additional golden corpus.
/// SSH authenticates a synthetic account. The RFB peer completes ARD's client
/// exchange but does not claim to validate macOS account authentication.
private final class DesktopSSHRecord: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [String: Int]()
    func add(_ key: String) { lock.lock(); values[key, default: 0] += 1; lock.unlock() }
    func count(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return values[key, default: 0] }
}
private final class DesktopSSHAuth: NIOSSHServerUserAuthenticationDelegate, @unchecked Sendable {
    let record: DesktopSSHRecord
    init(_ record: DesktopSSHRecord) { self.record = record }
    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { .password }
    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        record.add("auth")
        if request.username == "synthetic", case .password(let login) = request.request, login.password == "synthetic-only" {
            responsePromise.succeed(.success)
        } else { responsePromise.succeed(.failure) }
    }
}
private final class DesktopSSHEcho: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    func channelRead(context: ChannelHandlerContext, data: NIOAny) { context.writeAndFlush(data, promise: nil) }
}
private final class DesktopSyntheticRFB: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData
    let record: DesktopSSHRecord
    private var input = ByteBuffer()
    private var stage = 0
    init(_ record: DesktopSSHRecord) { self.record = record }
    private func send(_ bytes: [UInt8], _ context: ChannelHandlerContext) {
        context.writeAndFlush(wrapOutboundOut(.init(type: .channel, data: .byteBuffer(ByteBuffer(bytes: bytes)))), promise: nil)
    }
    func channelActive(context: ChannelHandlerContext) { send(Array("RFB 003.889\n".utf8), context); context.fireChannelActive() }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case .byteBuffer(var buffer) = unwrapInboundIn(data).data else { context.close(promise: nil); return }
        input.writeBuffer(&buffer)
        guard input.readableBytes <= 32768 else { context.close(promise: nil); return }
        while true {
            switch stage {
            case 0:
                guard input.readBytes(length: 12) != nil else { return }
                send([1, 30], context); stage = 1
            case 1:
                guard let choice: UInt8 = input.readInteger() else { return }
                guard choice == 30 else { context.close(promise: nil); return }
                // RFC 2409 1024-bit group; server exponent one, disposable test only.
                let hex = "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE65381FFFFFFFFFFFFFFFF"
                let prime = stride(from: 0, to: hex.count, by: 2).map { i -> UInt8 in
                    let start = hex.index(hex.startIndex, offsetBy: i)
                    return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
                }
                send([0, 2, 0, 128] + prime + [UInt8](repeating: 0, count: 127) + [2], context); stage = 2
            case 2:
                guard input.readBytes(length: 256) != nil else { return }
                record.add("ardExchange"); send([0, 0, 0, 0], context); stage = 3
            case 3:
                guard input.readBytes(length: 1) != nil else { return }
                let name = Array("Synthetic Desktop".utf8)
                send([1, 0, 0, 128, 32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0,
                      0, 0, 0, UInt8(name.count)] + name, context); stage = 4
            default:
                guard let kind: UInt8 = input.getInteger(at: input.readerIndex) else { return }
                let count: Int
                switch kind {
                case 0: count = 20
                case 2:
                    guard let encodings: UInt16 = input.getInteger(at: input.readerIndex + 2) else { return }
                    count = 4 + Int(encodings) * 4
                case 3: count = 10
                case 4: count = 8
                case 5: count = 6
                case 6:
                    guard let length: UInt32 = input.getInteger(at: input.readerIndex + 4) else { return }
                    guard length <= 16384 else { context.close(promise: nil); return }; count = 8 + Int(length)
                default: context.close(promise: nil); return
                }
                guard let bytes = input.readBytes(length: count) else { return }
                if kind == 3 {
                    record.add("update")
                    // 256 x 128 raw BGRA image, with a distinct synthetic color.
                    var frame: [UInt8] = [0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 128, 0, 0, 0, 0]
                    for _ in 0..<32768 { frame += [180, 90, 30, 0] }
                    send(frame, context)
                } else if kind == 4 { record.add(bytes[1] == 0 ? "keyUp" : "keyDown") }
                else if kind == 5 { record.add(bytes[1] == 0 ? "pointerUp" : "pointerDown") }
            }
            input.discardReadBytes()
        }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}
private final class DesktopSSHServer: @unchecked Sendable {
    enum Mode: Sendable { case echo, rfb, denied, silent }
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let key = NIOSSHPrivateKey(ed25519Key: .init())
    let record = DesktopSSHRecord()
    let mode: Mode
    let screenPort: Int
    var listener: Channel!
    private var clients: [Channel] = [] // Sole server event loop.
    init(_ mode: Mode, screenPort: Int = 5900) { self.mode = mode; self.screenPort = screenPort }
    var port: Int { listener.localAddress!.port! }
    var hostKey: String { String(openSSHPublicKey: key.publicKey) }
    func start() async throws {
        listener = try await ServerBootstrap(group: group).childChannelInitializer { [self] channel in
            clients.append(channel); record.add("tcp")
            if mode == .silent { return channel.eventLoop.makeSucceededFuture(()) }
            let handler = NIOSSHHandler(role: .server(.init(hostKeys: [key], userAuthDelegate: DesktopSSHAuth(record))),
                allocator: channel.allocator, inboundChildChannelInitializer: { [self] child, type in
                    guard mode != .denied, case .directTCPIP(let request) = type,
                          request.targetHost == "127.0.0.1", request.targetPort == screenPort else {
                        return child.eventLoop.makeFailedFuture(DesktopSSHFailure.forwarding)
                    }
                    record.add("forward")
                    return mode == .echo ? child.pipeline.addHandler(DesktopSSHEcho()) : child.pipeline.addHandler(DesktopSyntheticRFB(record))
                })
            return channel.pipeline.addHandler(handler)
        }.bind(host: "127.0.0.1", port: 0).get()
    }
    func activeClients() async throws -> Int { try await group.next().submit { self.clients.filter(\.isActive).count }.get() }
    func disconnectClients() async throws {
        for client in try await group.next().submit({ self.clients }).get() { try? await client.close().get() }
    }
    func close() async throws { try await disconnectClients(); try await listener.close().get(); try await group.shutdownGracefully() }
}
private func desktopWriterFinished(_ group: DispatchGroup) -> Bool { group.wait(timeout: .now() + 6) == .success }

@MainActor final class DesktopSSHTransportTests: XCTestCase {
    private func wait(_ label: String, _ predicate: () -> Bool) async throws {
        for _ in 0..<400 { if predicate() { return }; try await Task.sleep(for: .milliseconds(25)) }
        XCTFail(label); throw POSIXError(.ETIMEDOUT)
    }
    private func open(_ server: DesktopSSHServer, password: String = "synthetic-only") async throws -> DirectDesktopSSHTunnel {
        let trusted = server.hostKey
        return try await DirectDesktopSSHTunnel.open(addresses: ["127.0.0.1"], sshPort: server.port, screenSharingPort: server.screenPort,
            username: "synthetic", password: password, validateHost: { key in
                guard key == trusted else { throw TerminalSecretStore.Failure.changedKey }
            })
    }
    func testBoundedEncryptedBridgePreservesFourMiBAndCloses() async throws {
        let server = DesktopSSHServer(.echo); try await server.start()
        do {
            let tunnel = try await open(server), fd = tunnel.takeSocket()
            let valid = await Task.detached {
                var timeout = timeval(tv_sec: 5, tv_usec: 0)
                _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                let count = 4 * 1024 * 1024, group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    var buffer = [UInt8](repeating: 0x5a, count: 16384), sent = 0
                    while sent < count {
                        for i in buffer.indices { buffer[i] = UInt8((sent + i) % 251) }
                        let n = Darwin.write(fd, &buffer, buffer.count)
                        if n < 0 && errno == EINTR { continue }; if n <= 0 { break }; sent += n
                    }
                    group.leave()
                }
                var received = 0, valid = true, buffer = [UInt8](repeating: 0, count: 16384)
                while received < count {
                    let n = Darwin.read(fd, &buffer, buffer.count)
                    if n < 0 && errno == EINTR { continue }; if n <= 0 { valid = false; break }
                    for i in 0..<n where buffer[i] != UInt8((received + i) % 251) { valid = false }; received += n
                }
                let finished = desktopWriterFinished(group)
                Darwin.close(fd); return finished && valid && received == count
            }.value
            XCTAssertTrue(valid)
            let counts = try await tunnel.counts()
            XCTAssertEqual(counts.outbound, 4 * 1024 * 1024); XCTAssertEqual(counts.inbound, 4 * 1024 * 1024)
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
            let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let policy = try XCTUnwrap(fixture["sshTransportPolicy"] as? [String: Any])
            XCTAssertEqual(DesktopSSHRelay.limit, policy["queueLimitBytes"] as? Int)
            XCTAssertLessThanOrEqual(counts.peak, DesktopSSHRelay.limit)
            XCTAssertEqual(policy["plaintextFallback"] as? Bool, false)
            await tunnel.close(); await tunnel.close()
            XCTAssertFalse(tunnel.bridge.isActive); XCTAssertFalse(tunnel.remote.isActive)
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testIdentityRejectionHappensBeforePasswordOrForwarding() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for row in try XCTUnwrap(fixture["sshTransportCases"] as? [[String: Any]]) {
            let server = DesktopSSHServer(.echo); try await server.start()
            let accept = row["authenticate"] as? Bool == true
            do {
                let tunnel = try await DirectDesktopSSHTunnel.open(addresses: ["127.0.0.1"], sshPort: server.port,
                    screenSharingPort: 5900, username: "synthetic", password: "synthetic-only", validateHost: { _ in
                        if !accept { throw TerminalSecretStore.Failure.rejectedKey }
                    })
                await tunnel.close(); XCTAssertTrue(accept)
            } catch { XCTAssertFalse(accept) }
            XCTAssertEqual(server.record.count("auth"), accept ? 1 : 0)
            XCTAssertEqual(server.record.count("forward"), accept ? 1 : 0)
            try await server.close()
        }
    }
    func testCustomScreenSharingPortUsesTheSameFixedLoopbackForward() async throws {
        let server = DesktopSSHServer(.echo, screenPort: 5902); try await server.start()
        let tunnel = try await open(server)
        XCTAssertEqual(server.record.count("forward"), 1)
        await tunnel.close(); try await server.close()
    }
    func testWrongLoginAndDeniedForwardingHaveActionableStages() async throws {
        for mode in [DesktopSSHServer.Mode.echo, .denied] {
            let server = DesktopSSHServer(mode); try await server.start()
            do { let tunnel = try await open(server, password: mode == .echo ? "wrong-synthetic" : "synthetic-only"); await tunnel.close(); XCTFail("Must fail closed") }
            catch { XCTAssertEqual(DirectDesktopSSHTunnel.failureStage(error), mode == .echo ? 111 : 114) }
            XCTAssertEqual(server.record.count("tcp"), 1); XCTAssertEqual(server.record.count("forward"), 0)
            try await server.close()
        }
        let viewer = CompanionVNCViewer(); viewer.servicePort = 5900; viewer.sshPort = 2222; viewer.loadViewIfNeeded()
        viewer.showConnectionFailureStage(10)
        let details = try XCTUnwrap(viewer.value(forKey: "loginIssueDetails") as? String)
        XCTAssertTrue(details.contains("Remote Login (SSH)")); XCTAssertTrue(details.contains("Port: 2222"))
        viewer.stop()
    }
    func testCancellationDuringHandshakeClosesParent() async throws {
        let server = DesktopSSHServer(.silent); try await server.start()
        let opening = Task { try await open(server) }
        try await wait("SSH connected before cancellation") { server.record.count("tcp") == 1 }
        opening.cancel()
        do { let tunnel = try await opening.value; await tunnel.close(); XCTFail("Cancelled handshake connected") } catch {}
        let active = try await server.activeClients(); XCTAssertEqual(active, 0)
        try await server.close()
    }
    func testOversizedRelayClosesBothEndpointsAndParentDisconnectClosesConsumer() async throws {
        let server = DesktopSSHServer(.echo); try await server.start()
        let tunnel = try await open(server), fd = tunnel.takeSocket()
        try await tunnel.bridge.eventLoop.submit {
            var buffer = ByteBufferAllocator().buffer(capacity: DesktopSSHRelay.limit + 1)
            buffer.writeRepeatingByte(0, count: DesktopSSHRelay.limit + 1)
            tunnel.bridge.pipeline.fireChannelRead(NIOAny(buffer))
        }.get()
        try? await tunnel.bridge.closeFuture.get(); try? await tunnel.remote.closeFuture.get()
        XCTAssertFalse(tunnel.bridge.isActive); XCTAssertFalse(tunnel.remote.isActive)
        var byte: UInt8 = 0; XCTAssertEqual(Darwin.read(fd, &byte, 1), 0); Darwin.close(fd)
        await tunnel.close(); try await server.close()
        let next = DesktopSSHServer(.echo); try await next.start()
        let other = try await open(next), socket = other.takeSocket()
        try await next.disconnectClients(); try? await other.bridge.closeFuture.get()
        XCTAssertFalse(other.bridge.isActive); XCTAssertFalse(other.remote.isActive)
        XCTAssertEqual(Darwin.read(socket, &byte, 1), 0); Darwin.close(socket)
        await other.close(); try await next.close()
    }
    func testFirstUseTrustApprovalCancellationAndChangedKeyInNormalCoordinator() async throws {
        for scenario in ["approve", "reject", "cancel", "lost", "changed"] {
            let server = DesktopSSHServer(.rfb); try await server.start()
            let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["127.0.0.1"], sshPort: server.port)
            let terminalLogin = TerminalSecretStore.Login(username: "separate-terminal", password: "separate-synthetic")
            try TerminalSecretStore.save(terminalLogin, id: mac.id)
            if scenario == "changed" {
                let other = NIOSSHPrivateKey(ed25519Key: .init())
                try TerminalSecretStore.write(Data(String(openSSHPublicKey: other.publicKey).utf8), id: mac.id, kind: "host-key")
            }
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let prior = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
            let viewer = CompanionVNCViewer(), coordinator = VNCRemoteDesktopView.Coordinator(mac: mac)
            viewer.macName = mac.name; viewer.sshPort = mac.sshPort; coordinator.viewer = viewer
            viewer.connectHandler = { user, password, remember in MainActor.assumeIsolated { coordinator.connect(user: user, password: password, remember: remember) } }
            viewer.disconnectHandler = { MainActor.assumeIsolated { coordinator.disconnect() } }
            window.rootViewController = viewer; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
            (viewer.value(forKey: "username") as? UITextField)?.text = "synthetic"
            (viewer.value(forKey: "password") as? UITextField)?.text = "synthetic-only"
            _ = viewer.perform(NSSelectorFromString("start"))
            do {
                if scenario == "changed" {
                    try await wait("changed identity recovery is shown") { (viewer.value(forKey: "loginIssueDetails") as? String)?.contains("Stage: 112") == true }
                } else {
                    try await wait("first-use fingerprint is visible before login") { viewer.presentedViewController != nil }
                    XCTAssertEqual(server.record.count("auth"), 0)
                    XCTAssertNil(try TerminalSecretStore.hostKey(mac.id))
                    if scenario == "cancel" || scenario == "reject" || scenario == "lost" {
                        if scenario == "lost" { try await server.disconnectClients() }
                        else if scenario == "cancel" { coordinator.disconnect() }
                        else { coordinator.answerTrust(false) }
                        try await wait("cancel dismisses pending verification") { viewer.presentedViewController == nil }
                        coordinator.answerTrust(true) // A late answer cannot save a cancelled pin.
                        XCTAssertNil(try TerminalSecretStore.hostKey(mac.id))
                    } else {
                        XCTAssertNotNil(viewer.presentedViewController)
                        try await Task.sleep(for: .milliseconds(500)); window.layoutIfNeeded()
                        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                        let attachment = XCTAttachment(image: image); attachment.name = "SSH-first-use-verification"; attachment.lifetime = .keepAlways; add(attachment)
                        coordinator.answerTrust(true)
                        try await wait("explicit approval permits the normal native owner") { viewer.session.connected }
                        XCTAssertEqual(try TerminalSecretStore.hostKey(mac.id), server.hostKey)
                    }
                }
                XCTAssertEqual(server.record.count("auth"), scenario == "approve" ? 1 : 0)
                XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.username, terminalLogin.username)
                XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.password, terminalLogin.password)
                coordinator.disconnect(); try await server.close()
            } catch { coordinator.disconnect(); try? await server.close(); window.isHidden = true; window.rootViewController = nil; prior?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id); throw error }
            window.isHidden = true; window.rootViewController = nil; prior?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id)
        }
    }
    func testNormalDesktopAndTrackpadViewsRenderAndReleaseInputOverSSH() async throws {
        for inputOnly in [false, true] {
            let server = DesktopSSHServer(.rfb); try await server.start()
            let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["127.0.0.1"], sshPort: server.port)
            try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let prior = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
            let viewer = CompanionVNCViewer(), coordinator = VNCRemoteDesktopView.Coordinator(mac: mac)
            viewer.macName = mac.name; viewer.inputOnly = inputOnly; viewer.sshPort = mac.sshPort; viewer.servicePort = mac.port
            coordinator.viewer = viewer
            viewer.connectHandler = { user, password, remember in MainActor.assumeIsolated { coordinator.connect(user: user, password: password, remember: remember) } }
            viewer.disconnectHandler = { MainActor.assumeIsolated { coordinator.disconnect() } }
            window.rootViewController = viewer; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
            (viewer.value(forKey: "username") as? UITextField)?.text = "synthetic"
            (viewer.value(forKey: "password") as? UITextField)?.text = "synthetic-only"
            _ = viewer.perform(NSSelectorFromString("start"))
            do {
                try await wait("native desktop becomes ready through SSH") { viewer.session.connected }
                try await wait("normal view presents framebuffer") { viewer.value(forKey: "lastFramebuffer") != nil }
                XCTAssertEqual(server.record.count("auth"), 1); XCTAssertEqual(server.record.count("forward"), 1)
                XCTAssertEqual(server.record.count("ardExchange"), 1)
                viewer.session.key(0xffe3, down: true)
                _ = viewer.session.tryClickX(20, y: 20, mask: 1)
                try await wait("ordered native input reaches encrypted channel") { server.record.count("keyDown") > 0 && server.record.count("pointerDown") > 0 }
                viewer.session.pause { server.record.add("paused") }
                try await wait("balanced native input pause completes") { server.record.count("paused") == 1 }
                try await wait("held modifiers release through same SSH channel") { server.record.count("keyUp") > 0 }
                viewer.session.resume()
                try await wait("same owner resumes") { viewer.session.connected }
                XCTAssertEqual(server.record.count("tcp"), 1)
                try await wait("connected UI dismisses sign-in progress") {
                    (viewer.value(forKey: "loginScroll") as? UIScrollView)?.isHidden == true &&
                    (viewer.value(forKey: "starting") as? Bool) == false
                }
                try await Task.sleep(for: .milliseconds(500)); window.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let attachment = XCTAttachment(image: image); attachment.name = inputOnly ? "SSH-synthetic-trackpad" : "SSH-synthetic-desktop"; attachment.lifetime = .keepAlways; add(attachment)
                coordinator.disconnect()
                try await wait("native owner closes") { !viewer.session.running }
                for _ in 0..<100 { if try await server.activeClients() == 0 { break }; try await Task.sleep(for: .milliseconds(25)) }
                let remaining = try await server.activeClients(); XCTAssertEqual(remaining, 0)
                try await server.close()
            } catch { coordinator.disconnect(); try? await server.close(); window.isHidden = true; window.rootViewController = nil; prior?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id); throw error }
            window.isHidden = true; window.rootViewController = nil; prior?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id)
        }
    }
}
