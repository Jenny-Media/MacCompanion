import Foundation
import Security
import XCTest

/// Hosted by the normal Simulator app; unique diagnostic keys are deleted.
/// No approval is performed and no production key policy is selected here.
final class IdentityCustodyDiagnostics: XCTestCase {
    func testSoftwareKeyCreationConstraints() throws {
        for mode in ["session", "approval-private-usage", "approval-presence"] {
            let tag = Data("dev.maccompanion.simulator.diagnostic.\(UUID().uuidString)".utf8)
            defer {
                SecItemDelete([kSecClass: kSecClassKey, kSecAttrApplicationTag: tag] as CFDictionary)
            }
            var privateAttributes: [CFString: Any] = [kSecAttrIsPermanent: true, kSecAttrApplicationTag: tag]
            var error: Unmanaged<CFError>?
            if mode == "session" {
                privateAttributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            } else {
                let flags: SecAccessControlCreateFlags = mode == "approval-private-usage"
                    ? [.privateKeyUsage, .userPresence] : [.userPresence]
                let control = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                             flags, &error)
                XCTAssertNotNil(control)
                privateAttributes[kSecAttrAccessControl] = control
            }
            let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeySizeInBits: 256, kSecPrivateKeyAttrs: privateAttributes]
            let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error)
            let retained = error?.takeRetainedValue()
            print("custody-diagnostic mode=\(mode) created=\(key != nil) error=\(retained.map(CFErrorGetCode) ?? 0)")
            if mode == "session" { XCTAssertNotNil(key) }
        }
    }
}
