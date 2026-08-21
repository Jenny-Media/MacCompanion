import CompanionAgent
import Foundation

public enum AgentNetworkPairingContextErrorV0:
    Error,
    Equatable,
    Sendable
{
    case unavailable
    case staleListenerGeneration
    case staleAdvertisementGeneration
}

public struct AgentNetworkPairingContextSnapshotV0:
    Equatable,
    Sendable
{
    public let listenerReady: Bool
    public let advertisementReady: Bool
    public let terminal: Bool
    public let listenerGeneration: UInt64
    public let advertisementGeneration: UInt64
    public let pairingAvailable: Bool

    public init(
        listenerReady: Bool,
        advertisementReady: Bool,
        terminal: Bool,
        listenerGeneration: UInt64,
        advertisementGeneration: UInt64
    ) {
        self.listenerReady = listenerReady
        self.advertisementReady = advertisementReady
        self.terminal = terminal
        self.listenerGeneration = listenerGeneration
        self.advertisementGeneration = advertisementGeneration
        pairingAvailable = listenerReady && advertisementReady && !terminal
    }
}

/// Listener-lifetime source for the exact identity and endpoints encoded in a
/// local pairing QR. Pairing is unavailable until both the sealed listener and
/// its Bonjour registration are ready. Terminal teardown is nonthrowing and
/// permanently prevents a stale callback from re-enabling the source.
public actor AgentNetworkPairingContextAuthorityV0:
    AgentLocalPairingContextReadingV0
{
    private let context: AgentLocalPairingContextV0
    private var listenerReady = false
    private var advertisementReady = false
    private var terminal = false
    private var listenerGeneration: UInt64 = 0
    private var advertisementGeneration: UInt64 = 0

    public init(context: AgentLocalPairingContextV0) {
        self.context = context
    }

    public func publishListenerReadiness(
        ready: Bool,
        generation: UInt64
    ) throws {
        guard !terminal, generation > listenerGeneration else {
            throw AgentNetworkPairingContextErrorV0
                .staleListenerGeneration
        }
        listenerGeneration = generation
        listenerReady = ready
    }

    public func publishAdvertisementReadiness(
        ready: Bool,
        generation: UInt64
    ) throws {
        guard !terminal, generation > advertisementGeneration else {
            throw AgentNetworkPairingContextErrorV0
                .staleAdvertisementGeneration
        }
        advertisementGeneration = generation
        advertisementReady = ready
    }

    public func stop() {
        terminal = true
        listenerReady = false
        advertisementReady = false
    }

    public func currentPairingContext() throws
        -> AgentLocalPairingContextV0
    {
        guard listenerReady, advertisementReady, !terminal else {
            throw AgentNetworkPairingContextErrorV0.unavailable
        }
        return context
    }

    public func snapshot() -> AgentNetworkPairingContextSnapshotV0 {
        AgentNetworkPairingContextSnapshotV0(
            listenerReady: listenerReady,
            advertisementReady: advertisementReady,
            terminal: terminal,
            listenerGeneration: listenerGeneration,
            advertisementGeneration: advertisementGeneration
        )
    }
}
