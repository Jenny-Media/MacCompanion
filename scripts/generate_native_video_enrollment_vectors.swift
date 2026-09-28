import CryptoKit
import Foundation
func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
func lp(_ d: Data) -> Data { let n = UInt32(d.count); return Data((0..<4).map { UInt8((n >> (24 - $0 * 8)) & 255) }) + d }
func u64(_ n: UInt64) -> Data { Data((0..<8).map { UInt8((n >> (56 - $0 * 8)) & 255) }) }
func u16(_ n: UInt16) -> Data { Data([UInt8(n >> 8), UInt8(n & 255)]) }
func uuid(_ s: String) -> Data { var value = UUID(uuidString:s)!.uuid; return withUnsafeBytes(of:&value) { Data($0) } }
let ids = (1...5).map { "018f6000-0000-7000-8000-" + String(format:"%012d", $0) }
let hostPin = Data(0x80...0x9f), connection = Data(0x00...0x0f)
let coordinator = CommandLine.arguments.contains("--coordinator")
// These public bytes are deliberately not certificates. Only the injected test
// backend accepts them; the real backend validates complete X.509 DER.
let clientBytes = Data("MacCompanion public client certificate conformance bytes".utf8)
let hostBytes = Data("MacCompanion public host certificate conformance bytes".utf8)
let clientCert = coordinator ? Data(SHA256.hash(data: clientBytes)) : Data(0xa0...0xbf)
let hostCert = coordinator ? Data(SHA256.hash(data: hostBytes)) : Data(0xc0...0xdf)
let challenge = Data(0x30...0x4f)
var input = Data("MacCompanion/NativeVideoEnrollment/v0.1".utf8)
input += lp(uuid(ids[0])) + lp(hostPin) + lp(uuid(ids[1])) + lp(connection) + lp(uuid(ids[2]))
input += u64(4) + u64(5) + u64(6) + lp(uuid(ids[3])) + lp(uuid(ids[4])) + u64(1) + u64(2) + u16(1280) + u16(720)
input += lp(clientCert) + lp(hostCert) + lp(challenge) + u64(1724000000000) + u64(1724000015000) + u16(0) + u16(1)
let key = try P256.Signing.PrivateKey(rawRepresentation: Data(repeating:0,count:31) + Data([1]))
var result: [String:Any] = ["profile":"MacCompanion native video enrollment signing v0.1", "warning":"Public conformance-only session key and digest stand-ins. Never use in a product build.", "inputs":["hostID":ids[0],"clientID":ids[1],"interactiveSessionID":ids[2],"streamGeneration":ids[3],"surfaceID":ids[4],"hostFingerprintHex":hex(hostPin),"primaryConnectionIDHex":hex(connection),"authorizationEpoch":4,"grantRevision":5,"policyRevision":6,"surfaceRevision":1,"coordinateSpaceRevision":2,"encodedWidth":1280,"encodedHeight":720,"clientCertificateSHA256Hex":hex(clientCert),"hostCertificateSHA256Hex":hex(hostCert),"hostChallengeHex":hex(challenge),"issuedAtUnixMilliseconds":1724000000000,"expiresAtUnixMilliseconds":1724000015000,"sessionPublicKeyX963Hex":hex(key.publicKey.x963Representation)],"derived":["signingInputHex":hex(input),"signingInputSHA256Hex":hex(Data(SHA256.hash(data:input))),"signatureRawHex":hex(try key.signature(for:input).rawRepresentation)]]
if coordinator {
    result["certificateConformanceBytes"] = ["clientHex": hex(clientBytes), "hostHex": hex(hostBytes)]
    result["warning"] = "Public conformance key and non-certificate bytes for the fake backend only. Never use in a product build."
}
let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
print(String(data:data,encoding:.utf8)!)
