import CompanionDomain

public enum ObservationFreshnessError: Error, Equatable, Sendable {
    case invalidTime
    case overflow
}

public enum ObservationPresentationState: String, Codable, CaseIterable, Sendable {
    case live
    case stale
    case unreachable
}

public struct ObservationAssessment: Equatable, Sendable {
    public let state: ObservationPresentationState
    public let estimatedAgeMilliseconds: Int64
    public let observedAtUnixMilliseconds: Int64
}

public struct ObservationFreshness: Equatable, Sendable {
    public static let maximumSafeInteger: Int64 = 9_007_199_254_740_991
    public let observedAtUnixMilliseconds: Int64
    public let responseSentAtUnixMilliseconds: Int64
    public let requestStartedAtMonotonicMilliseconds: Int64
    public let receivedAtMonotonicMilliseconds: Int64
    public let validForMilliseconds: Int64
    public let estimatedAgeAtReceiptMilliseconds: Int64
    public let expiresAtMonotonicMilliseconds: Int64

    public init(
        observedAtUnixMilliseconds: Int64,
        responseSentAtUnixMilliseconds: Int64,
        requestStartedAtMonotonicMilliseconds: Int64,
        receivedAtMonotonicMilliseconds: Int64,
        validForMilliseconds: Int64
    ) throws {
        guard observedAtUnixMilliseconds >= 0,
              observedAtUnixMilliseconds <= Self.maximumSafeInteger,
              responseSentAtUnixMilliseconds >= observedAtUnixMilliseconds,
              responseSentAtUnixMilliseconds <= Self.maximumSafeInteger,
              requestStartedAtMonotonicMilliseconds >= 0,
              receivedAtMonotonicMilliseconds >= requestStartedAtMonotonicMilliseconds,
              (1...60_000).contains(validForMilliseconds) else {
            throw ObservationFreshnessError.invalidTime
        }
        let hostAge = responseSentAtUnixMilliseconds - observedAtUnixMilliseconds
        let roundTrip = receivedAtMonotonicMilliseconds - requestStartedAtMonotonicMilliseconds
        guard hostAge <= Int64.max - roundTrip else {
            throw ObservationFreshnessError.overflow
        }
        let estimatedAge = hostAge + roundTrip
        let remaining = max(0, validForMilliseconds - min(validForMilliseconds, estimatedAge))
        guard receivedAtMonotonicMilliseconds <= Int64.max - remaining else {
            throw ObservationFreshnessError.overflow
        }

        self.observedAtUnixMilliseconds = observedAtUnixMilliseconds
        self.responseSentAtUnixMilliseconds = responseSentAtUnixMilliseconds
        self.requestStartedAtMonotonicMilliseconds = requestStartedAtMonotonicMilliseconds
        self.receivedAtMonotonicMilliseconds = receivedAtMonotonicMilliseconds
        self.validForMilliseconds = validForMilliseconds
        self.estimatedAgeAtReceiptMilliseconds = estimatedAge
        self.expiresAtMonotonicMilliseconds = receivedAtMonotonicMilliseconds + remaining
    }

    public func assess(
        reachability: ClientReachabilityState,
        monotonicNowMilliseconds: Int64
    ) throws -> ObservationAssessment {
        guard monotonicNowMilliseconds >= receivedAtMonotonicMilliseconds else {
            throw ObservationFreshnessError.invalidTime
        }
        let elapsed = monotonicNowMilliseconds - receivedAtMonotonicMilliseconds
        guard estimatedAgeAtReceiptMilliseconds <= Int64.max - elapsed else {
            throw ObservationFreshnessError.overflow
        }
        let state: ObservationPresentationState
        if reachability == .unreachable {
            state = .unreachable
        } else if monotonicNowMilliseconds < expiresAtMonotonicMilliseconds {
            state = .live
        } else {
            state = .stale
        }
        return ObservationAssessment(
            state: state,
            estimatedAgeMilliseconds: estimatedAgeAtReceiptMilliseconds + elapsed,
            observedAtUnixMilliseconds: observedAtUnixMilliseconds
        )
    }
}
