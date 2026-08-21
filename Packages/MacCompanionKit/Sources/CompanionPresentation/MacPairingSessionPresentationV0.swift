import CompanionIPC
import Foundation

public enum MacPairingSessionPresentationErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidPhase
    case receiptMismatch
    case completionBeforeCreation
}

public enum MacPairingSessionPresentationPhaseV0:
    Equatable,
    Sendable
{
    case idle
    case creating(LocalPairingSessionCreateCommandV0)
    case creationFailed(LocalPairingSessionCreateCommandV0)
    case presenting(LocalPairingSessionCreatedReceiptV0)
    case dismissing(
        LocalPairingSessionCreatedReceiptV0,
        LocalPairingSessionDismissCommandV0
    )
    case dismissalFailed(
        LocalPairingSessionCreatedReceiptV0,
        LocalPairingSessionDismissCommandV0
    )
}

/// Pure menu-app reducer for secret-bearing pairing IPC. It emits commands and
/// consumes validated receipts but owns no transport, peer trust, clock,
/// entropy, or pairing authority. Failed response delivery retains the exact
/// command so retry cannot create or dismiss a different session implicitly.
public struct MacPairingSessionPresentationV0: Equatable, Sendable {
    public private(set) var phase: MacPairingSessionPresentationPhaseV0

    public init() {
        phase = .idle
    }

    public var visibleReceipt: LocalPairingSessionCreatedReceiptV0? {
        switch phase {
        case let .presenting(receipt),
             let .dismissing(receipt, _),
             let .dismissalFailed(receipt, _):
            receipt
        case .idle, .creating, .creationFailed:
            nil
        }
    }

    public var interactionEnabled: Bool {
        switch phase {
        case .presenting, .creationFailed, .dismissalFailed:
            true
        case .idle, .creating, .dismissing:
            false
        }
    }

    public mutating func begin(
        commandID: UUID
    ) throws -> LocalPairingSessionCreateCommandV0 {
        guard case .idle = phase else {
            throw MacPairingSessionPresentationErrorV0.invalidPhase
        }
        let command = try LocalPairingSessionCreateCommandV0(
            commandID: commandID
        )
        phase = .creating(command)
        return command
    }

    public mutating func creationFailed() throws {
        guard case let .creating(command) = phase else {
            throw MacPairingSessionPresentationErrorV0.invalidPhase
        }
        phase = .creationFailed(command)
    }

    public mutating func retryCreation() throws
        -> LocalPairingSessionCreateCommandV0
    {
        guard case let .creationFailed(command) = phase else {
            throw MacPairingSessionPresentationErrorV0.invalidPhase
        }
        phase = .creating(command)
        return command
    }

    public mutating func receiveCreated(
        _ receipt: LocalPairingSessionCreatedReceiptV0
    ) throws {
        guard case let .creating(command) = phase else {
            throw MacPairingSessionPresentationErrorV0.invalidPhase
        }
        guard receipt.correlationID == command.commandID else {
            throw MacPairingSessionPresentationErrorV0.receiptMismatch
        }
        phase = .presenting(receipt)
    }

    public mutating func requestDismissal(
        commandID: UUID
    ) throws -> LocalPairingSessionDismissCommandV0 {
        guard case let .presenting(receipt) = phase else {
            throw MacPairingSessionPresentationErrorV0.invalidPhase
        }
        let command = try LocalPairingSessionDismissCommandV0(
            commandID: commandID,
            pairingID: receipt.pairingID
        )
        phase = .dismissing(receipt, command)
        return command
    }

    public mutating func dismissalFailed() throws {
        guard case let .dismissing(receipt, command) = phase else {
            throw MacPairingSessionPresentationErrorV0.invalidPhase
        }
        phase = .dismissalFailed(receipt, command)
    }

    public mutating func retryDismissal() throws
        -> LocalPairingSessionDismissCommandV0
    {
        guard case let .dismissalFailed(receipt, command) = phase else {
            throw MacPairingSessionPresentationErrorV0.invalidPhase
        }
        phase = .dismissing(receipt, command)
        return command
    }

    public mutating func receiveDismissed(
        _ receipt: LocalPairingSessionDismissedReceiptV0
    ) throws {
        guard case let .dismissing(created, command) = phase else {
            throw MacPairingSessionPresentationErrorV0.invalidPhase
        }
        guard receipt.correlationID == command.commandID,
              receipt.pairingID == command.pairingID else {
            throw MacPairingSessionPresentationErrorV0.receiptMismatch
        }
        guard receipt.completedAtUnixMilliseconds
                >= created.createdAtUnixMilliseconds else {
            throw MacPairingSessionPresentationErrorV0
                .completionBeforeCreation
        }
        phase = .idle
    }

    /// Agent loss, listener loss, logout, expiry notification, or local app
    /// teardown immediately removes the secret-bearing receipt from UI state.
    public mutating func invalidate() {
        phase = .idle
    }
}
