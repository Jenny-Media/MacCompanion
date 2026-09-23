import CoreGraphics
import CoreVideo
import Foundation
@preconcurrency import WebRTC

enum SyntheticFrames {
    static let width = 1280
    static let height = 720

    static func make(sequence: UInt32, generation: UInt8) throws -> CVPixelBuffer {
        var output: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &output)
        guard status == kCVReturnSuccess, let output else { throw MediaProbeError.invalidFrame }
        guard CVPixelBufferLockBaseAddress(output, []) == kCVReturnSuccess else { throw MediaProbeError.invalidFrame }
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        guard let base = CVPixelBufferGetBaseAddress(output) else { throw MediaProbeError.invalidFrame }
        let stride = CVPixelBufferGetBytesPerRow(output) / 4
        let pixels = base.assumingMemoryBound(to: UInt32.self)
        let shift = Int(sequence % 360)
        for y in 0..<height {
            for x in 0..<width {
                let shade: UInt32 = ((x + shift) / 100 + y / 100) % 2 == 0 ? 0xFF305A70 : 0xFF90B8D0
                pixels[y * stride + x] = y < 96 ? 0xFF808080 : shade
            }
        }
        let value = (UInt64(generation) << 24) | UInt64(sequence & 0xFFFFFF)
        let check = UInt64(generation ^ UInt8(truncatingIfNeeded: sequence) ^ UInt8(truncatingIfNeeded: sequence >> 8) ^ UInt8(truncatingIfNeeded: sequence >> 16))
        let marker = (UInt64(0xA55A) << 40) | (value << 8) | check
        for bit in 0..<56 {
            let color: UInt32 = (marker >> (55 - bit)) & 1 == 1 ? 0xFFE0E0E0 : 0xFF202020
            for y in 12..<84 {
                for x in (64 + bit * 20)..<(64 + (bit + 1) * 20) { pixels[y * stride + x] = color }
            }
        }
        return output
    }

    static func read(_ frame: RTCVideoFrame) -> (UInt8, UInt32)? {
        let data = frame.buffer.toI420()
        var marker: UInt64 = 0
        let y = Int(data.height) * 48 / height
        for bit in 0..<56 {
            let x = Int(data.width) * (64 + bit * 20 + 10) / width
            let value = data.dataY[y * Int(data.strideY) + x]
            marker = (marker << 1) | (value > 128 ? 1 : 0)
        }
        guard marker >> 40 == 0xA55A else { return nil }
        let generation = UInt8(truncatingIfNeeded: marker >> 32)
        let sequence = UInt32(truncatingIfNeeded: marker >> 8) & 0xFFFFFF
        let check = generation ^ UInt8(truncatingIfNeeded: sequence) ^ UInt8(truncatingIfNeeded: sequence >> 8) ^ UInt8(truncatingIfNeeded: sequence >> 16)
        guard check == UInt8(truncatingIfNeeded: marker) else { return nil }
        return (generation, sequence)
    }
}

/// The marker is synthetic test content; retained measurements are bounded.
final class FrameSink: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    let generation: UInt8
    private var active = true
    private var received = 0
    private var invalid = 0
    private var wrongGeneration = 0
    private var backwards = 0
    private var lateCallbacks = 0
    private var lastSequence: UInt32?
    private var lastArrival: Double?
    private var longestGap = 0.0
    private var sent: [UInt32: Double] = [:]
    private var timings: [Double] = []
    private var timingIndex = 0
    private var display: RTCVideoRenderer?

    init(generation: UInt8) { self.generation = generation; super.init() }
    func setDisplay(_ display: RTCVideoRenderer?) { lock.withLock { self.display = display } }
    func sentFrame(_ sequence: UInt32) {
        lock.withLock {
            sent[sequence] = ProcessInfo.processInfo.systemUptime
            if sequence >= 512 { sent.removeValue(forKey: sequence - 512) }
        }
    }
    func setSize(_ size: CGSize) { lock.withLock { if active { display?.setSize(size) } } }
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        lock.withLock {
            guard active else { lateCallbacks += 1; return }
            guard let (generation, sequence) = SyntheticFrames.read(frame) else { invalid += 1; return }
            guard generation == self.generation else { wrongGeneration += 1; return }
            if let lastSequence, sequence <= lastSequence { backwards += 1; return }
            let now = ProcessInfo.processInfo.systemUptime
            if let lastArrival { longestGap = max(longestGap, now - lastArrival) }
            lastArrival = now; lastSequence = sequence; received += 1
            if let start = sent[sequence] {
                let value = (now - start) * 1000
                if timings.count < 5000 { timings.append(value) }
                else { timings[timingIndex] = value; timingIndex = (timingIndex + 1) % 5000 }
            }
            display?.renderFrame(frame)
        }
    }
    func retire() { lock.withLock { active = false; display?.renderFrame(nil); display = nil } }
    var count: Int { lock.withLock { received } }
    func summary() -> [String: Any] {
        lock.withLock {
            let sorted = timings.sorted()
            var result: [String: Any] = ["receivedValidFrames": received, "invalidMarkers": invalid,
                "wrongGenerationFrames": wrongGeneration, "nonIncreasingFrames": backwards,
                "rejectedLateCallbacks": lateCallbacks, "maximumInterFrameGapSeconds": longestGap,
                "retainedTimingSamples": sorted.count, "active": active]
            if let lastSequence { result["lastSequence"] = lastSequence }
            if !sorted.isEmpty {
                result["internalRoundTripP50Ms"] = sorted[(sorted.count - 1) / 2]
                result["internalRoundTripP95Ms"] = sorted[Int(Double(sorted.count - 1) * 0.95)]
            }
            return result
        }
    }
}
