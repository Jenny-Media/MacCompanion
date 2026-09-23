import Foundation
@preconcurrency import WebRTC

func emitProbeRecord(_ value: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
    }
}

@main
enum RoundTripMain {
    static func main() {
        DispatchQueue.global(qos: .userInitiated).async {
            do { try run(); exit(0) }
            catch { emitProbeRecord(["event": "failure", "error": String(describing: error)]); exit(1) }
        }
        dispatchMain()
    }
    static func run() throws {
        guard RTCInitializeSSL() else { throw MediaProbeError.missingPeer }
        let args = CommandLine.arguments
        func option(_ name: String, _ fallback: Int) -> Int {
            guard let index = args.firstIndex(of: name), index + 1 < args.count else { return fallback }
            return Int(args[index + 1]) ?? fallback
        }
        let seconds = max(3, min(3600, option("--seconds", 15)))
        let cycles = max(1, min(10, option("--cycles", 1)))
        let localNetworkOnly = args.contains("--lan-only")
        for cycle in 1...cycles {
            let sink = FrameSink(generation: UInt8(cycle))
            let sender = try MediaPeer(sending: true, sink: FrameSink(generation: UInt8(cycle)), localNetworkOnly: localNetworkOnly)
            let receiver = try MediaPeer(sending: false, sink: sink, localNetworkOnly: localNetworkOnly)
            defer { sender.close(); receiver.close() }
            let started = ProcessInfo.processInfo.systemUptime
            let answer = try receiver.answer(sender.offer())
            try sender.acceptAnswer(answer)
            var sequence: UInt32 = 0
            var firstFrame: Double?
            var next = ProcessInfo.processInfo.systemUptime
            let end = next + Double(seconds)
            var nextReport = next + 10
            var restartDone = false
            var beforeRestart = 0
            while ProcessInfo.processInfo.systemUptime < end {
                let now = ProcessInfo.processInfo.systemUptime
                if args.contains("--ice-restart"), !restartDone, sequence >= 60 {
                    beforeRestart = sink.count
                    try sender.acceptAnswer(receiver.answer(sender.offer(restart: true)))
                    restartDone = true
                    next = ProcessInfo.processInfo.systemUptime
                }
                sequence += 1
                try autoreleasepool {
                    let frame = try SyntheticFrames.make(sequence: sequence, generation: UInt8(cycle))
                    sink.sentFrame(sequence)
                    sender.submit(frame, timestampNs: Int64(now * 1_000_000_000))
                }
                if firstFrame == nil, sink.count > 0 { firstFrame = now - started }
                if now >= nextReport {
                    emitProbeRecord(["event": "progress", "cycle": cycle, "elapsedSeconds": now - started, "frames": sink.summary()])
                    nextReport = now + 10
                }
                next += 1.0 / 30
                Thread.sleep(forTimeInterval: max(0, next - ProcessInfo.processInfo.systemUptime))
            }
            let senderStats = try sender.statistics()
            let receiverStats = try receiver.statistics()
            receiver.close(); sender.close()
            let stoppedCount = sink.count
            Thread.sleep(forTimeInterval: 0.35)
            let stopPassed = sink.count == stoppedCount
            let report = sink.summary()
            let codecPassed = (senderStats + receiverStats).contains { ($0["mimeType"] as? String)?.lowercased() == "video/h264" }
            let receivedEnough = sink.count >= max(30, Int(sequence) / 2)
            let valid = (report["invalidMarkers"] as? Int) == 0 && (report["wrongGenerationFrames"] as? Int) == 0 && (report["nonIncreasingFrames"] as? Int) == 0
            let restartPassed = !args.contains("--ice-restart") || (restartDone && sink.count > beforeRestart + 10)
            let passed = stopPassed && codecPassed && receivedEnough && valid && restartPassed
            emitProbeRecord(["event": "result", "cycle": cycle, "passed": passed, "durationSeconds": seconds,
                "localNetworkOnly": localNetworkOnly,
                "sentFrames": sequence, "frames": report, "firstFrameSeconds": firstFrame ?? -1,
                "stopPassed": stopPassed, "iceRestartPassed": restartPassed, "iceRestartAttempted": restartDone,
                "senderStats": senderStats, "receiverStats": receiverStats,
                "physicalNetworkTested": false, "glassLatencyMeasured": false])
            if !passed { throw MediaProbeError.invalidFrame }
        }
    }
}
