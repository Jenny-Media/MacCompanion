#if !DEBUG || !targetEnvironment(simulator)
#error("Normal consent test driver is Debug Simulator-only")
#endif
import Darwin
import Foundation

/// Separate UI-test process only. The normal app never receives this token.
enum NormalConsentBridge {
    enum Failure: Error { case invalidFixture, socket, transport, response }

    static func command(_ action: String) throws -> [String: Any] {
        guard let encoded = ProcessInfo.processInfo.environment["MACCOMPANION_TEST_CONSENT_FIXTURE"],
              let data = encoded.data(using: .utf8),
              let fixture = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              fixture["source"] as? String == "signed-agent",
              let token = fixture["token"] as? String,
              let port = fixture["port"] as? Int, (1...65535).contains(port) else { throw Failure.invalidFixture }
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure.socket }
        defer { Darwin.close(descriptor) }
        var timeout = timeval(tv_sec: 8, tv_usec: 0)
        var noSignal: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw Failure.socket
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        guard inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) == 1 else { throw Failure.socket }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { throw Failure.transport }
        func send(_ object: [String: Any]) throws {
            let body = try JSONSerialization.data(withJSONObject: object)
            var length = UInt32(body.count).bigEndian
            var frame = withUnsafeBytes(of: &length) { Data($0) }
            frame.append(body)
            try frame.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.send(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                    guard count > 0 else { throw Failure.transport }
                    offset += count
                }
            }
        }
        func read(_ length: Int) throws -> Data {
            var data = Data(count: length)
            try data.withUnsafeMutableBytes { bytes in
                var offset = 0
                while offset < length {
                    let count = Darwin.recv(descriptor, bytes.baseAddress!.advanced(by: offset), length - offset, 0)
                    guard count > 0 else { throw Failure.transport }
                    offset += count
                }
            }
            return data
        }
        func receive() throws -> Data {
            let prefix = try read(4)
            let count = prefix.reduce(0) { ($0 << 8) | Int($1) }
            guard count > 0, count <= 4_194_304 else { throw Failure.response }
            return try read(count)
        }
        try send(["token": token, "role": "control"])
        guard try receive() == Data("ready".utf8) else { throw Failure.response }
        try send(["action": action])
        guard let result = try JSONSerialization.jsonObject(with: receive()) as? [String: Any] else {
            throw Failure.response
        }
        return result
    }
}
