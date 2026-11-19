#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
@preconcurrency import Citadel
@preconcurrency import NIO

enum DirectTrackpadVolume: Int, CaseIterable, Sendable {
    case read, decrease, increase, toggleMute

    static let admission = "mac-companion-volume-v1\n"
    static let maximumReplyBytes = 16
    static let step = 6
    static let operationTimeout: TimeAmount = .seconds(5)
    static let channelRetirementGrace: TimeAmount = .seconds(1)

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
        // Remote Login parses the outer command with the account's shell.
        // osascript combines its -e arguments into lines of the same script.
        let lines = script.split(separator: "\n").map { "-e \(Self.shellArgument(String($0)))" }
        let gate = #"IFS= read -r admission && [ "$admission" = mac-companion-volume-v1 ] || exit 1; "#
            + "exec /usr/bin/osascript " + lines.joined(separator: " ")
        return "/bin/sh -c " + Self.shellArgument(gate)
    }

    private static func shellArgument(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func run(
        client: SSHClient,
        isCurrent: @escaping @MainActor @Sendable () -> Bool,
        admit: @escaping @MainActor @Sendable (() -> Void) -> Bool = { action in action(); return true }
    ) async -> String? {
        let timeout = Duration.nanoseconds(Self.operationTimeout.nanoseconds)
        let deadline = ContinuousClock.now.advanced(by: timeout)
        do {
            var reply = Data()
            try Task.checkCancellation()
            let status = try await client.withExec(
                command, timeout: Self.operationTimeout, retirementGrace: Self.channelRetirementGrace
            ) { inbound, outbound in
                let admission = try await MainActor.run {
                    try Task.checkCancellation()
                    guard ContinuousClock.now < deadline, isCurrent() else { throw CancellationError() }
                    var pending: EventLoopFuture<Void>?
                    let admitted = admit { pending = outbound.enqueueWrite(ByteBuffer(string: Self.admission)) }
                    guard admitted, let write = pending else { throw CancellationError() }
                    return write
                }
                try await admission.get()
                for try await chunk in inbound {
                    if case .stdout(let bytes) = chunk {
                        guard reply.count + bytes.readableBytes <= Self.maximumReplyBytes else {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                        reply.append(contentsOf: bytes.readableBytesView)
                    }
                }
            }
            guard status == 0, await isCurrent(), !Task.isCancelled, ContinuousClock.now < deadline,
                  let output = String(data: reply, encoding: .utf8),
                  Reading(response: output) != nil else { return nil }
            return output
        } catch { return nil }
    }
}
#endif
