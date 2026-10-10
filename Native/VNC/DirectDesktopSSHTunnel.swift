#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Darwin
@preconcurrency import Citadel
@preconcurrency import NIO
@preconcurrency import NIOSSH

enum DesktopSSHFailure: Error { case socket, forwarding }

/// Owns a duplicate while numeric-address dialing or the SSH handshake blocks.
/// Never closes a descriptor after its number could have been reused.
private final class DesktopSSHOpening: @unchecked Sendable {
    private let lock = NSLock()
    private var parent: Channel?
    private var descriptor: Int32 = -1
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func registerSocket(_ fd: Int32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
        guard !cancelled else { return false }
        if fd >= 0 {
            descriptor = dup(fd)
            guard descriptor >= 0 else { return false }
        }
        return true
    }
    func register(_ channel: Channel) {
        lock.lock(); parent = channel
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
        let shouldClose = cancelled; lock.unlock()
        if shouldClose { channel.close(promise: nil) }
    }
    func cancel() {
        lock.lock(); cancelled = true; let channel = parent
        if descriptor >= 0 { _ = shutdown(descriptor, SHUT_RDWR); Darwin.close(descriptor); descriptor = -1 }
        lock.unlock(); channel?.close(promise: nil)
    }
    deinit { cancel() }
}

// Both handlers live on one event loop. Pause reads while a partner's writes are
// buffered; fail closed at a hard queue limit even if an upstream ignores reads.
// No retries, replay, local TCP listener, or fallback transport.
final class DesktopSSHRelay: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    static let limit = 256 * 1024
    private weak var partner: DesktopSSHRelay?
    private var context: ChannelHandlerContext?
    private var pendingRead = false
    private var queued = 0
    private(set) var transferred = 0
    private(set) var peakQueued = 0
    static func pair() -> (DesktopSSHRelay, DesktopSSHRelay) {
        let a = DesktopSSHRelay(), b = DesktopSSHRelay()
        a.partner = b; b.partner = a
        return (a, b)
    }
    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        partner?.resumeRead()
    }
    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil; partner = nil
    }
    private var writable: Bool { context?.channel.isWritable == true && queued < 64 * 1024 }
    private func resumeRead() {
        guard pendingRead, queued < 64 * 1024, partner?.writable == true else { return }
        pendingRead = false; context?.read()
    }
    func read(context: ChannelHandlerContext) {
        if queued < 64 * 1024, partner?.writable == true { context.read() }
        else { pendingRead = true }
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
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
    func channelReadComplete(context: ChannelHandlerContext) { partner?.context?.flush() }
    func channelWritabilityChanged(context: ChannelHandlerContext) {
        partner?.resumeRead(); context.fireChannelWritabilityChanged()
    }
    func channelInactive(context: ChannelHandlerContext) {
        closeBoth(); context.fireChannelInactive()
    }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, case .inputClosed = event { closeBoth() }
        else { context.fireUserInboundEventTriggered(event) }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { closeBoth() }
    private func closeBoth() { context?.close(promise: nil); partner?.context?.close(promise: nil) }
}

final class DirectDesktopSSHTunnel: @unchecked Sendable {
    let client: SSHClient
    let remote: Channel
    let bridge: Channel
    private var consumerSocket: Int32
    // A duplicate allows cancellation to wake a synchronous LibVNCClient read
    // after ownership of the original descriptor has passed to C.
    private var cancellationSocket: Int32
    private let lock = NSLock()
    private let opening: DesktopSSHOpening
    private let relays: (DesktopSSHRelay, DesktopSSHRelay)
    private init(client: SSHClient, remote: Channel, bridge: Channel, socket: Int32,
                 cancellationSocket: Int32, opening: DesktopSSHOpening, relays: (DesktopSSHRelay, DesktopSSHRelay)) {
        self.client = client; self.remote = remote; self.bridge = bridge
        consumerSocket = socket; self.cancellationSocket = cancellationSocket; self.relays = relays; self.opening = opening
    }
    func takeSocket() -> Int32 {
        lock.lock(); defer { lock.unlock() }
        let fd = consumerSocket; consumerSocket = -1; return fd
    }
    func cancelReads() {
        lock.lock(); defer { lock.unlock() }
        if cancellationSocket >= 0 { _ = shutdown(cancellationSocket, SHUT_RDWR) }
    }
    func close() async {
        cancelReads(); opening.cancel()
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
        opening.cancel(); bridge.close(promise: nil); remote.close(promise: nil)
        for fd in [consumerSocket, cancellationSocket] where fd >= 0 {
            _ = shutdown(fd, SHUT_RDWR); Darwin.close(fd)
        }
    }
    func counts() async throws -> (outbound: Int, inbound: Int, peak: Int) {
        try await bridge.eventLoop.submit { [relays] in
            (relays.0.transferred, relays.1.transferred, max(relays.0.peakQueued, relays.1.peakQueued))
        }.get()
    }
    static func failureStage(_ error: Error) -> Int {
        if let error = error as? TerminalSecretStore.Failure {
            switch error {
            case .changedKey: return 112
            case .rejectedKey: return 113
            default: return 115
            }
        }
        if error as? TerminalConnectionFailure == .lookup { return 10 }
        if let error = error as? DesktopSSHFailure {
            switch error { case .socket: return 110; case .forwarding: return 114 }
        }
        if error is AuthenticationFailed { return 111 }
        if let error = error as? SSHClientError, case .allAuthenticationOptionsFailed = error { return 111 }
        return 110
    }
    static func open(addresses: [String], sshPort: Int, screenSharingPort: Int,
                     username: String, password: String,
                     validateHost: @escaping @MainActor @Sendable (String) async throws -> Void,
                     progress: @escaping @MainActor @Sendable (String) -> Void = { _ in }) async throws -> DirectDesktopSSHTunnel {
        let opening = DesktopSSHOpening()
        return try await withTaskCancellationHandler {
            do {
                return try await openUnchecked(addresses: addresses, sshPort: sshPort, screenSharingPort: screenSharingPort,
                    username: username, password: password, validateHost: validateHost, progress: progress, opening: opening)
            } catch { opening.cancel(); throw error }
        } onCancel: { opening.cancel() }
    }
    private static func openUnchecked(addresses: [String], sshPort: Int, screenSharingPort: Int,
                                      username: String, password: String,
                                      validateHost: @escaping @MainActor @Sendable (String) async throws -> Void,
                                      progress: @escaping @MainActor @Sendable (String) -> Void,
                                      opening: DesktopSSHOpening) async throws -> DirectDesktopSSHTunnel {
        guard (1...65535).contains(sshPort), (1...65535).contains(screenSharingPort),
              (1...8).contains(addresses.count) else { throw DesktopSSHFailure.socket }
        try Task.checkCancellation()
        await progress("Connecting to Remote Login…")
        // The established C resolver validates each numeric sockaddr and dials
        // that exact address. It stops fallback before SSH authentication.
        let (fd, failure) = await Task.detached { () -> (Int32, Int) in
            var failure = 0
            let fd = CompanionVNCConnectAddresses(addresses, sshPort, { opening.isCancelled },
                { opening.registerSocket($0) }, { _, _ in }, &failure)
            return (fd, failure)
        }.value
        guard fd >= 0 else {
            if opening.isCancelled { throw CancellationError() }
            throw failure == 10 ? TerminalConnectionFailure.lookup : DesktopSSHFailure.socket
        }
        if opening.isCancelled || Task.isCancelled { Darwin.close(fd); throw CancellationError() }
        await progress("Verifying SSH server…")
        let parent = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .channelOption(ChannelOptions.autoRead, value: false).withConnectedSocket(fd).get()
        opening.register(parent)
        var settings = SSHClientSettings(host: addresses[0], port: sshPort,
            authenticationMethod: { .passwordBased(username: username, password: password) },
            hostKeyValidator: .custom(TerminalHostValidator(validate: validateHost)))
        settings.connectTimeout = .seconds(60)
        let client: SSHClient
        do { try Task.checkCancellation(); client = try await SSHClient.connect(on: parent, settings: settings); try Task.checkCancellation() }
        catch { try? await parent.close(); throw error }
        await progress("Opening encrypted Screen Sharing…")
        var pair: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else {
            try? await client.close(); throw DesktopSSHFailure.socket
        }
        for fd in pair {
            var enabled: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        }
        let cancelFD = dup(pair[0])
        guard cancelFD >= 0 else {
            for fd in pair { Darwin.close(fd) }; try? await client.close(); throw DesktopSSHFailure.socket
        }
        let relays = DesktopSSHRelay.pair()
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
                targetHost: "127.0.0.1", targetPort: screenSharingPort,
                originatorAddress: try SocketAddress(ipAddress: "127.0.0.1", port: 0))) {
                $0.pipeline.addHandler(relays.1)
            }
            // A closed forwarding channel must not leave an idle SSH parent.
            local.closeFuture.whenComplete { _ in parent.close(promise: nil) }
            remote.closeFuture.whenComplete { _ in parent.close(promise: nil) }
            try await local.setOption(ChannelOptions.autoRead, value: true).get()
            try Task.checkCancellation()
            return DirectDesktopSSHTunnel(client: client, remote: remote, bridge: local, socket: pair[0],
                             cancellationSocket: cancelFD, opening: opening, relays: relays)
        } catch {
            if let bridge { try? await bridge.close() }
            for fd in pair where fd >= 0 { Darwin.close(fd) }
            Darwin.close(cancelFD); try? await client.close()
            if error is CancellationError { throw error }; throw DesktopSSHFailure.forwarding
        }
    }
}

#endif
