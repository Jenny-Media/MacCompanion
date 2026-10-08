/// One local recovery reservation per actual background entry. A ticket owns
/// no authority: its unchanged Control binding must be checked before and after
/// every asynchronous replacement step. Old video/input admission stays retired.
public struct InteractiveNativeVideoForegroundRecoveryV0: Sendable {
    public struct Ticket: Equatable, Sendable {
        public let generation: UInt64
        public let binding: InteractiveNativeVideoBindingV0
    }
    private var generation: UInt64 = 0
    private var pending: Ticket?
    private var reserved: Ticket?
    public init() {}

    public mutating func background(binding: InteractiveNativeVideoBindingV0?) {
        cancel()
        guard generation < .max, let binding else { return }
        generation += 1
        pending = Ticket(generation: generation, binding: binding)
    }

    public mutating func resume(current: InteractiveNativeVideoBindingV0?,
        foreground: Bool, nowMonotonicMilliseconds: UInt64) -> Ticket? {
        guard foreground, let ticket = pending else { return nil }
        pending = nil
        guard current == ticket.binding,
              nowMonotonicMilliseconds < ticket.binding.expiresAtMonotonicMilliseconds else { return nil }
        reserved = ticket
        return ticket
    }

    public func isCurrent(_ ticket: Ticket) -> Bool { reserved == ticket }
    public mutating func cancel() { pending = nil; reserved = nil }
}
