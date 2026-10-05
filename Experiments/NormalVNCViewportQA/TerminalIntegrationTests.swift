import XCTest
import Crypto
import NIO
import NIOSSH
import Citadel
@testable import Mac_Companion

private final class SSHTestRecord: @unchecked Sendable {
    private let lock=NSLock()
    private var auth=0, keyAuth=0
    private var cols=0, rows=0
    var passwordRequests: Int { lock.lock(); defer { lock.unlock() }; return auth }
    var keyRequests: Int { lock.lock(); defer { lock.unlock() }; return keyAuth }
    func keyAuthenticated() { lock.lock(); keyAuth += 1; lock.unlock() }
    var size: [Int] { lock.lock(); defer { lock.unlock() }; return [cols,rows] }
    func authenticated() { lock.lock(); auth += 1; lock.unlock() }
    func resized(_ cols:Int,_ rows:Int) { lock.lock(); self.cols=cols; self.rows=rows; lock.unlock() }
}
private final class SSHTestAuth: NIOSSHServerUserAuthenticationDelegate, @unchecked Sendable {
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
private final class SSHTestPTY: ChannelDuplexHandler, @unchecked Sendable {
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
            context.triggerUserOutboundEvent(ChannelSuccessEvent(),promise:nil)
            context.writeAndFlush(wrapOutboundOut(SSHChannelData(type:.channel,data:.byteBuffer(ByteBuffer(string:"synthetic-ready\r\n")))),promise:nil)
        } else if let request=event as? SSHChannelRequestEvent.WindowChangeRequest { record.resized(request.terminalCharacterWidth,request.terminalRowHeight) }
        else { context.fireUserInboundEventTriggered(event) }
    }
    func channelRead(context:ChannelHandlerContext,data:NIOAny) { context.writeAndFlush(wrapOutboundOut(unwrapInboundIn(data)),promise:nil) }
    func errorCaught(context:ChannelHandlerContext,error:Error) { context.close(promise:nil) }
}
@MainActor final class TerminalIntegrationTests:XCTestCase {
    private func server(record:SSHTestRecord,key:NIOSSHPrivateKey, publicKey: NIOSSHPublicKey? = nil) async throws -> Channel {
        let auth=SSHTestAuth(record, publicKey: publicKey)
        return try await ServerBootstrap(group:MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
            channel.pipeline.addHandler(NIOSSHHandler(role:.server(.init(hostKeys:[key],userAuthDelegate:auth)),allocator:channel.allocator,inboundChildChannelInitializer:{ child,type in
                child.pipeline.addHandler(SSHTestPTY(record))
            }))
        }.bind(host:"127.0.0.1",port:0).get()
    }
    private func wait(_ message: String = "synthetic SSH session", _ condition: @MainActor ()->Bool) async throws {
        for _ in 0..<500 { if condition() { return }; try await Task.sleep(for:.milliseconds(10)) }
        XCTFail("Timed out waiting for \(message)")
    }
    func testEd25519AuthenticatesOnlyAfterHostTrustWithoutPasswordFallback() async throws {
        let record = SSHTestRecord(), key = TerminalSSHKey.create()
        let publicKey = NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(rawRepresentation: key.seed)).publicKey
        let server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()), publicKey: publicKey)
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Key SSH", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectTerminalSession(mac: mac)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "MUST-NOT-SEND", remember: false, key: key)
        try await wait("key host trust") { session.trust != nil || !session.connecting }
        XCTAssertNotNil(session.trust); XCTAssertEqual(record.keyRequests, 0); XCTAssertEqual(record.passwordRequests, 0)
        session.answerTrust(true); try await wait("key authentication success") { session.connected || !session.connecting }
        XCTAssertTrue(session.connected, session.status); XCTAssertGreaterThan(record.keyRequests, 0); XCTAssertEqual(record.passwordRequests, 0)
        XCTAssertEqual(try TerminalSecretStore.sshKey(mac.id)?.username, "synthetic")
        session.stop()
        session.connect(username: "synthetic", password: "synthetic-only", remember: true, key: .create())
        try await wait("wrong key rejection; status: \(session.status); key requests: \(record.keyRequests)") { !session.connecting }
        XCTAssertFalse(session.connected); XCTAssertEqual(record.passwordRequests, 0)
        try await server.close()
    }
    func testRealSSHTrustBeforeLoginInteractivePTYOrderedInputResizeAndBackgroundStop() async throws {
        let record=SSHTestRecord(),key=NIOSSHPrivateKey(ed25519Key:.init())
        let server=try await server(record:record,key:key)
        let mac=DirectMacRecordV1(id:UUID(),name:"Synthetic SSH",addresses:["127.0.0.1"],sshPort:try XCTUnwrap(server.localAddress?.port))
        let session=DirectTerminalSession(mac:mac)
        var output=[UInt8](); session.received={ output += $0 }
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username:"synthetic",password:"synthetic-only",remember:true)
        try await wait { session.trust != nil || !session.connecting }
        XCTAssertNotNil(session.trust); XCTAssertEqual(record.passwordRequests,0)
        session.answerTrust(true); try await wait { session.connected || !session.connecting }
        XCTAssertTrue(session.connected,session.status); XCTAssertEqual(record.passwordRequests,1)
        try await wait { String(decoding:output,as:UTF8.self).contains("synthetic-ready") }
        session.send(Array("A".utf8)); session.send(Array("B".utf8)); session.resize(columns:100,rows:30)
        try await wait { String(decoding:output,as:UTF8.self).hasSuffix("AB") && record.size == [100,30] }
        XCTAssertEqual(record.size,[100,30]); XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.username,"synthetic")
        session.background(); XCTAssertFalse(session.connected); XCTAssertFalse(session.connecting)
        session.send(Array("MUST-NOT-REPLAY".utf8)); XCTAssertFalse(session.connected)
        try await server.close()
    }
    func testChangedHostKeyRejectsBeforeAnyPasswordAuthentication() async throws {
        let record=SSHTestRecord(), key=NIOSSHPrivateKey(ed25519Key:.init())
        let server=try await server(record:record,key:key)
        let mac=DirectMacRecordV1(id:UUID(),name:"Synthetic Changed SSH",addresses:["127.0.0.1"],sshPort:try XCTUnwrap(server.localAddress?.port))
        let other=NIOSSHPrivateKey(ed25519Key:.init())
        try TerminalSecretStore.write(Data(String(openSSHPublicKey:other.publicKey).utf8),id:mac.id,kind:"host-key")
        let session=DirectTerminalSession(mac:mac); defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username:"synthetic",password:"synthetic-only",remember:false)
        try await wait { !session.connecting }
        XCTAssertFalse(session.connected); XCTAssertEqual(record.passwordRequests,0); XCTAssertNil(session.trust)
        XCTAssertTrue(session.status.contains("key changed"),session.status)
        try await server.close()
    }
    func testRejectedFirstHostKeyCancelsWithoutSavingOrSendingLogin() async throws {
        let record=SSHTestRecord(),key=NIOSSHPrivateKey(ed25519Key:.init()),server=try await server(record:record,key:key)
        let mac=DirectMacRecordV1(id:UUID(),name:"Synthetic Reject SSH",addresses:["127.0.0.1"],sshPort:try XCTUnwrap(server.localAddress?.port))
        let session=DirectTerminalSession(mac:mac); defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username:"synthetic",password:"synthetic-only",remember:false)
        try await wait { session.trust != nil || !session.connecting }; XCTAssertNotNil(session.trust,session.status); session.answerTrust(false)
        try await wait { !session.connecting }; XCTAssertEqual(record.passwordRequests,0); XCTAssertNil(try TerminalSecretStore.hostKey(mac.id))
        try await server.close()
    }
}
