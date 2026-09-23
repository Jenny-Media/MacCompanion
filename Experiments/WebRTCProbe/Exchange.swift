import Foundation

/// Test-only file exchange through the operator's local or paired-device channel.
/// This is not a production pairing/authentication protocol.
struct ProbeExchange: Codable, Sendable {
    let session: String
    let generation: UInt8
    let expiresAt: Double
    let sdp: String
    let capture: Bool
    var reconnectRequest: String? = nil

    func validate() throws {
        guard UUID(uuidString: session) != nil, generation > 0,
              expiresAt > Date().timeIntervalSince1970,
              expiresAt < Date().timeIntervalSince1970 + 3700,
              sdp.utf8.count < 262_144,
              reconnectRequest == nil || UUID(uuidString: reconnectRequest!) != nil else { throw MediaProbeError.missingDescription }
    }
    static func read(_ url: URL) throws -> Self {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 300_000 else { throw MediaProbeError.missingDescription }
        let result = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try result.validate()
        return result
    }
    func write(_ url: URL) throws { try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen]) }
}

/// A bounded request over the same disposable paired-device file channel.
/// Resuming media never extends the original test lifetime.
struct ProbeReconnectRequest: Codable, Sendable {
    let request: String
    let previousSession: String
    let generation: UInt8
    let expiresAt: Double

    func validate() throws {
        guard UUID(uuidString: request) != nil, UUID(uuidString: previousSession) != nil,
              generation > 0, expiresAt > Date().timeIntervalSince1970,
              expiresAt < Date().timeIntervalSince1970 + 3700 else { throw MediaProbeError.missingDescription }
    }
    static func read(_ url: URL) throws -> Self {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4096 else {
            throw MediaProbeError.missingDescription
        }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try value.validate()
        return value
    }
    func write(_ url: URL) throws {
        try validate()
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

func writeProbeStatus(_ value: [String: Any], to url: URL) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
        try? data.write(to: url, options: .atomic)
    }
}
