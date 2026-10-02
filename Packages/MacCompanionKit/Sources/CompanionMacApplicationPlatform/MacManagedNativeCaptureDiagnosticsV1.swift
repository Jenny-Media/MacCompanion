#if os(macOS)
import Darwin
import Foundation

/// Retain fixed diagnostic vocabulary while operation credentials and raw logs
/// are destroyed. No log line, target metadata or request material is emitted.
package enum MacManagedNativeCaptureDiagnosticsV1 {
    static func codes(in data: Data) -> [String] {
        let allowed: [String: Set<Int>] = [
            "selected-capture-context-error": Set(10...16),
            "selected-capture-stream-error": Set(1...6),
            "selected-capture-sample-rejected": Set(1...7).union(61...65),
        ]
        var result = Set<String>()
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "=", omittingEmptySubsequences: false)
            if fields.count == 2, let accepted = allowed[String(fields[0])],
               let value = Int(fields[1]), String(value) == fields[1], accepted.contains(value) {
                result.insert(String(fields[0]) + "=" + String(value))
            }
            if line.contains("Couldn't find any working encoder matching [videotoolbox]") {
                result.insert("no-working-encoder")
            }
        }
        return result.sorted()
    }

    static func codes(file: URL) -> [String] {
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var facts = stat()
        guard fstat(fd, &facts) == 0, (facts.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              facts.st_uid == geteuid(), facts.st_nlink == 1, facts.st_size > 0 else { return [] }
        let size = min(Int64(facts.st_size), 65_536)
        guard lseek(fd, facts.st_size - off_t(size), SEEK_SET) >= 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: Int(size))
        let count = bytes.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        guard count > 0 else { return [] }
        return codes(in: Data(bytes.prefix(count)))
    }
}
#endif
