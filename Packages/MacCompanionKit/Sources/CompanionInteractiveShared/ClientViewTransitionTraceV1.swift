import Foundation

/// Local timing only. Contains no host identity, window name, image or input.
public struct ClientViewTransitionTraceV1: Sendable {
    public enum Stage: String, Sendable {
        case fenced, rendererDrained, enrollmentDrained, hostAcknowledged
        case nativePrepared, firstFrame, inputReady, cancelled, failed
    }
    public let attemptID: UUID
    private let startedAtNanoseconds: UInt64
    public init(attemptID: UUID = UUID(), nowNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        self.attemptID = attemptID
        startedAtNanoseconds = nowNanoseconds
    }
    public func elapsedMilliseconds(nowNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds) -> UInt64 {
        nowNanoseconds >= startedAtNanoseconds ? (nowNanoseconds - startedAtNanoseconds) / 1_000_000 : 0
    }
}
