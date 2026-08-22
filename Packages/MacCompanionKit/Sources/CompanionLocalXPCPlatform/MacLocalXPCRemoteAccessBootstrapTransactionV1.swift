#if os(macOS)
import CompanionIPC
import CompanionLocalXPCPlatformC

public enum MacLocalXPCRemoteAccessBootstrapWireV1 {
    public static let maximumPayloadBytes =
        Int(MCLocalXPCMaximumBootstrapPayloadBytes)
}

/// Serializes the authentication-only bootstrap exchange for one exact peer
/// generation. The gate carries no remote authority and performs no durable
/// mutation; it only prevents reordering, overlap, and stale completion.
struct MacLocalXPCRemoteAccessBootstrapTransactionGateV1: Sendable {
    private enum Phase: Equatable, Sendable {
        case awaitingOfferRead
        case readingOffer(operation: UInt64)
        case offerReady(LocalRemoteAccessBootstrapOfferV0)
        case enabling(
            operation: UInt64,
            command: LocalRemoteAccessEnableCommandV0
        )
        case enabled(LocalRemoteAccessEnabledReceiptV0)
    }

    private(set) var currentGeneration: UInt64?
    private var phase: Phase?
    private var nextOperation: UInt64 = 0

    var currentOffer: LocalRemoteAccessBootstrapOfferV0? {
        guard case let .offerReady(offer) = phase else { return nil }
        return offer
    }

    var enabledReceipt: LocalRemoteAccessEnabledReceiptV0? {
        guard case let .enabled(receipt) = phase else { return nil }
        return receipt
    }

    mutating func bind(generation: UInt64) -> Bool {
        guard generation > 0,
              currentGeneration == nil,
              phase == nil else {
            return false
        }
        currentGeneration = generation
        phase = .awaitingOfferRead
        return true
    }

    mutating func beginOfferRead(
        generation: UInt64,
        permitted: Bool
    ) -> UInt64? {
        guard permitted,
              currentGeneration == generation,
              phase == .awaitingOfferRead,
              let operation = issueOperation() else {
            return nil
        }
        phase = .readingOffer(operation: operation)
        return operation
    }

    mutating func finishOfferRead(
        generation: UInt64,
        operation: UInt64,
        offer: LocalRemoteAccessBootstrapOfferV0
    ) -> Bool {
        guard currentGeneration == generation,
              phase == .readingOffer(operation: operation) else {
            return false
        }
        phase = .offerReady(offer)
        return true
    }

    mutating func beginEnable(
        generation: UInt64,
        permitted: Bool,
        command: LocalRemoteAccessEnableCommandV0
    ) -> UInt64? {
        guard permitted,
              currentGeneration == generation,
              case let .offerReady(offer) = phase,
              command.offer == offer,
              let operation = issueOperation() else {
            return nil
        }
        phase = .enabling(operation: operation, command: command)
        return operation
    }

    mutating func finishEnable(
        generation: UInt64,
        operation: UInt64,
        receipt: LocalRemoteAccessEnabledReceiptV0
    ) -> Bool {
        guard currentGeneration == generation,
              case let .enabling(activeOperation, command) = phase,
              activeOperation == operation else {
            return false
        }
        do {
            try receipt.validate(against: command)
        } catch {
            invalidateCurrent()
            return false
        }
        phase = .enabled(receipt)
        return true
    }

    /// Terminates only the still-current in-flight operation. A delayed error
    /// from an old operation or peer generation cannot invalidate replacement
    /// work.
    mutating func fail(
        generation: UInt64,
        operation: UInt64
    ) -> Bool {
        guard currentGeneration == generation,
              operationIsCurrent(operation) else {
            return false
        }
        invalidateCurrent()
        return true
    }

    @discardableResult
    mutating func invalidate(generation: UInt64) -> Bool {
        guard currentGeneration == generation else { return false }
        invalidateCurrent()
        return true
    }

    mutating func invalidateAll() {
        invalidateCurrent()
    }

    private mutating func issueOperation() -> UInt64? {
        guard nextOperation < UInt64.max else { return nil }
        nextOperation += 1
        return nextOperation
    }

    private func operationIsCurrent(_ operation: UInt64) -> Bool {
        switch phase {
        case let .readingOffer(activeOperation),
             let .enabling(activeOperation, _):
            activeOperation == operation
        case .awaitingOfferRead, .offerReady, .enabled, nil:
            false
        }
    }

    private mutating func invalidateCurrent() {
        currentGeneration = nil
        phase = nil
    }
}
#endif
