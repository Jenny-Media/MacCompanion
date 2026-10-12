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
    var transportIsActive: Bool { activeTransport()?.isActive ?? false }
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
    let usernames: Set<String>
    var supportedAuthenticationMethods:NIOSSHAvailableUserAuthenticationMethods { publicKey == nil ? .password : [.publicKey, .password] }
    init(_ record:SSHTestRecord, publicKey: NIOSSHPublicKey? = nil, usernames: Set<String> = ["synthetic"]) { self.record=record; self.publicKey=publicKey; self.usernames=usernames }
    func requestReceived(request:NIOSSHUserAuthenticationRequest,responsePromise:EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        switch request.request {
        case .publicKey(let login): record.keyAuthenticated(); responsePromise.succeed(usernames.contains(request.username) && login.publicKey == publicKey ? .success : .failure)
        case .password(let login): record.authenticated(); responsePromise.succeed(usernames.contains(request.username) && login.password == "synthetic-only" ? .success : .failure)
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

#if os(macOS)
/// The only server here is a disposable XCTest transport to macOS's own SFTP
/// executable. No server, shell process or helper is linked into either client.
final class FilesTestSFTPProcess: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData
    private let root: URL
    private let allowSFTP: Bool
    private let responseDelay: TimeAmount
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    init(root: URL, allowSFTP: Bool, responseDelay: TimeAmount) { self.root = root; self.allowSFTP = allowSFTP; self.responseDelay = responseDelay }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        guard let request = event as? SSHChannelRequestEvent.SubsystemRequest else { context.fireUserInboundEventTriggered(event); return }
        guard allowSFTP, request.subsystem == "sftp", process == nil else { context.triggerUserOutboundEvent(ChannelFailureEvent(), promise: nil); return }
        let process = Process(), input = Pipe(), output = Pipe(), channel = context.channel
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/sftp-server")
        process.arguments = ["-d", root.path]; process.currentDirectoryURL = root
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        self.process = process; self.input = input; self.output = output
        let delay = responseDelay
        output.fileHandleForReading.readabilityHandler = { handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil; channel.close(promise: nil) }
            else {
                channel.eventLoop.scheduleTask(in: delay) {
                    guard channel.isActive else { return }
                    channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(ByteBuffer(bytes: bytes))), promise: nil)
                }
            }
        }
        do { try process.run(); context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil) }
        catch { context.triggerUserOutboundEvent(ChannelFailureEvent(), promise: nil); stop() }
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case .byteBuffer(let buffer) = unwrapInboundIn(data).data, let input else { context.close(promise: nil); return }
        do { try input.fileHandleForWriting.write(contentsOf: Data(buffer.readableBytesView)) }
        catch { context.close(promise: nil) }
    }
    func channelInactive(context: ChannelHandlerContext) { stop(); context.fireChannelInactive() }
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
    private func stop() {
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close(); try? output?.fileHandleForReading.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil; input = nil; output = nil
    }
}
#endif
