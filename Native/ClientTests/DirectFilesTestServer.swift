import Foundation
import NIO
import NIOSSH
import NIOConcurrencyHelpers
import Crypto
@testable import Citadel

/// Disposable loopback protocol fixture, linked only into hosted test targets.
/// Emits valid packets with indexed string sizes; never reads the host filesystem.
struct FilesDirectoryTestPlan: Decodable, Sendable {
    let name: String
    let entries: Int
    let longnameUnit: String
    let longnameRepeats: Int
    let extended: [[String]]
    let maximumMetadataBytes: Int?
    let accepted: Bool
    let expectedReadRequests: Int
    static let empty = Self(name: "empty", entries: 0, longnameUnit: "", longnameRepeats: 0,
                            extended: [], maximumMetadataBytes: nil, accepted: true, expectedReadRequests: 1)
}

final class FilesDirectoryTestProbe: Sendable {
    private struct State { var reads = 0; var closes = 0; var channels: [Channel] = [] }
    private let state = NIOLockedValueBox(State())
    var reads: Int { state.withLockedValue { $0.reads } }
    var closes: Int { state.withLockedValue { $0.closes } }
    func read() { state.withLockedValue { $0.reads += 1 } }
    func closeHandle() { state.withLockedValue { $0.closes += 1 } }
    func opened(_ channel: Channel) { state.withLockedValue { $0.channels.append(channel) } }
    func shutdown() async {
        let channels = state.withLockedValue { state -> [Channel] in
            defer { state.channels = [] }; return state.channels
        }
        for channel in channels { try? await channel.close().get() }
    }
}

private final class FilesDirectoryTestAuth: NIOSSHServerUserAuthenticationDelegate, Sendable {
    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { .password }
    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        if case .password(let login) = request.request {
            responsePromise.succeed(request.username == "synthetic" && login.password == "synthetic-only" ? .success : .failure)
        } else { responsePromise.succeed(.failure) }
    }
}

private final class FilesDirectoryTestChunks: ChannelOutboundHandler {
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var buffer = unwrapOutboundIn(data)
        // Feed a large SFTP packet as SSH stream chunks, like sftp-server's pipe.
        while buffer.readableBytes > 16_384 {
            context.write(wrapOutboundOut(buffer.readSlice(length: 16_384)!), promise: nil)
        }
        context.write(wrapOutboundOut(buffer), promise: promise)
    }
}

private final class FilesDirectoryTestHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SFTPMessage
    typealias OutboundOut = ByteBuffer
    let plan: FilesDirectoryTestPlan
    let probe: FilesDirectoryTestProbe
    let responseDelay: TimeAmount
    let downloadBytes: Data?
    private var index = 0 // Confined to this channel's event loop.
    init(plan: FilesDirectoryTestPlan, probe: FilesDirectoryTestProbe, responseDelay: TimeAmount, downloadBytes: Data?) {
        self.plan = plan; self.probe = probe; self.responseDelay = responseDelay
        self.downloadBytes = downloadBytes
    }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let request = event as? SSHChannelRequestEvent.SubsystemRequest {
            if request.subsystem == "sftp" { context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil) }
            else { context.triggerUserOutboundEvent(ChannelFailureEvent(), promise: nil) }
        } else { context.fireUserInboundEventTriggered(event) }
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response: SFTPMessage
        switch unwrapInboundIn(data) {
        case .initialize:
            response = .version(.init(version: .v3, extensionData: []))
        case .realpath(let request):
            var attributes = SFTPFileAttributes(); attributes.permissions = 0o040700
            response = .name(.init(requestId: request.requestId, components: [
                .init(filename: "/synthetic", longname: "", attributes: attributes)
            ]))
        case .opendir(let request):
            index = 0
            response = .handle(.init(requestId: request.requestId, handle: ByteBuffer(string: "directory")))
        case .readdir(let request):
            probe.read()
            if index < plan.entries {
                var attributes = SFTPFileAttributes(); attributes.permissions = 0o100600
                attributes.extended = plan.extended.map { ($0[0], $0[1]) }
                let entry = SFTPPathComponent(filename: String(format: "file%06d", index),
                    longname: String(repeating: plan.longnameUnit, count: plan.longnameRepeats), attributes: attributes)
                index += 1
                response = .name(.init(requestId: request.requestId, components: [entry]))
            } else { response = .status(.init(requestId: request.requestId, errorCode: .eof, message: "", languageTag: "")) }
        case .closeFile(let request):
            probe.closeHandle()
            response = .status(.init(requestId: request.requestId, errorCode: .ok, message: "", languageTag: ""))
        case .lstat(let request) where downloadBytes != nil:
            var attributes = SFTPFileAttributes(); attributes.permissions = 0o100600; attributes.size = UInt64(downloadBytes!.count)
            response = .attributes(.init(requestId: request.requestId, attributes: attributes))
        case .fstat(let request) where downloadBytes != nil:
            var attributes = SFTPFileAttributes(); attributes.permissions = 0o100600; attributes.size = UInt64(downloadBytes!.count)
            response = .attributes(.init(requestId: request.requestId, attributes: attributes))
        case .openFile(let request) where downloadBytes != nil:
            response = .handle(.init(requestId: request.requestId, handle: ByteBuffer(string: "download")))
        case .read(let request) where downloadBytes != nil:
            let bytes = downloadBytes!.dropFirst(Int(request.offset)).prefix(Int(request.length))
            response = bytes.isEmpty ? .status(.init(requestId: request.requestId, errorCode: .eof, message: "", languageTag: ""))
                : .data(.init(requestId: request.requestId, data: ByteBuffer(bytes: bytes)))
        default: context.close(promise: nil); return
        }
        do {
            let bytes = try packet(response)
            if responseDelay.nanoseconds == 0 { context.writeAndFlush(wrapOutboundOut(bytes), promise: nil) }
            else {
                let channel = context.channel
                channel.eventLoop.scheduleTask(in: responseDelay) {
                    guard channel.isActive else { return }
                    channel.writeAndFlush(bytes, promise: nil)
                }
            }
        }
        catch { context.close(promise: nil) }
    }
    private func packet(_ response: SFTPMessage) throws -> ByteBuffer {
        var buffer = ByteBuffer()
        guard case .name(let name) = response else {
            try SFTPMessageSerializer().encode(data: response, out: &buffer); return buffer
        }
        // Independently frame v3 NAME attributes, including extended_count.
        // The client's outbound attribute encoder is not the fixture authority.
        buffer.writeInteger(UInt32(0)); buffer.writeInteger(SFTPMessageType.name.rawValue)
        buffer.writeInteger(name.requestId); buffer.writeInteger(name.count)
        for entry in name.components {
            buffer.writeSSHString(entry.filename); buffer.writeSSHString(entry.longname)
            let extended = entry.attributes.extended
            buffer.writeInteger(UInt32(0x4) | (extended.isEmpty ? 0 : 0x80000000))
            buffer.writeInteger(entry.attributes.permissions ?? 0)
            if !extended.isEmpty {
                buffer.writeInteger(UInt32(extended.count))
                for (key, value) in extended { buffer.writeSSHString(key); buffer.writeSSHString(value) }
            }
        }
        buffer.setInteger(UInt32(buffer.readableBytes - 4), at: 0)
        return buffer
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}

func filesDirectoryTestServer(plan: FilesDirectoryTestPlan = .empty, probe: FilesDirectoryTestProbe,
                              responseDelay: TimeAmount = .nanoseconds(0), downloadBytes: Data? = nil) async throws -> Channel {
    let hostKey = NIOSSHPrivateKey(ed25519Key: .init())
    return try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
        probe.opened(channel)
        return channel.pipeline.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [hostKey], userAuthDelegate: FilesDirectoryTestAuth())),
            allocator: channel.allocator, inboundChildChannelInitializer: { child, _ in
                probe.opened(child)
                return child.pipeline.addHandlers(SSHChannelDataUnwrapper(), SSHOutboundChannelDataWrapper(), FilesDirectoryTestChunks(),
                    ByteToMessageHandler(SFTPMessageParser()),
                    FilesDirectoryTestHandler(plan: plan, probe: probe, responseDelay: responseDelay, downloadBytes: downloadBytes))
            }))
    }.bind(host: "127.0.0.1", port: 0).get()
}
