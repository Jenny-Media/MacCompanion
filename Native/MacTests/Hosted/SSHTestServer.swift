import Foundation
import Crypto
import NIO
import NIOSSH
import Citadel
import Darwin

final class SSHTestRecord: @unchecked Sendable {
    let respondToInstall: Bool
    init(respondToInstall: Bool = true) { self.respondToInstall = respondToInstall }
    private let lock=NSLock()
    private var auth=0, keyAuth=0
    private var execs=0
    private var input: [UInt8] = []
    private var shell: Channel?
    private var transport: Channel?
    func openedTransport(_ channel: Channel) { lock.lock(); transport = channel; lock.unlock() }
    private func activeTransport() -> Channel? { lock.lock(); defer { lock.unlock() }; return transport }
    func finish(status: Int?, signal: String? = nil, transportFailed: Bool = false) async throws {
        guard let channel = activeShell() else { throw POSIXError(.ENOTCONN) }
        if let status { try await channel.triggerUserOutboundEvent(SSHChannelRequestEvent.ExitStatus(exitStatus: status)).get() }
        if let signal { try await channel.triggerUserOutboundEvent(SSHChannelRequestEvent.ExitSignal(signalName: signal, errorMessage: "", language: "", dumpedCore: false)).get() }
        if transportFailed { try await activeTransport()?.close().get() }
        else { try await channel.close().get() }
    }
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
final class SSHTestAuth: NIOSSHServerUserAuthenticationDelegate, @unchecked Sendable {
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
final class SSHTestPTY: ChannelDuplexHandler, @unchecked Sendable {
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
