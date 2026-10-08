#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Crypto
import Citadel
import NIOSSH

/// Private material stays in the device-only Keychain; private backups require authenticated encrypted export.
struct TerminalSSHKey: Codable, Sendable {
    var seed: Data
    var username: String = ""
    var publicKey: String { (try? String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey(rawRepresentation: seed)).publicKey)) ?? "" }
    var fingerprint: String { TerminalSecretStore.fingerprint(publicKey) ?? "" }
    func validate() throws {
        guard seed.count == 32, username.utf8.count <= 255, !username.contains("\0"), !publicKey.isEmpty else { throw KeyFailure.invalid }
    }
    static func create() -> Self { .init(seed: Curve25519.Signing.PrivateKey().rawRepresentation) }
    static func importOpenSSH(_ text: String, passphrase: String) throws -> Self {
        guard text.utf8.count <= 32768, passphrase.utf8.count <= 4096 else { throw KeyFailure.tooLarge }
        let header = "-----BEGIN OPENSSH " + "PRIVATE KEY-----"
        let footer = "-----END OPENSSH " + "PRIVATE KEY-----"
        let compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
        let begin = header.replacingOccurrences(of: " ", with: "")
        let end = footer.replacingOccurrences(of: " ", with: "")
        guard compact.hasPrefix(begin), compact.hasSuffix(end),
              let data = Data(base64Encoded: String(compact.dropFirst(begin.count).dropLast(end.count))) else { throw KeyFailure.invalid }
        var reader = KeyReader(data: data)
        guard try reader.take(15) == Data("openssh-key-v1\0".utf8) else { throw KeyFailure.invalid }
        let cipher = try reader.field(), kdf = try reader.field(), options = try reader.field()
        guard try reader.integer() == 1 else { throw KeyFailure.invalid }
        let publicBlob = try reader.field()
        var publicReader = KeyReader(data: publicBlob)
        guard try publicReader.field() == Data("ssh-ed25519".utf8) else { throw KeyFailure.unsupported }
        let advertised = try publicReader.field()
        guard advertised.count == 32, publicReader.remaining == 0 else { throw KeyFailure.invalid }
        _ = try reader.field()
        guard reader.remaining == 0 else { throw KeyFailure.invalid }
        if cipher == Data("none".utf8) {
            guard kdf == Data("none".utf8), options.isEmpty else { throw KeyFailure.invalid }
        } else {
            guard ["aes128-ctr", "aes256-ctr"].contains(String(decoding: cipher, as: UTF8.self)), kdf == Data("bcrypt".utf8) else { throw KeyFailure.unsupported }
            var kdfReader = KeyReader(data: options)
            let salt = try kdfReader.field(), rounds = try kdfReader.integer()
            guard (1...64).contains(salt.count), (1...128).contains(rounds), kdfReader.remaining == 0 else { throw KeyFailure.workLimit }
            guard !passphrase.isEmpty else { throw KeyFailure.passphrase }
        }
        // Citadel handles the standard OpenSSH cipher and bcrypt KDF after bounded preflight.
        let normalized = header + "\n" + data.base64EncodedString() + "\n" + footer
        let key: Curve25519.Signing.PrivateKey
        do { key = try .init(sshEd25519: normalized, decryptionKey: passphrase.isEmpty ? nil : Data(passphrase.utf8)) }
        catch { throw cipher == Data("none".utf8) ? KeyFailure.invalid : KeyFailure.passphrase }
        guard key.publicKey.rawRepresentation == advertised else { throw KeyFailure.invalid }
        return .init(seed: key.rawRepresentation)
    }
    enum KeyFailure: LocalizedError {
        case invalid, unsupported, tooLarge, passphrase, workLimit
        var errorDescription: String? {
            switch self {
            case .invalid: "This is not a valid OpenSSH private key. Nothing was saved."
            case .unsupported: "Use an Ed25519 OpenSSH key. RSA, ECDSA and hardware-backed keys are not supported yet."
            case .tooLarge: "The key file must be at most 32 KiB."
            case .passphrase: "Enter the correct passphrase for this key. Nothing was saved."
            case .workLimit: "This key uses an unsupported encryption work factor. Re-export it with the standard OpenSSH settings."
            }
        }
    }
}
private struct KeyReader {
    let data: Data
    var offset = 0
    var remaining: Int { data.count - offset }
    mutating func take(_ length: Int) throws -> Data {
        guard length >= 0, length <= remaining else { throw TerminalSSHKey.KeyFailure.invalid }
        defer { offset += length }; return data.subdata(in: offset..<(offset + length))
    }
    mutating func integer() throws -> UInt32 { try take(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } }
    mutating func field() throws -> Data { let length = try integer(); return try take(Int(length)) }
}
#endif
