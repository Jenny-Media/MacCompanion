import XCTest
import UIKit
import SwiftUI
import Crypto
@preconcurrency import NIO
@preconcurrency import NIOSSH
@preconcurrency import Citadel
import Darwin
@testable import Mac_Companion

@MainActor private final class DesktopOpeningInterruptionViewer: CompanionVNCViewer {
    var openingHook: (() -> Void)?
    override func showConnectionProgress(_ message: String) {
        super.showConnectionProgress(message)
        if message == "Opening encrypted connection…", let hook = openingHook { openingHook = nil; hook() }
    }
}

/// Generated interoperability workload, never an additional golden corpus.
/// SSH authenticates a synthetic account. The RFB peer completes ARD's client
/// exchange but does not claim to validate macOS account authentication.
private final class DesktopSSHRecord: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [String: Int]()
    func add(_ key: String, by amount: Int = 1) { lock.lock(); values[key, default: 0] += amount; lock.unlock() }
    func count(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return values[key, default: 0] }
}
/// Holds a write completion without making the channel itself unwritable.
/// A read counter lets the test distinguish local backpressure from a reverse
/// direction being incorrectly stalled by that held completion.
private final class DesktopHeldRelayWrites: ChannelOutboundHandler, @unchecked Sendable {
    typealias OutboundIn = ByteBuffer
    private var completions: [EventLoopPromise<Void>] = []
    private(set) var reads = 0
    private let forwardReads: Bool
    init(forwardReads: Bool = false) { self.forwardReads = forwardReads }
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        if let promise { completions.append(promise) }
    }
    func read(context: ChannelHandlerContext) {
        reads += 1
        if forwardReads { context.read() }
    }
    func releaseWrites() {
        let pending = completions; completions.removeAll()
        for promise in pending { promise.succeed(()) }
    }
    func handlerRemoved(context: ChannelHandlerContext) { releaseWrites() }
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
    let record: DesktopSSHRecord
    init(_ record: DesktopSSHRecord) { self.record = record }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case .byteBuffer(let bytes) = unwrapInboundIn(data).data { record.add("echoBytes", by: bytes.readableBytes) }
        context.writeAndFlush(data, promise: nil)
    }
}
private final class DesktopSyntheticRFB: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData
    let record: DesktopSSHRecord
    private var input = ByteBuffer()
    private var stage = 0
    private let cursorPackets: [[UInt8]]
    private var sentCursorPackets = false
    private var sentDisplayLayout = false
    init(_ record: DesktopSSHRecord, cursorPackets: [[UInt8]] = []) { self.record = record; self.cursorPackets = cursorPackets }
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
                case 9: count = 16 // Apple automatic framebuffer delivery, enabled after valid layout metadata.
                case 6:
                    guard let length: UInt32 = input.getInteger(at: input.readerIndex + 4) else { return }
                    guard length <= 16384 else { context.close(promise: nil); return }; count = 8 + Int(length)
                default: context.close(promise: nil); return
                }
                guard let bytes = input.readBytes(length: count) else { return }
                if kind == 2 {
                    for offset in stride(from: 4, to: bytes.count, by: 4) {
                        let encoding = bytes[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                        record.add("encoding.\(Int32(bitPattern: encoding))")
                    }
                } else if kind == 3 {
                    record.add("update")
                    if !sentDisplayLayout && record.count("encoding.1105") > 0 {
                        sentDisplayLayout = true
                        // Generated single-monitor metadata for this synthetic
                        // 256 x 128 desktop; not another mutable fixture corpus.
                        var body = [UInt8](repeating: 0, count: 76)
                        func put16(_ offset: Int, _ value: UInt16) { body[offset] = UInt8(value >> 8); body[offset + 1] = UInt8(value & 255) }
                        put16(0, 5); put16(2, 128); put16(4, 64); put16(6, 256); put16(8, 128); put16(18, 1)
                        body[13] = 5; body[39] = 5
                        put16(44, 64); put16(46, 128); put16(52, 128); put16(54, 256)
                        send([0, 0, 0, 1] + [0, 0, 0, 0, 1, 0, 0, 128] + [0, 0, 4, 81] + [0, 76] + body, context)
                    }
                    // 256 x 128 raw BGRA image, with a distinct synthetic color.
                    var frame: [UInt8] = [0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 128, 0, 0, 0, 0]
                    for _ in 0..<32768 { frame += [180, 90, 30, 0] }
                    send(frame, context)
                    if !sentCursorPackets && !cursorPackets.isEmpty {
                        sentCursorPackets = true
                        for packet in cursorPackets { send(packet, context) }
                        record.add("cursorPacketsSent")
                    }
                } else if kind == 9 { record.add(bytes[4...7].allSatisfy { $0 == 0 } ? "automaticUpdatesStart" : "automaticUpdatesStop") }
                else if kind == 4 { record.add(bytes[1] == 0 ? "keyUp" : "keyDown") }
                else if kind == 5 { record.add(bytes[1] == 0 ? "pointerUp" : "pointerDown") }
            }
            input.discardReadBytes()
        }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}
// A real SSH peer delays cleanup after forwarded EOF, exposing a parent that
// closes before the old Screen Sharing socket has finished retiring.
private final class DesktopRetiringPeer: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    let record: DesktopSSHRecord
    let responds: Bool
    init(_ record: DesktopSSHRecord, responds: Bool) { self.record = record; self.responds = responds }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, case .inputClosed = event {
            record.add("forwardedEOF")
            if responds {
                let channel = context.channel, record = record
                context.eventLoop.scheduleTask(in: .milliseconds(80)) {
                    record.add(channel.isActive ? "peerCleanup" : "prematureParentClose")
                    channel.close(promise: nil)
                }
            }
        } else { context.fireUserInboundEventTriggered(event) }
    }
}
private final class DesktopSSHServer: @unchecked Sendable {
    enum Mode: Sendable { case echo, rfb, denied, silent, retiring, stalledRetirement }
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let key = NIOSSHPrivateKey(ed25519Key: .init())
    let record = DesktopSSHRecord()
    let mode: Mode
    let screenPort: Int
    let cursorPackets: [[UInt8]]
    var listener: Channel!
    private var clients: [Channel] = [] // Sole server event loop.
    init(_ mode: Mode, screenPort: Int = 5900, cursorPackets: [[UInt8]] = []) { self.mode = mode; self.screenPort = screenPort; self.cursorPackets = cursorPackets }
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
                    if self.mode == .retiring || self.mode == .stalledRetirement {
                        return child.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).flatMap {
                            child.pipeline.addHandler(DesktopRetiringPeer(self.record, responds: self.mode == .retiring))
                        }
                    }
                    return child.getOption(SSHChildChannelOptions.peerMaximumMessageLength).flatMap { maximum in
                        self.record.add("peerPacket.\(maximum)")
                        return self.mode == .echo ? child.pipeline.addHandler(DesktopSSHEcho(self.record)) : child.pipeline.addHandler(DesktopSyntheticRFB(self.record, cursorPackets: self.cursorPackets))
                    }
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
            let diagnostics = try await tunnel.diagnosticCounters()
            XCTAssertEqual(diagnostics["outboundBytes"], Double(counts.outbound))
            XCTAssertEqual(diagnostics["inboundBytes"], Double(counts.inbound))
            for key in ["outboundQueuedBytes", "inboundQueuedBytes", "outboundPeakQueuedBytes", "inboundPeakQueuedBytes"] {
                let value = try XCTUnwrap(diagnostics[key]); XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, Double(DesktopSSHRelay.limit))
            }
            for key in ["outboundWriteMaxMS", "inboundWriteMaxMS"] {
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(diagnostics[key]), 0)
            }
            XCTAssertTrue(JSONSerialization.isValidJSONObject(diagnostics))
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
            let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let policy = try XCTUnwrap(fixture["sshTransportPolicy"] as? [String: Any])
            XCTAssertEqual(DesktopSSHRelay.limit, policy["queueLimitBytes"] as? Int)
            let retirement = try XCTUnwrap(policy["retirement"] as? [String: Any])
            XCTAssertEqual(DirectDesktopSSHTunnel.retirementSeconds, (retirement["maximumSeconds"] as? NSNumber)?.int64Value)
            let packetLimit = try XCTUnwrap(policy["maximumSSHPacketBytes"] as? Int)
            XCTAssertEqual(server.record.count("peerPacket.\(packetLimit)"), 1)
            XCTAssertEqual(policy["receiveWindowBytes"] as? Int, packetLimit)
            XCTAssertEqual(policy["backpressureScope"] as? String, "perDirection")
            XCTAssertEqual(policy["sourceReadRequiresOwnQueueBelowHighWatermark"] as? Bool, true)
            XCTAssertEqual(policy["sourceReadRequiresDestinationWritable"] as? Bool, true)
            XCTAssertEqual(policy["reversePendingWritesBlockSourceRead"] as? Bool, false)
            XCTAssertLessThanOrEqual(counts.peak, DesktopSSHRelay.limit)
            XCTAssertEqual(policy["plaintextFallback"] as? Bool, false)
            await tunnel.close(); await tunnel.close()
            XCTAssertFalse(tunnel.bridge.isActive); XCTAssertFalse(tunnel.remote.isActive)
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testBackpressureIsIndependentInBothRelayDirections() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            for stalledDirection in 0..<2 {
                let relays = DesktopSSHRelay.pair()
                let relayList = [relays.0, relays.1]
                let gates = [DesktopHeldRelayWrites(), DesktopHeldRelayWrites()]
                var channels: [Channel] = [], peers: [Int32] = []
                do {
                    for direction in 0..<2 {
                        var pair: [Int32] = [-1, -1]
                        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else { throw DesktopSSHFailure.socket }
                        peers.append(pair[0])
                        let gate = gates[direction], relay = relayList[direction]
                        let channel = try await ClientBootstrap(group: group)
                            .channelOption(ChannelOptions.autoRead, value: false)
                            .channelInitializer { $0.pipeline.addHandlers(gate, relay) }
                            .withConnectedSocket(pair[1]).get()
                        channels.append(channel)
                    }
                    let source = channels[stalledDirection], reverse = channels[1 - stalledDirection]
                    let sourceGate = gates[stalledDirection], destinationGate = gates[1 - stalledDirection]
                    let sourceRelay = relayList[stalledDirection]
                    try await source.eventLoop.submit {
                        let sourceBefore = sourceGate.reads, reverseBefore = destinationGate.reads
                        var frame = ByteBufferAllocator().buffer(capacity: 65536)
                        frame.writeRepeatingByte(0x5a, count: 65536)
                        source.pipeline.fireChannelRead(NIOAny(frame))
                        source.pipeline.fireChannelReadComplete()
                        XCTAssertEqual(sourceRelay.queuedBytes, 65536)
                        XCTAssertTrue(source.isWritable); XCTAssertTrue(reverse.isWritable)
                        source.read(); reverse.read()
                        XCTAssertEqual(sourceGate.reads, sourceBefore, "This direction must pause at its own queue watermark")
                        XCTAssertEqual(destinationGate.reads, reverseBefore + 1,
                            "A held write in one direction must not block reading input in the reverse direction")
                        destinationGate.releaseWrites()
                        XCTAssertEqual(sourceRelay.queuedBytes, 0)
                        XCTAssertEqual(sourceGate.reads, sourceBefore + 1, "Write completion must resume its own blocked reader")
                    }.get()
                    for channel in channels { try? await channel.close().get() }
                    for peer in peers { Darwin.close(peer) }
                } catch {
                    for channel in channels { try? await channel.close().get() }
                    for peer in peers { Darwin.close(peer) }
                    throw error
                }
            }
            try await group.shutdownGracefully()
        } catch { try? await group.shutdownGracefully(); throw error }
    }
    func testEncryptedTunnelDeliversReverseInputWhileVideoWritesAreHeld() async throws {
        let server = DesktopSSHServer(.echo); try await server.start()
        do {
            let tunnel = try await open(server), fd = tunnel.takeSocket()
            let heldVideo = DesktopHeldRelayWrites(forwardReads: true)
            try await tunnel.bridge.pipeline.addHandler(heldVideo, position: .first).get()
            var video = [UInt8](repeating: 0x5a, count: 65536)
            XCTAssertEqual(Darwin.write(fd, &video, video.count), video.count)
            var queued = false
            for _ in 0..<100 {
                if try await tunnel.diagnosticCounters()["inboundQueuedBytes"] == 65536 { queued = true; break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(queued, "The encrypted video path must actually be stalled for this test")
            // Repeated separate writes prevent an already-permitted socket read
            // from making a direction-coupling regression appear to pass.
            var input = [UInt8](repeating: 0x31, count: 16)
            for index in 1...4 {
                XCTAssertEqual(Darwin.write(fd, &input, input.count), input.count)
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertEqual(server.record.count("echoBytes"), 65536 + 16 * index,
                    "The synthetic SSH peer must receive each input while video delivery is blocked")
            }
            try await tunnel.bridge.eventLoop.submit { heldVideo.releaseWrites() }.get()
            Darwin.close(fd); await tunnel.close(); try await server.close()
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
    func testEstablishedRetirementForwardsEOFAndWaitsForPeerCleanupBeforeReplacement() async throws {
        let server = DesktopSSHServer(.retiring); try await server.start()
        let tunnel = try await open(server)
        await tunnel.close()
        XCTAssertEqual(server.record.count("forwardedEOF"), 1)
        XCTAssertEqual(server.record.count("peerCleanup"), 1)
        XCTAssertEqual(server.record.count("prematureParentClose"), 0)
        let active = try await server.activeClients(); XCTAssertEqual(active, 0)
        try await server.close()
    }
    func testUnresponsiveRetirementIsBoundedAndClosesEveryOwnedChannel() async throws {
        let server = DesktopSSHServer(.stalledRetirement); try await server.start()
        let tunnel = try await open(server), started = ProcessInfo.processInfo.systemUptime
        await tunnel.close()
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        XCTAssertEqual(server.record.count("forwardedEOF"), 1)
        XCTAssertLessThan(elapsed, 4)
        XCTAssertFalse(tunnel.bridge.isActive); XCTAssertFalse(tunnel.remote.isActive)
        try await server.close()
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
            // Explicit SSH override under the shared Login & Access profile.
            try DirectMacAccessStore.setMacLogin(.init(username: "desktop-saved", password: "desktop-synthetic"), id: mac.id)
            try TerminalSecretStore.save(terminalLogin, id: mac.id)
            XCTAssertEqual(try DirectMacAccessStore.load(mac.id).sshMethod, .password)
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
    func testRealConnectionSetupNegotiatesAndRendersHostCursorPositionOverSSH() async throws {
        let bundle = Bundle(for: Self.self)
        let indexURL = try XCTUnwrap(bundle.url(forResource: "manifest", withExtension: "json"))
        let index = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any])
        let entries = try XCTUnwrap(index["fixtures"] as? [[String: Any]])
        let entry = try XCTUnwrap(entries.first { $0["path"] as? String == "vnc-desktop-tunnel-v0.1.json" })
        XCTAssertEqual(entry["expect"] as? String, "valid")
        let fixtureURL = bundle.resourceURL!.appendingPathComponent(try XCTUnwrap(entry["path"] as? String))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        let shapes = try XCTUnwrap(fixture["appleCursorCases"] as? [[String: Any]])
        let shape = try XCTUnwrap(shapes.first)
        let size = try XCTUnwrap(shape["size"] as? [UInt16]), hotspot = try XCTUnwrap(shape["hotspot"] as? [UInt16])
        let payload = try XCTUnwrap(shape["payload"] as? [UInt8])
        let positionPolicy = try XCTUnwrap(fixture["appleCursorPosition"] as? [String: Any])
        let positions = try XCTUnwrap(positionPolicy["cases"] as? [[String: Any]])
        let position = try XCTUnwrap(positions.first { $0["known"] as? Bool == true })
        let rect = try XCTUnwrap(position["rect"] as? [UInt16])
        func packet(_ rect: [UInt16], encoding: UInt32, payload: [UInt8] = []) -> [UInt8] {
            [0, 0, 0, 1] + rect.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] } +
                [24, 16, 8, 0].map { UInt8((encoding >> $0) & 255) } + payload
        }
        let packets = [packet([hotspot[0], hotspot[1], size[0], size[1]], encoding: 1104, payload: payload),
                       packet(rect, encoding: 1100)]
        let server = DesktopSSHServer(.rfb, cursorPackets: packets); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic cursor Mac", addresses: ["127.0.0.1"], sshPort: server.port)
        try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let prior = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let viewer = CompanionVNCViewer(), coordinator = VNCRemoteDesktopView.Coordinator(mac: mac)
        viewer.macName = mac.name; viewer.sshPort = mac.sshPort; coordinator.viewer = viewer
        viewer.connectHandler = { user, password, remember in MainActor.assumeIsolated { coordinator.connect(user: user, password: password, remember: remember) } }
        viewer.disconnectHandler = { MainActor.assumeIsolated { coordinator.disconnect() } }
        window.rootViewController = viewer; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
        defer {
            coordinator.disconnect(); window.isHidden = true; window.rootViewController = nil
            prior?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id)
        }
        do {
            (viewer.value(forKey: "username") as? UITextField)?.text = "synthetic"
            (viewer.value(forKey: "password") as? UITextField)?.text = "synthetic-only"
            _ = viewer.perform(NSSelectorFromString("start"))
            try await wait("normal owner presents the desktop and host cursor") {
                viewer.session.connected && viewer.value(forKey: "lastFramebuffer") != nil &&
                    viewer.value(forKey: "remoteCursorImage") != nil &&
                    viewer.session.diagnosticCounters["cursorPositionUpdates"] as? Int == 1
            }
            XCTAssertEqual(server.record.count("tcp"), 1); XCTAssertEqual(server.record.count("forward"), 1)
            XCTAssertEqual(server.record.count("ardExchange"), 1)
            for encoding in try XCTUnwrap(fixture["cursorNegotiationEncodings"] as? [Int]) + [1104] {
                XCTAssertGreaterThan(server.record.count("encoding.\(encoding)"), 0, "Missing actual handshake encoding \(encoding)")
            }
            XCTAssertEqual(server.record.count("cursorPacketsSent"), 1)
            XCTAssertEqual(viewer.value(forKey: "cursorPositionKnown") as? Bool, true)
            XCTAssertEqual((viewer.value(forKey: "cursorPosition") as? NSValue)?.cgPointValue,
                           CGPoint(x: Int(rect[0]), y: Int(rect[1])))
            window.layoutIfNeeded()
            XCTAssertEqual((viewer.value(forKey: "cursorIndicator") as? UIView)?.isHidden, false)
            XCTAssertEqual((viewer.value(forKey: "fallbackCursor") as? CAShapeLayer)?.isHidden, true)
            coordinator.disconnect()
            try await wait("cursor connection closes") { !viewer.session.running }
            try await server.close()
        } catch { coordinator.disconnect(); try? await server.close(); throw error }
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
                if inputOnly {
                    try await wait("input-only controls become ready without pixels") {
                        (viewer.value(forKey: "loginScroll") as? UIScrollView)?.isHidden == true &&
                        (viewer.value(forKey: "starting") as? Bool) == false
                    }
                    XCTAssertNil(viewer.value(forKey: "lastFramebuffer"))
                    XCTAssertEqual((viewer.session.diagnosticCounters["presentedFrames"] as? NSNumber)?.intValue, 0)
                    // LibVNCClient sends its standard initial request inside rfbInitClient.
                    // Its response must never gate input or trigger ongoing polling.
                    XCTAssertEqual(server.record.count("update"), 1, "Only the library initialization request is sent")
                    let crop = try XCTUnwrap(viewer.value(forKey: "activeCrop") as? NSValue).cgRectValue
                    XCTAssertEqual(crop, CGRect(x: 0, y: 0, width: 256, height: 128), "Pointer bounds come from ServerInit")
                } else { try await wait("normal view presents framebuffer") { viewer.value(forKey: "lastFramebuffer") != nil } }
                XCTAssertEqual(server.record.count("auth"), 1); XCTAssertEqual(server.record.count("forward"), 1)
                XCTAssertEqual(server.record.count("ardExchange"), 1)
                if !inputOnly { try await wait("normal desktop arms automatic delivery") { server.record.count("automaticUpdatesStart") > 0 } }
                viewer.session.key(0xffe3, down: true)
                _ = viewer.session.tryClickX(20, y: 20, mask: 1)
                try await wait("ordered native input reaches encrypted channel") { server.record.count("keyDown") > 0 && server.record.count("pointerDown") > 0 }
                viewer.session.pause { server.record.add("paused") }
                try await wait("balanced native input pause completes") { server.record.count("paused") == 1 }
                try await wait("held modifiers release through same SSH channel") { server.record.count("keyUp") > 0 }
                viewer.session.resume()
                try await wait("same owner resumes") { viewer.session.connected }
                XCTAssertEqual(server.record.count("tcp"), 1)
                if inputOnly { XCTAssertEqual(server.record.count("update"), 1, "Resume sends no additional video requests") }
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
    func testMirrorRestartKeepsTransportClosedForWholeCleanupIntervalBeforeFreshAuthentication() async throws {
        let server = DesktopSSHServer(.rfb); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["127.0.0.1"], sshPort: server.port)
        try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
        let viewer = CompanionVNCViewer(), coordinator = VNCRemoteDesktopView.Coordinator(mac: mac)
        viewer.loadViewIfNeeded(); coordinator.viewer = viewer; viewer.restoredDesktopSizePreset = 0
        coordinator.connect(user: "synthetic", password: "synthetic-only", remember: false)
        do {
            try await wait("initial encrypted desktop") { viewer.session.desktopFrameReady }
            let previous = viewer.session
            viewer.setValue(true, forKey: "starting"); viewer.setValue(true, forKey: "changingDisplayMode")
            viewer.setValue(true, forKey: "mirrorRequiresCleanup"); viewer.setValue(true, forKey: "mirrorFullRestartUsed")
            coordinator.disconnect()
            let started = ContinuousClock.now
            coordinator.connect(user: "synthetic", password: "synthetic-only", remember: false)
            try await Task.sleep(for: .milliseconds(1200))
            XCTAssertEqual(server.record.count("tcp"),1, "No replacement may keep the old host display alive")
            XCTAssertEqual(server.record.count("auth"),1); XCTAssertTrue(viewer.session.displayHandoffInputBlocked)
            XCTAssertFalse(previous.running)
            let active = try await server.activeClients(); XCTAssertEqual(active,0, "The preceding SSH owner must be fully closed during cleanup")
            let remaining = try XCTUnwrap(viewer.value(forKey: "mirrorCleanupRemaining") as? Int)
            XCTAssertGreaterThan(remaining,13); XCTAssertLessThanOrEqual(remaining,16)
            try await Task.sleep(for: .seconds(15))
            try await wait("one fresh SSH authentication after cleanup") { server.record.count("auth") == 2 }
            XCTAssertGreaterThanOrEqual(started.duration(to: .now), .seconds(16))
            try await wait("fresh native framebuffer after restart") { viewer.session.desktopFrameReady }
            XCTAssertEqual(server.record.count("tcp"),2); XCTAssertEqual(server.record.count("forward"),2)
            XCTAssertEqual(viewer.value(forKey: "mirrorCleanupRemaining") as? Int,0)
            XCTAssertEqual(viewer.mirrorRetirementDelay,0)
            coordinator.disconnect(); viewer.stop(); try await server.close(); try? TerminalSecretStore.remove(mac.id)
        } catch { coordinator.disconnect(); viewer.stop(); try? await server.close(); try? TerminalSecretStore.remove(mac.id); throw error }
    }
    func testMirrorCleanupCannotOpenConnectionAfterExitReplacementOrLossOfForeground() async throws {
        for reason in ["exit", "replacement", "inactive", "background"] {
            let server = DesktopSSHServer(.rfb); try await server.start()
            let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["127.0.0.1"], sshPort: server.port)
            let viewer = CompanionVNCViewer(), coordinator = VNCRemoteDesktopView.Coordinator(mac: mac)
            viewer.loadViewIfNeeded(); coordinator.viewer = viewer
            viewer.setValue(true, forKey: "starting"); viewer.setValue(true, forKey: "changingDisplayMode")
            viewer.setValue(true, forKey: "mirrorRequiresCleanup")
            coordinator.connect(user: "synthetic", password: "synthetic-only", remember: false)
            try await Task.sleep(for: .milliseconds(150))
            switch reason {
            case "exit": viewer.stop()
            case "replacement": coordinator.disconnect(); viewer.prepareConnection()
            case "inactive": viewer.becameInactive()
            default: await viewer.background()
            }
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertEqual(server.record.count("tcp"),0, reason); XCTAssertEqual(server.record.count("auth"),0, reason)
            coordinator.disconnect(); viewer.stop(); try await server.close()
        }
    }

    func testMirrorInactivityRetainsTransientRecoveryAndRestartsQuietInterval() async throws {
        let server = DesktopSSHServer(.rfb); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["127.0.0.1"], sshPort: server.port)
        let viewer = CompanionVNCViewer(), coordinator = VNCRemoteDesktopView.Coordinator(mac: mac)
        viewer.loadViewIfNeeded(); coordinator.viewer = viewer
        let login = try XCTUnwrap(viewer.value(forKey: "credentialState") as? DirectDesktopLoginState)
        login.edit(username: "synthetic", password: "synthetic-only", remember: false)
        _ = login.beginLogin(); login.authenticated()
        viewer.restoredDesktopSizePreset = 0
        for key in ["starting", "changingDisplayMode", "mirrorRequiresCleanup", "mirrorFullRestartUsed"] { viewer.setValue(true, forKey: key) }
        viewer.setValue(0, forKey: "modeTargetPreset"); viewer.setValue(2, forKey: "modePreviousPreset")
        var recoveries = 0
        viewer.connectHandler = { user, password, remember in MainActor.assumeIsolated {
            recoveries += 1; XCTAssertEqual(user,"synthetic"); XCTAssertEqual(password,"synthetic-only"); XCTAssertFalse(remember)
            coordinator.connect(user: user, password: password, remember: remember)
        } }
        viewer.disconnectHandler = { MainActor.assumeIsolated { coordinator.disconnect() } }
        coordinator.observeActivity()
        do {
            coordinator.connect(user: "synthetic", password: "synthetic-only", remember: false)
            let retired = viewer.session
            try await Task.sleep(for: .milliseconds(150))
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertEqual(server.record.count("tcp"),0); XCTAssertEqual(server.record.count("auth"),0)
            XCTAssertEqual(login.loginForResume()?["password"],"synthetic-only", "Temporary inactivity is not explicit cancellation")
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertEqual(recoveries,1); XCTAssertFalse(viewer.session === retired)
            XCTAssertNil(viewer.value(forKey: "failedDisplayModePreset")); XCTAssertTrue(viewer.value(forKey: "starting") as? Bool == true)
            XCTAssertEqual(login.loginForResume()?["password"],"synthetic-only")
            XCTAssertEqual(server.record.count("tcp"),0); XCTAssertEqual(server.record.count("auth"),0)
            let remaining = try XCTUnwrap(viewer.value(forKey: "mirrorCleanupRemaining") as? Int)
            XCTAssertGreaterThan(remaining,13); XCTAssertLessThanOrEqual(remaining,16)
            coordinator.disconnect(); viewer.stop(); XCTAssertNil(login.loginForResume()); try await server.close()
        } catch {
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            coordinator.disconnect(); viewer.stop(); try? await server.close()
            coordinator.stopObserving(); viewer.connectHandler = nil; viewer.disconnectHandler = nil; throw error
        }
        coordinator.stopObserving(); viewer.connectHandler = nil; viewer.disconnectHandler = nil
    }

    func testActivationDuringRejectedOpeningRetirementKeepsTransientRecovery() async throws {
        let server = DesktopSSHServer(.retiring); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["127.0.0.1"], sshPort: server.port)
        try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
        let viewer = DesktopOpeningInterruptionViewer(), coordinator = VNCRemoteDesktopView.Coordinator(mac: mac)
        viewer.loadViewIfNeeded(); coordinator.viewer = viewer
        let login = try XCTUnwrap(viewer.value(forKey: "credentialState") as? DirectDesktopLoginState)
        login.edit(username: "synthetic", password: "synthetic-only", remember: false)
        _ = login.beginLogin(); login.authenticated()
        for key in ["starting", "changingDisplayMode", "mirrorFullRestartUsed"] { viewer.setValue(true, forKey: key) }
        viewer.restoredDesktopSizePreset = 2; viewer.setValue(2, forKey: "modeTargetPreset"); viewer.setValue(0, forKey: "modePreviousPreset")
        var recoveries = 0
        viewer.connectHandler = { user, password, remember in MainActor.assumeIsolated {
            recoveries += 1; XCTAssertEqual(user,"synthetic"); XCTAssertEqual(password,"synthetic-only"); XCTAssertFalse(remember)
            coordinator.connect(user: user, password: password, remember: remember)
        } }
        viewer.disconnectHandler = { MainActor.assumeIsolated { coordinator.disconnect() } }
        coordinator.observeActivity()
        var activation: Task<Void, Error>?
        viewer.openingHook = {
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            activation = Task { @MainActor in
                try await self.wait("rejected opening sends forwarded EOF") { server.record.count("forwardedEOF") > 0 }
                XCTAssertEqual(server.record.count("peerCleanup"),0,"Return while retirement is still pending")
                XCTAssertEqual(server.record.count("tcp"),1,"No overlapping replacement before retirement")
                NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            }
        }
        do {
            coordinator.connect(user: "synthetic", password: "synthetic-only", remember: false)
            try await wait("foreground recovery survives rejected-opening retirement") { recoveries == 1 }
            try await activation?.value
            try await wait("retiring peer finishes before replacement transport") { server.record.count("peerCleanup") >= 1 }
            XCTAssertEqual(login.loginForResume()?["password"],"synthetic-only")
            XCTAssertNil(viewer.value(forKey: "failedDisplayModePreset"))
            XCTAssertGreaterThanOrEqual(server.record.count("peerCleanup"),1)
            coordinator.disconnect(); viewer.stop(); try await server.close()
        } catch {
            activation?.cancel(); NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            coordinator.disconnect(); viewer.stop(); try? await server.close()
            coordinator.stopObserving(); viewer.connectHandler = nil; viewer.disconnectHandler = nil; try? TerminalSecretStore.remove(mac.id); throw error
        }
        coordinator.stopObserving(); viewer.connectHandler = nil; viewer.disconnectHandler = nil; try? TerminalSecretStore.remove(mac.id)
    }

    func testPendingOpeningRetiresBeforeReplacementAndCannotOverwriteIt() async throws {
        let server = DesktopSSHServer(.silent); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["127.0.0.1"], sshPort: server.port)
        let viewer = CompanionVNCViewer(), coordinator = VNCRemoteDesktopView.Coordinator(mac: mac)
        viewer.loadViewIfNeeded(); coordinator.viewer = viewer
        do {
            coordinator.connect(user: "synthetic", password: "synthetic-only", remember: false)
            try await wait("first pending SSH handshake") { server.record.count("tcp") == 1 }
            let old = viewer.session
            coordinator.disconnect()
            viewer.setValue(true, forKey: "starting"); viewer.setValue(true, forKey: "changingDisplayMode")
            viewer.setValue(2, forKey: "modeTargetPreset")
            coordinator.connect(user: "synthetic", password: "synthetic-only", remember: false)
            try await wait("replacement after joined pending retirement") { server.record.count("tcp") == 2 }
            let active = try await server.activeClients()
            XCTAssertEqual(active,1, "The old pending opener must not survive the replacement")
            XCTAssertFalse(old.running); XCTAssertFalse(viewer.session === old)
            XCTAssertTrue(viewer.session.displayHandoffInputBlocked)
            XCTAssertNil(viewer.value(forKey: "failedDisplayModePreset"), "The cancelled opener must not fail the replacement")
            XCTAssertTrue(viewer.value(forKey: "starting") as? Bool == true)
            coordinator.disconnect(); viewer.stop(); try await server.close()
        } catch { coordinator.disconnect(); viewer.stop(); try? await server.close(); throw error }
    }

}
