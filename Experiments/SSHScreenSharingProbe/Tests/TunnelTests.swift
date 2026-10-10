import XCTest
import Crypto
import Darwin
import Citadel
import NIO
import NIOSSH
import NIOEmbedded
@testable import Tunnel

private final class TestAuth: NIOSSHServerUserAuthenticationDelegate {
    var requests = 0
    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { .password }
    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        requests += 1
        if request.username == "synthetic", case .password(let password) = request.request, password.password == "synthetic-test" {
            responsePromise.succeed(.success)
        } else { responsePromise.succeed(.failure) }
    }
}
private final class EchoSSH: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.writeAndFlush(data, promise: nil)
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}
private final class TestServer {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let key = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
    let auth = TestAuth()
    var listener: Channel!
    var accepted: [Channel] = [] // Access only on the group's sole event loop.
    var forwarded = 0
    var port: Int { listener.localAddress!.port! }
    var trusted: String { String(openSSHPublicKey: key.publicKey) }
    func start() async throws {
        listener = try await ServerBootstrap(group: group).childChannelInitializer { [self] channel in
            accepted.append(channel)
            let handler = NIOSSHHandler(role: .server(.init(hostKeys: [key], userAuthDelegate: auth)),
                allocator: channel.allocator, inboundChildChannelInitializer: { [self] child, type in
                    guard case .directTCPIP(let request) = type, request.targetHost == "127.0.0.1", request.targetPort == 5900 else {
                        return child.eventLoop.makeFailedFuture(ProbeFailure.unexpectedChannel)
                    }
                    forwarded += 1
                    return child.pipeline.addHandler(EchoSSH())
                })
            return channel.pipeline.addHandler(handler)
        }.bind(host: "127.0.0.1", port: 0).get()
    }
    func disconnectClients() async throws {
        let clients = try await group.next().submit { self.accepted }.get()
        for client in clients { try? await client.close() }
    }
    func close() async throws {
        try await disconnectClients(); try await listener.close()
        try await group.shutdownGracefully()
    }
}
final class TunnelTests: XCTestCase {
    func testCancellationDuringSilentSSHHandshakeClosesParent() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        var accepted: Channel?
        let listener = try await ServerBootstrap(group: group).childChannelInitializer { channel in
            accepted = channel; return channel.eventLoop.makeSucceededFuture(())
        }.bind(host: "127.0.0.1", port: 0).get()
        let opening = Task {
            try await SSHTunnel.open(sshPort: listener.localAddress!.port!, username: "synthetic", password: "synthetic-test", trustedKeys: [])
        }
        for _ in 0 ..< 100 {
            if try await group.next().submit({ accepted != nil }).get() { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        opening.cancel()
        do { let tunnel = try await opening.value; await tunnel.close(); XCTFail("Cancelled handshake cannot connect") } catch {}
        let connection = try await group.next().submit { accepted }.get()
        XCTAssertNotNil(connection)
        if let connection { try await connection.closeFuture.get(); XCTAssertFalse(connection.isActive) }
        try await listener.close(); try await group.shutdownGracefully()
    }
    func testEncryptedForwardingPreservesSyntheticBytesAndCloses() async throws {
        let server = TestServer(); try await server.start()
        do {
            let tunnel = try await SSHTunnel.open(sshPort: server.port, username: "synthetic", password: "synthetic-test", trustedKeys: [server.trusted])
            let fd = tunnel.takeSocket()
            let result = await Task.detached { () -> Bool in
                var timeout = timeval(tv_sec: 5, tv_usec: 0)
                _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                // Larger than socket buffers and both SSH windows; exercises flow control.
                let expected = (0 ..< 4 * 1024 * 1024).map { UInt8(truncatingIfNeeded: $0) }
                let writer = DispatchGroup(); writer.enter()
                DispatchQueue.global().async {
                    expected.withUnsafeBytes { bytes in
                        var offset = 0
                        while offset < bytes.count {
                            let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), min(16384, bytes.count - offset))
                            if n < 0 && errno == EINTR { continue }
                            if n <= 0 { break }; offset += n
                        }
                    }
                    writer.leave()
                }
                var received = 0, valid = true, buffer = [UInt8](repeating: 0, count: 16384)
                while received < expected.count {
                    let n = Darwin.read(fd, &buffer, buffer.count)
                    if n < 0 && errno == EINTR { continue }
                    if n <= 0 { valid = false; break }
                    for i in 0 ..< n where buffer[i] != UInt8(truncatingIfNeeded: received + i) { valid = false }
                    received += n
                }
                let done = writer.wait(timeout: .now() + 6) == .success
                Darwin.close(fd)
                return valid && done && received == expected.count
            }.value
            XCTAssertTrue(result)
            let counts = try await tunnel.counts()
            XCTAssertEqual(counts.outbound, 4 * 1024 * 1024)
            XCTAssertEqual(counts.inbound, 4 * 1024 * 1024)
            XCTAssertLessThanOrEqual(counts.peak, BoundedRelay.limit)
            await tunnel.close(); await tunnel.close()
            XCTAssertFalse(tunnel.bridge.isActive); XCTAssertFalse(tunnel.remote.isActive); XCTAssertFalse(tunnel.client.isConnected)
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testChangedHostKeyRejectsBeforeAuthenticationOrForwarding() async throws {
        let server = TestServer(); try await server.start()
        let wrong = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        do {
            let tunnel = try await SSHTunnel.open(sshPort: server.port, username: "synthetic", password: "synthetic-test",
                trustedKeys: [String(openSSHPublicKey: wrong.publicKey)])
            await tunnel.close(); XCTFail("A changed host identity must fail closed")
        } catch {}
        let observed = try await server.group.next().submit { (server.auth.requests, server.forwarded) }.get()
        XCTAssertEqual(observed.0, 0); XCTAssertEqual(observed.1, 0)
        try await server.close()
    }
    func testParentDisconnectClosesConsumerSocket() async throws {
        let server = TestServer(); try await server.start()
        let tunnel = try await SSHTunnel.open(sshPort: server.port, username: "synthetic", password: "synthetic-test", trustedKeys: [server.trusted])
        let fd = tunnel.takeSocket()
        try await server.disconnectClients()
        await tunnel.close()
        var byte: UInt8 = 0
        XCTAssertEqual(Darwin.read(fd, &byte, 1), 0)
        Darwin.close(fd); try await server.close()
    }
    func testOversizedBufferClosesBothBridgeEndpoints() throws {
        let loop = EmbeddedEventLoop(), pair = BoundedRelay.pair()
        let first = EmbeddedChannel(handler: pair.0, loop: loop), second = EmbeddedChannel(handler: pair.1, loop: loop)
        var buffer = ByteBufferAllocator().buffer(capacity: BoundedRelay.limit + 1)
        buffer.writeRepeatingByte(0, count: BoundedRelay.limit + 1)
        _ = try first.writeInbound(buffer)
        XCTAssertFalse(first.isActive); XCTAssertFalse(second.isActive)
        _ = try first.finish(acceptAlreadyClosed: true); _ = try second.finish(acceptAlreadyClosed: true)
    }
}
