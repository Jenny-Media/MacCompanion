import XCTest
import Foundation
import Darwin
@testable import Mac_Companion
import Crypto
@preconcurrency import NIO
@preconcurrency import NIOSSH
@preconcurrency import Citadel

// Manual, synthetic SSH-only comparison. Never linked into application targets.
private final class WindowProbeAuth: NIOSSHServerUserAuthenticationDelegate, @unchecked Sendable {
    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { .password }
    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        if request.username == "synthetic", case .password(let auth) = request.request, auth.password == "synthetic-only" {
            responsePromise.succeed(.success)
        } else { responsePromise.succeed(.failure) }
    }
}
private final class WindowProbeHostValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let trusted: String
    init(_ trusted: String) { self.trusted = trusted }
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        if String(openSSHPublicKey: hostKey) == trusted { validationCompletePromise.succeed(()) }
        else { validationCompletePromise.fail(ChannelError.inappropriateOperationForState) }
    }
}
private final class WindowProbeDelay: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    private var context: ChannelHandlerContext?
    func handlerAdded(context: ChannelHandlerContext) { self.context = context }
    func handlerRemoved(context: ChannelHandlerContext) { self.context = nil }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let bytes = unwrapInboundIn(data)
        context.eventLoop.scheduleTask(in: .milliseconds(25)) { [self] in
            self.context?.fireChannelRead(self.wrapInboundOut(bytes))
            self.context?.fireChannelReadComplete()
        }
    }
    func channelReadComplete(context: ChannelHandlerContext) {}
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let bytes = unwrapOutboundIn(data)
        context.eventLoop.scheduleTask(in: .milliseconds(25)) { [self] in
            guard let context = self.context else { promise?.fail(ChannelError.ioOnClosedChannel); return }
            context.writeAndFlush(self.wrapOutboundOut(bytes), promise: promise)
        }
    }
    func flush(context: ChannelHandlerContext) {}
}
private final class WindowProbeSource: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData
    func channelActive(context: ChannelHandlerContext) {
        for _ in 0..<256 {
            let bytes = ByteBuffer(repeating: 0x5a, count: 16 * 1024)
            context.write(wrapOutboundOut(.init(type: .channel, data: .byteBuffer(bytes))), promise: nil)
        }
        context.flush(); context.fireChannelActive()
    }
}
private final class WindowProbeSink: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    let completed: EventLoopPromise<Int>
    private var count = 0
    init(_ completed: EventLoopPromise<Int>) { self.completed = completed }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let bytes = unwrapInboundIn(data)
        guard bytes.readableBytesView.allSatisfy({ $0 == 0x5a }) else { completed.fail(ChannelError.inappropriateOperationForState); return }
        count += bytes.readableBytes
        if count == 4 * 1024 * 1024 { completed.succeed(count) }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { completed.fail(error); context.close(promise: nil) }
}
private final class WindowProbeServer: @unchecked Sendable {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let key = NIOSSHPrivateKey(ed25519Key: .init())
    private var clients: [Channel] = []
    var listener: Channel!
    func start() async throws {
        listener = try await ServerBootstrap(group: group).childChannelInitializer { [self] channel in
            clients.append(channel)
            let ssh = NIOSSHHandler(role: .server(.init(hostKeys: [key], userAuthDelegate: WindowProbeAuth())), allocator: channel.allocator,
                inboundChildChannelInitializer: { child, type in
                    guard case .directTCPIP(let request) = type, request.targetHost == "127.0.0.1", request.targetPort == 5900 else {
                        return child.eventLoop.makeFailedFuture(ChannelError.inappropriateOperationForState)
                    }
                    return child.pipeline.addHandler(WindowProbeSource())
                })
            return channel.pipeline.addHandler(WindowProbeDelay()).flatMap { channel.pipeline.addHandler(ssh) }
        }.bind(host: "127.0.0.1", port: 0).get()
    }
    func close() async throws {
        let channels = try await group.next().submit { self.clients }.get()
        for channel in channels { try? await channel.close() }
        try? await listener.close(); try await group.shutdownGracefully()
    }
}
@MainActor final class SSHWindowLatencyTests: XCTestCase {
    func testApplicationTunnelOnTheSameControlledLink() async throws {
        let server = WindowProbeServer(); try await server.start()
        let trusted = String(openSSHPublicKey: server.key.publicKey)
        do {
            let tunnel = try await DirectDesktopSSHTunnel.open(addresses: ["127.0.0.1"], sshPort: server.listener.localAddress!.port!,
                screenSharingPort: 5900, username: "synthetic", password: "synthetic-only", validateHost: { value in
                    guard value == trusted else { throw ChannelError.inappropriateOperationForState }
                })
            let fd = tunnel.takeSocket(), started = ProcessInfo.processInfo.systemUptime
            let count = await Task.detached {
                var timeout = timeval(tv_sec: 10, tv_usec: 0)
                _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var count = 0, buffer = [UInt8](repeating: 0, count: 16384)
                while count < 4 * 1024 * 1024 {
                    let n = Darwin.read(fd, &buffer, buffer.count)
                    if n < 0 && errno == EINTR { continue }
                    if n <= 0 { break }
                    guard buffer.prefix(n).allSatisfy({ $0 == 0x5a }) else { break }; count += n
                }
                Darwin.close(fd); return count
            }.value
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            let diagnostic = try await tunnel.diagnosticCounters()
            print("SSH_APPLICATION_WINDOW_PROBE " + String(decoding: try JSONSerialization.data(withJSONObject:
                ["bytes": Double(count), "elapsedMS": elapsed, "peakQueuedBytes": diagnostic["inboundPeakQueuedBytes"] ?? -1], options: [.sortedKeys]), as: UTF8.self))
            XCTAssertEqual(count,4 * 1024 * 1024)
            XCTAssertLessThanOrEqual(diagnostic["inboundPeakQueuedBytes"] ?? .infinity, Double(DesktopSSHRelay.limit))
            await tunnel.close(); try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testControlledFiftyMillisecondLinkComparesBoundedReceiveWindows() async throws {
        var results = [[String: Double]]()
        for size in [128 * 1024, 256 * 1024, 1024 * 1024] {
            let server = WindowProbeServer(); try await server.start()
            let trusted = String(openSSHPublicKey: server.key.publicKey)
            var settings = SSHClientSettings(host: "127.0.0.1", port: server.listener.localAddress!.port!,
                authenticationMethod: { .passwordBased(username: "synthetic", password: "synthetic-only") },
                hostKeyValidator: .custom(WindowProbeHostValidator(trusted)))
            settings.protocolOptions = [.maximumPacketSize(size)]
            settings.connectTimeout = .seconds(10)
            let client = try await SSHClient.connect(to: settings)
            let complete = client.eventLoop.makePromise(of: Int.self)
            let timeout = client.eventLoop.scheduleTask(in: .seconds(20)) { complete.fail(ChannelError.connectTimeout(.seconds(20))) }
            let started = ProcessInfo.processInfo.systemUptime
            do {
                let channel = try await client.createDirectTCPIPChannel(using: .init(targetHost: "127.0.0.1", targetPort: 5900,
                    originatorAddress: try SocketAddress(ipAddress: "127.0.0.1", port: 0))) { @Sendable child in
                    child.pipeline.addHandler(WindowProbeSink(complete))
                }
                let bytes = try await complete.futureResult.get()
                let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
                results.append(["receiveWindowBytes": Double(size), "bytes": Double(bytes), "elapsedMS": elapsed])
                timeout.cancel(); try? await channel.close(); try? await client.close(); try await server.close()
            } catch {
                timeout.cancel(); try? await client.close(); try? await server.close(); throw error
            }
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        print("SSH_WINDOW_LATENCY_PROBE " + String(decoding: data, as: UTF8.self))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json"); attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertGreaterThan(results[0]["elapsedMS"]!, results[2]["elapsedMS"]! * 1.5)
    }
}
