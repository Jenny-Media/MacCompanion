import Foundation
import Darwin
import Citadel
import NIO
import NIOSSH

public enum ProbeFailure: Error { case hostIdentity, socket, overflow, unexpectedChannel, handshake }

private final class HandshakeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var parent: Channel?
    private var cancelled = false
    func register(_ channel: Channel) {
        lock.lock(); parent = channel; let shouldClose = cancelled; lock.unlock()
        if shouldClose { channel.close(promise: nil) }
    }
    func cancel() {
        lock.lock(); cancelled = true; let channel = parent; lock.unlock()
        channel?.close(promise: nil)
    }
}

public final class StrictHostValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let trusted: Set<String>
    public init(keys: [String]) {
        trusted = Set(keys.map { $0.split(separator: " ").prefix(2).joined(separator: " ") })
    }
    public func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let key = String(openSSHPublicKey: hostKey).split(separator: " ").prefix(2).joined(separator: " ")
        if trusted.contains(key) { validationCompletePromise.succeed(()) }
        else { validationCompletePromise.fail(ProbeFailure.hostIdentity) }
    }
}

// Both handlers live on one event loop. Pause reads while a partner's writes are
// buffered; fail closed at a hard queue limit even if an upstream ignores reads.
// No retries, replay, local TCP listener, or fallback transport.
public final class BoundedRelay: ChannelDuplexHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    public static let limit = 256 * 1024
    private weak var partner: BoundedRelay?
    private var context: ChannelHandlerContext?
    private var pendingRead = false
    private var queued = 0
    public private(set) var transferred = 0
    public private(set) var peakQueued = 0
    public static func pair() -> (BoundedRelay, BoundedRelay) {
        let a = BoundedRelay(), b = BoundedRelay()
        a.partner = b; b.partner = a
        return (a, b)
    }
    public func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        partner?.resumeRead()
    }
    public func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil; partner = nil
    }
    private var writable: Bool { context?.channel.isWritable == true && queued < 64 * 1024 }
    private func resumeRead() {
        guard pendingRead, queued < 64 * 1024, partner?.writable == true else { return }
        pendingRead = false; context?.read()
    }
    public func read(context: ChannelHandlerContext) {
        if queued < 64 * 1024, partner?.writable == true { context.read() }
        else { pendingRead = true }
    }
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data), count = buffer.readableBytes
        guard let peer = partner, let peerContext = peer.context,
              count <= Self.limit, count <= Self.limit - queued else {
            closeBoth(); return
        }
        queued += count; transferred += count; peakQueued = max(peakQueued, queued)
        let completion = context.eventLoop.makePromise(of: Void.self)
        completion.futureResult.whenComplete { [weak self] result in
            guard let self else { return }
            self.queued -= count
            if case .failure = result { self.closeBoth() }
            else { self.resumeRead(); self.partner?.resumeRead() }
        }
        peerContext.write(peer.wrapOutboundOut(buffer), promise: completion)
    }
    public func channelReadComplete(context: ChannelHandlerContext) { partner?.context?.flush() }
    public func channelWritabilityChanged(context: ChannelHandlerContext) {
        partner?.resumeRead(); context.fireChannelWritabilityChanged()
    }
    public func channelInactive(context: ChannelHandlerContext) {
        closeBoth(); context.fireChannelInactive()
    }
    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, case .inputClosed = event { closeBoth() }
        else { context.fireUserInboundEventTriggered(event) }
    }
    public func errorCaught(context: ChannelHandlerContext, error: Error) { closeBoth() }
    private func closeBoth() { context?.close(promise: nil); partner?.context?.close(promise: nil) }
}

public final class SSHTunnel: @unchecked Sendable {
    public let client: SSHClient
    public let remote: Channel
    public let bridge: Channel
    private var consumerSocket: Int32
    // A duplicate allows cancellation to wake a synchronous LibVNCClient read
    // after ownership of the original descriptor has passed to C.
    private var cancellationSocket: Int32
    private let lock = NSLock()
    private let relays: (BoundedRelay, BoundedRelay)
    private init(client: SSHClient, remote: Channel, bridge: Channel, socket: Int32,
                 cancellationSocket: Int32, relays: (BoundedRelay, BoundedRelay)) {
        self.client = client; self.remote = remote; self.bridge = bridge
        consumerSocket = socket; self.cancellationSocket = cancellationSocket; self.relays = relays
    }
    public func takeSocket() -> Int32 {
        lock.lock(); defer { lock.unlock() }
        let fd = consumerSocket; consumerSocket = -1; return fd
    }
    public func cancelReads() {
        lock.lock(); defer { lock.unlock() }
        if cancellationSocket >= 0 { _ = shutdown(cancellationSocket, SHUT_RDWR) }
    }
    public func close() async {
        cancelReads()
        try? await bridge.close(); try? await remote.close(); try? await client.close()
        let descriptors = releaseDescriptors()
        for fd in descriptors where fd >= 0 { Darwin.close(fd) }
    }
    private func releaseDescriptors() -> [Int32] {
        lock.lock(); defer { lock.unlock() }
        let descriptors = [consumerSocket, cancellationSocket]
        consumerSocket = -1; cancellationSocket = -1
        return descriptors
    }
    deinit {
        for fd in [consumerSocket, cancellationSocket] where fd >= 0 {
            _ = shutdown(fd, SHUT_RDWR); Darwin.close(fd)
        }
    }
    public func counts() async throws -> (outbound: Int, inbound: Int, peak: Int) {
        try await bridge.eventLoop.submit { [relays] in
            (relays.0.transferred, relays.1.transferred, max(relays.0.peakQueued, relays.1.peakQueued))
        }.get()
    }
    public static func open(sshPort: Int, username: String, password: String, trustedKeys: [String]) async throws -> SSHTunnel {
        let cancellation = HandshakeCancellation()
        return try await withTaskCancellationHandler {
            try await openUnchecked(sshPort: sshPort, username: username, password: password,
                                    trustedKeys: trustedKeys, cancellation: cancellation)
        } onCancel: { cancellation.cancel() }
    }
    private static func openUnchecked(sshPort: Int, username: String, password: String,
                                      trustedKeys: [String], cancellation: HandshakeCancellation) async throws -> SSHTunnel {
        try Task.checkCancellation()
        var settings = SSHClientSettings(host: "127.0.0.1", port: sshPort,
            authenticationMethod: { .passwordBased(username: username, password: password) },
            hostKeyValidator: .custom(StrictHostValidator(keys: trustedKeys)))
        settings.connectTimeout = .seconds(10)
        // Own the parent channel before authentication: Citadel's convenience
        // connect API does not close it after every failed handshake.
        let parent = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .channelOption(ChannelOptions.autoRead, value: false)
            .connectTimeout(.seconds(10)).connect(to: SocketAddress(ipAddress: "127.0.0.1", port: sshPort)).get()
        cancellation.register(parent)
        let client: SSHClient
        do { try Task.checkCancellation(); client = try await SSHClient.connect(on: parent, settings: settings); try Task.checkCancellation() }
        catch { try? await parent.close(); throw error }
        var pair: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else {
            try? await client.close(); throw ProbeFailure.socket
        }
        for fd in pair {
            var enabled: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        }
        let cancelFD = dup(pair[0])
        guard cancelFD >= 0 else {
            for fd in pair { Darwin.close(fd) }; try? await client.close(); throw ProbeFailure.socket
        }
        let relays = BoundedRelay.pair()
        var bridge: Channel?
        do {
            // Read only after both directions have handlers. Keeping this on the
            // SSH event loop makes queue accounting and closure deterministic.
            let bridgeFD = pair[1]; pair[1] = -1 // NIO owns the FD even if registration fails.
            let local = try await ClientBootstrap(group: client.eventLoop)
                .channelOption(ChannelOptions.autoRead, value: false)
                .channelOption(ChannelOptions.recvAllocator, value: FixedSizeRecvByteBufferAllocator(capacity: 16 * 1024))
                .channelOption(ChannelOptions.maxMessagesPerRead, value: 1)
                .channelOption(ChannelOptions.writeBufferWaterMark, value: .init(low: 16 * 1024, high: 64 * 1024))
                .channelInitializer { $0.pipeline.addHandler(relays.0) }
                .withConnectedSocket(bridgeFD).get()
            bridge = local
            let deadline = parent.eventLoop.scheduleTask(in: .seconds(10)) { parent.close(promise: nil) }
            defer { deadline.cancel() }
            let remote = try await client.createDirectTCPIPChannel(using: .init(
                targetHost: "127.0.0.1", targetPort: 5900,
                originatorAddress: try SocketAddress(ipAddress: "127.0.0.1", port: 0))) {
                $0.pipeline.addHandler(relays.1)
            }
            try await local.setOption(ChannelOptions.autoRead, value: true).get()
            try Task.checkCancellation()
            return SSHTunnel(client: client, remote: remote, bridge: local, socket: pair[0],
                             cancellationSocket: cancelFD, relays: relays)
        } catch {
            if let bridge { try? await bridge.close() }
            for fd in pair where fd >= 0 { Darwin.close(fd) }
            Darwin.close(cancelFD); try? await client.close(); throw error
        }
    }
}
