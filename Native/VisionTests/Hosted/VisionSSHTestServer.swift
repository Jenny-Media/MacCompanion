import XCTest
import UIKit
import SwiftUI
import Crypto
@preconcurrency import NIO
@preconcurrency import NIOSSH
@preconcurrency import Citadel
import Darwin

private enum VisionTestPeerFailure: Error { case forwarding }

/// Generated interoperability workload, never an additional golden corpus.
/// SSH authenticates a synthetic account. The RFB peer completes ARD's client
/// exchange but does not claim to validate macOS account authentication.
final class DesktopSSHRecord: @unchecked Sendable {
    struct Pointer: Sendable { let mask: Int; let x: Int; let y: Int; let time: Double; let modifiers: [UInt32] }
    struct Scroll: Sendable { let phase: Int; let dx: Double; let dy: Double; let x: Int; let y: Int }
    private let lock = NSLock()
    private var values = [String: Int]()
    private var pointers = [Pointer]()
    private var scrolls = [Scroll]()
    func add(_ key: String) { lock.lock(); values[key, default: 0] += 1; lock.unlock() }
    func count(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return values[key, default: 0] }
    func pointer(mask: Int, x: Int, y: Int, modifiers: [UInt32]) {
        lock.lock(); defer { lock.unlock() }
        if pointers.count < 4096 { pointers.append(.init(mask: mask, x: x, y: y, time: ProcessInfo.processInfo.systemUptime, modifiers: modifiers)) }
        values[mask & 7 != 0 ? "pointerDown" : "pointerUp", default: 0] += 1
        values["pointer-mask-" + String(mask), default: 0] += 1
    }
    func pointerEvents() -> [Pointer] { lock.lock(); defer { lock.unlock() }; return pointers }
    func scroll(_ event: Scroll) { lock.lock(); defer { lock.unlock() }; if scrolls.count < 4096 { scrolls.append(event) } }
    func scrollEvents() -> [Scroll] { lock.lock(); defer { lock.unlock() }; return scrolls }
}
final class DesktopSSHAuth: NIOSSHServerUserAuthenticationDelegate, @unchecked Sendable {
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
final class DesktopSSHEcho: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    func channelRead(context: ChannelHandlerContext, data: NIOAny) { context.writeAndFlush(data, promise: nil) }
}
final class DesktopSyntheticRFB: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData
    let record: DesktopSSHRecord
    private var input = ByteBuffer()
    private var stage = 0
    private let width: Int, height: Int
    private let nativeGestures: Bool
    private var layoutSent = false
    private var renderedRevision = -1
    private var revision = 0
    private var frameRequested = false
    private var forceFrame = false
    private var lastMask = 0
    private var marker = CGPoint.zero
    private var draggingMarker = false
    private var clicks = 0
    private var scrollOffset = 0
    private var typedKeys = 0
    private var heldModifiers = Set<UInt32>()
    private var output: [UInt8] = []
    private var offset = 0
    private var flushing = false
    init(_ record: DesktopSSHRecord, width: Int = 256, height: Int = 128, nativeGestures: Bool = false) {
        self.record = record; self.width = width; self.height = height; self.nativeGestures = nativeGestures
        marker = CGPoint(x: width / 2, y: height / 2)
    }
    private func dimension(_ value: Int) -> [UInt8] { [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)] }
    /// Generated two-display metadata exercises the existing Apple 1105 decoder.
    private func layout() -> [UInt8] {
        var body = [UInt8](repeating: 0, count: 20 + 2 * 56)
        func u16(_ value: Int, _ offset: Int) { body.replaceSubrange(offset..<offset + 2, with: dimension(value)) }
        u16(5, 0); u16(width, 2); u16(height, 4); u16(width, 6); u16(height, 8); u16(2, 18)
        for i in 0..<2 {
            let offset = 20 + i * 56
            body[offset + 19] = UInt8(i + 1)
            u16(0, offset + 28); u16(i * width / 2, offset + 30)
            u16(height, offset + 32); u16((i + 1) * width / 2, offset + 34)
        }
        return [0, 0, 0, 1] + [UInt8](repeating: 0, count: 8) + [0, 0, 4, 81] + dimension(body.count) + body
    }
    private func pump(_ channel: Channel) {
        guard channel.isWritable, !flushing, offset < output.count else { return }
        let end = min(output.count, offset + 16_384), bytes = Array(output[offset..<end]); offset = end; flushing = true
        channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(ByteBuffer(bytes: bytes)))).whenComplete { [self] result in
            flushing = false
            if case .failure = result { channel.close(promise: nil); return }
            if offset == output.count {
                output = []; offset = 0
                channel.eventLoop.execute { self.renderIfNeeded(channel) }
            }
            else { channel.eventLoop.execute { self.pump(channel) } }
        }
    }
    func channelWritabilityChanged(context: ChannelHandlerContext) { pump(context.channel); context.fireChannelWritabilityChanged() }
    private func send(_ bytes: [UInt8], _ context: ChannelHandlerContext) {
        context.writeAndFlush(wrapOutboundOut(.init(type: .channel, data: .byteBuffer(ByteBuffer(bytes: bytes)))), promise: nil)
    }
    /// Every pixel is generated. Changes exercise the real decoder/renderer,
    /// without recording screenshots or pretending to implement macOS controls.
    private func renderIfNeeded(_ channel: Channel) {
        guard frameRequested, !flushing, output.isEmpty, forceFrame || renderedRevision != revision else { return }
        frameRequested = false; forceFrame = false; renderedRevision = revision
        var frame: [UInt8] = [0, 0, 0, 1, 0, 0, 0, 0] + dimension(width) + dimension(height) + [0, 0, 0, 0]
        frame.reserveCapacity(16 + width * height * 4)
        let radius = max(12, min(40, width / 8))
        for y in 0..<height {
            for x in 0..<width {
                var color: [UInt8] = [180, 90, 30, 0]
                if x < width / 3 { color = ((y + scrollOffset) / 16).isMultiple(of: 2) ? [190, 160, 40, 0] : [70, 45, 25, 0] }
                if abs(x - Int(marker.x)) < radius && abs(y - Int(marker.y)) < min(radius, height / 4) {
                    color = clicks.isMultiple(of: 2) ? [30, 170, 80, 0] : [210, 70, 120, 0]
                }
                if x > width / 2 && y > height * 3 / 4 {
                    color = [UInt8(40 + typedKeys % 160), 55, 80, 0]
                }
                frame += color
            }
        }
        record.add("frame"); output = frame; offset = 0; pump(channel)
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
                send(dimension(width) + dimension(height) + [32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0,
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
                case 0x17:
                    guard let length: UInt16 = input.getInteger(at: input.readerIndex + 2) else { return }
                    guard nativeGestures, length <= 256 else { context.close(promise: nil); return }
                    count = 4 + Int(length)
                default: context.close(promise: nil); return
                }
                guard let bytes = input.readBytes(length: count) else { return }
                if kind == 3 {
                    record.add("update")
                    if nativeGestures && !layoutSent { layoutSent = true; send(layout(), context); record.add("layout") }
                    frameRequested = true; forceFrame = forceFrame || bytes[1] == 0
                    renderIfNeeded(context.channel)
                } else if kind == 0x17 {
                    guard bytes.count == 58, bytes[4...7] == [0, 1, 0, 11] else { context.close(promise: nil); return }
                    func integer(_ offset: Int) -> UInt32 { bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | UInt32($1) } }
                    let event = DesktopSSHRecord.Scroll(phase: Int(integer(38)),
                        dx: Double(Int32(bitPattern: integer(14))) / 65_536,
                        dy: Double(Int32(bitPattern: integer(18))) / 65_536,
                        x: Int(bytes[54]) << 8 | Int(bytes[55]), y: Int(bytes[56]) << 8 | Int(bytes[57]))
                    guard [1, 2, 4].contains(event.phase), abs(event.dx) <= 2048, abs(event.dy) <= 2048 else { context.close(promise: nil); return }
                    record.scroll(event)
                    if event.phase == 2 { scrollOffset += Int(event.dy); revision += 1; record.add("visualScroll"); renderIfNeeded(context.channel) }
                } else if kind == 4 {
                    let symbol = bytes[4...7].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    if [UInt32(0xffe1), 0xffe3, 0xffe9, 0xffeb].contains(symbol) {
                        if bytes[1] != 0 { heldModifiers.insert(symbol) } else { heldModifiers.remove(symbol) }
                    }
                    record.add(bytes[1] == 0 ? "keyUp" : "keyDown")
                    record.add((bytes[1] == 0 ? "keyUp-" : "keyDown-") + String(symbol))
                    if bytes[1] != 0 { typedKeys += 1; revision += 1; renderIfNeeded(context.channel) }
                }
                else if kind == 5 {
                    let mask = Int(bytes[1]), x = Int(bytes[2]) << 8 | Int(bytes[3]), y = Int(bytes[4]) << 8 | Int(bytes[5])
                    record.pointer(mask: mask, x: x, y: y, modifiers: heldModifiers.sorted())
                    if mask & 1 != 0 {
                        if lastMask & 1 == 0 { draggingMarker = abs(x - Int(marker.x)) < 40 && abs(y - Int(marker.y)) < 40 }
                        if draggingMarker { marker = CGPoint(x: x, y: y); revision += 1 }
                    } else if lastMask & 1 != 0 {
                        clicks += 1; draggingMarker = false; revision += 1; record.add("visualClick")
                    }
                    if mask & 8 != 0 { scrollOffset -= 12; revision += 1; record.add("visualScroll") }
                    if mask & 16 != 0 { scrollOffset += 12; revision += 1; record.add("visualScroll") }
                    if mask & 96 != 0 { scrollOffset += 8; revision += 1; record.add("visualScroll") }
                    lastMask = mask; renderIfNeeded(context.channel)
                }
            }
            input.discardReadBytes()
        }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}
final class DesktopSSHServer: @unchecked Sendable {
    enum Mode: Sendable { case echo, rfb, denied, silent }
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let key = NIOSSHPrivateKey(ed25519Key: .init())
    let record = DesktopSSHRecord()
    let mode: Mode
    let screenPort: Int
    let width: Int, height: Int
    let nativeGestures: Bool
    var listener: Channel!
    private var clients: [Channel] = [] // Sole server event loop.
    init(_ mode: Mode, screenPort: Int = 5900, width: Int = 256, height: Int = 128, nativeGestures: Bool = false) {
        self.mode = mode; self.screenPort = screenPort; self.width = width; self.height = height; self.nativeGestures = nativeGestures
    }
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
                        return child.eventLoop.makeFailedFuture(VisionTestPeerFailure.forwarding)
                    }
                    record.add("forward")
                    return mode == .echo ? child.pipeline.addHandler(DesktopSSHEcho()) : child.pipeline.addHandler(DesktopSyntheticRFB(record, width: width, height: height, nativeGestures: nativeGestures))
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

final class SSHTestServer: @unchecked Sendable {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let key = NIOSSHPrivateKey(ed25519Key: .init())
    let record = SSHTestRecord()
    private var listener: Channel!
    private var clients: [Channel] = []
    var port: Int { listener.localAddress!.port! }
    var hostKey: String { String(openSSHPublicKey: key.publicKey) }
    func start() async throws {
        listener = try await ServerBootstrap(group: group).childChannelInitializer { [self] channel in
            clients.append(channel); record.openedTransport(channel)
            return channel.pipeline.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [key], userAuthDelegate: SSHTestAuth(record))),
                allocator: channel.allocator, inboundChildChannelInitializer: { [self] child, type in
                    guard type == .session else { return child.eventLoop.makeFailedFuture(VisionTestPeerFailure.forwarding) }
                    return child.pipeline.addHandler(SSHTestPTY(record))
                }))
        }.bind(host: "127.0.0.1", port: 0).get()
    }
    func close() async throws {
        let connections = try await group.next().submit { self.clients }.get()
        for channel in connections { try? await channel.close().get() }
        try await listener.close().get(); try await group.shutdownGracefully()
    }
}
