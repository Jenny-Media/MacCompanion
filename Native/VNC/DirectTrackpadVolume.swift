#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
@preconcurrency import Citadel
@preconcurrency import NIO

enum DirectTrackpadVolume: Int, CaseIterable, Sendable {
    case read, decrease, increase, toggleMute

    static let admission = "mac-companion-volume-v1\n"
    static let maximumReplyBytes = 16
    static let step = 6

    struct Reading: Equatable {
        let level: Int
        let muted: Bool

        init?(response: String) {
            guard response.utf8.count <= DirectTrackpadVolume.maximumReplyBytes, response.hasSuffix("\n") else { return nil }
            let fields = response.dropLast().split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count == 2, let level = Int(fields[0]), (0...100).contains(level),
                  String(level) == fields[0], fields[1] == "0" || fields[1] == "1" else { return nil }
            self.level = level
            muted = fields[1] == "1"
        }
    }

    private var update: String {
        switch self {
        case .read:
            return ""
        case .decrease, .increase:
            let delta = self == .increase ? Self.step : -Self.step
            return """
                set targetLevel to oldLevel + (\(delta))
                if targetLevel < 0 then set targetLevel to 0
                if targetLevel > 100 then set targetLevel to 100
                if targetLevel is not oldLevel then set volume output volume targetLevel
                if output volume of (get volume settings) is not targetLevel then return "unavailable"
            """
        case .toggleMute:
            return """
                set targetMute to not (output muted of oldSettings)
                set volume output muted targetMute
                if output muted of (get volume settings) is not targetMute then return "unavailable"
            """
        }
    }

    var command: String {
        let script = """
            with timeout of 3 seconds
                set oldSettings to get volume settings
                set oldLevel to output volume of oldSettings
                if oldLevel is missing value then return "unavailable"
            \(update)
                set currentSettings to get volume settings
                set currentLevel to output volume of currentSettings
                if currentLevel is missing value then return "unavailable"
                if output muted of currentSettings then return (currentLevel as text) & ":1"
                return (currentLevel as text) & ":0"
            end timeout
            """
        // All interpolated content comes from this closed enum and fixed script.
        // The SSH channel can open while the UI is retiring. It cannot change
        // volume until that owner admits the command by writing the fixed line.
        let gate = """
            IFS= read -r admission && [ "$admission" = mac-companion-volume-v1 ] || exit 1
            exec /usr/bin/osascript -e \(Self.shellArgument(script))
            """
        return "/bin/sh -c " + Self.shellArgument(gate)
    }

    private static func shellArgument(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func run(client: SSHClient, isCurrent: @escaping @MainActor @Sendable () -> Bool) async -> String? {
        do {
            return try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask {
                    var reply = Data()
                    do {
                        try await client.withExec(command) { inbound, outbound in
                            guard await isCurrent() else { throw CancellationError() }
                            try Task.checkCancellation()
                            try await outbound.write(ByteBuffer(string: Self.admission))
                            for try await chunk in inbound {
                                if case .stdout(let bytes) = chunk {
                                    guard reply.count + bytes.readableBytes <= Self.maximumReplyBytes else {
                                        throw CocoaError(.fileReadCorruptFile)
                                    }
                                    reply.append(contentsOf: bytes.readableBytesView)
                                }
                            }
                        }
                    } catch ChannelError.alreadyClosed {
                        // The server can finish and close after supplying the reply.
                    }
                    guard await isCurrent(), !Task.isCancelled, let output = String(data: reply, encoding: .utf8),
                          Reading(response: output) != nil else { return nil }
                    return output
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw CancellationError()
                }
                defer { group.cancelAll() }
                return try await group.next() ?? nil
            }
        } catch { return nil }
    }
}
#endif
