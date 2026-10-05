import XCTest
import LocalAuthentication
@testable import Mac_Companion

private final class ControlledLAContext: LAContext, @unchecked Sendable {
    var reply: (@Sendable (Bool, (any Error)?) -> Void)?
    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool { true }
    override func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping @Sendable (Bool, (any Error)?) -> Void) { self.reply = reply }
}
@MainActor final class ClientAccessTests: XCTestCase {
    func testUnlockLoadsUnderlyingStateButGatesCredentialsUntilSuccessAndRelocksOnBackground() async throws {
        let old = UserDefaults.standard.bool(forKey: DirectAppLockV1.preferenceKey)
        UserDefaults.standard.set(false,forKey: DirectAppLockV1.preferenceKey)
        let context = ControlledLAContext(), lock = DirectAppLockV1(contextFactory: { context })
        defer { lock.setEnabled(false); UserDefaults.standard.set(old,forKey: DirectAppLockV1.preferenceKey) }
        let folder=URL.temporaryDirectory.appending(path:UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let library=DirectMacLibraryV1(url:folder.appending(path:"macs.json"))
        XCTAssertTrue(library.save(id:nil,name:"Synthetic Mac",address:"127.0.0.1"))
        lock.setEnabled(true); XCTAssertTrue(lock.authenticating); XCTAssertFalse(lock.canAccess)
        XCTAssertEqual(library.macs.count,1) // local metadata loaded concurrently, no dependency on auth reply
        lock.install(); XCTAssertTrue(lock.authenticating) // prompt inactive does not create another context
        context.reply?(false,nil); try await Task.sleep(for:.milliseconds(30))
        XCTAssertFalse(lock.canAccess); XCTAssertFalse(lock.authenticating)
        lock.authenticate(); context.reply?(true,nil); try await Task.sleep(for:.milliseconds(30))
        XCTAssertTrue(lock.canAccess)
        lock.background(); XCTAssertFalse(lock.canAccess)
        context.reply?(true,nil); try await Task.sleep(for:.milliseconds(30)); XCTAssertFalse(lock.canAccess) // stale success cannot reopen
    }
    func testIndexedHostFingerprintAndSeparateTerminalCredentialRetention() throws {
        let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"direct-screen-sharing-v1",withExtension:"json"))
        let json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        let additions=try XCTUnwrap(json["clientAdditions"] as? [String:Any]), ssh=try XCTUnwrap(additions["ssh"] as? [String:Any])
        for vector in try XCTUnwrap(ssh["keyVectors"] as? [[String:String]]) { XCTAssertEqual(TerminalSecretStore.fingerprint(try XCTUnwrap(vector["openSSH"])),vector["fingerprint"]) }
        let id=UUID(); defer { try? TerminalSecretStore.remove(id); try? DesktopCredentialStoreV1.remove(id) }
        try DesktopCredentialStoreV1.save(.init(username:"desktop-user",password:"synthetic-desktop"),hostID:id)
        try TerminalSecretStore.save(.init(username:"ssh-user",password:"synthetic-ssh"),id:id)
        XCTAssertEqual(try TerminalSecretStore.login(id)?.username,"ssh-user"); XCTAssertEqual(DesktopCredentialStoreV1.read(id)?.username,"desktop-user")
        try TerminalSecretStore.forgetLogin(id); XCTAssertNil(try TerminalSecretStore.login(id)); XCTAssertNotNil(DesktopCredentialStoreV1.read(id))
    }
    func testSchemaTwoMigrationPreservesUUIDAndAddsDefaultSSHPort() throws {
        let id=UUID(),folder=URL.temporaryDirectory.appending(path:UUID().uuidString); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appending(path:"macs.json")
        try JSONSerialization.data(withJSONObject:["version":2,"macs":[["id":id.uuidString,"name":"Synthetic Mac","addresses":["127.0.0.1"],"port":5900]]]).write(to:url)
        let library=DirectMacLibraryV1(url:url); XCTAssertEqual(library.macs.first?.id,id); XCTAssertEqual(library.macs.first?.sshPort,22)
        XCTAssertTrue(library.save(id:id,name:"Updated",addresses:["127.0.0.1"],sshPort:2222)); XCTAssertEqual(DirectMacLibraryV1(url:url).macs.first?.sshPort,2222)
        VNCSessionPreferences.setFullscreen(true,mac:id); XCTAssertTrue(VNCSessionPreferences.fullscreen(id)); VNCSessionPreferences.clear(id); XCTAssertFalse(VNCSessionPreferences.fullscreen(id))
    }
}
