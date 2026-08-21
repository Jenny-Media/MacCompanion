import CompanionIPC
import Foundation

public enum LocalInteractiveStopHandlerErrorV0: Error, Equatable, Sendable {
    case commandInFlight(UUID)
    case commandMismatch
    case remoteAuthorityNotEnded
    case runtimeTeardownIncomplete
}

public struct LocalInteractiveRemoteEndProofV0: Equatable, Sendable {
    public let deviceID: UUID
    public let requestID: UUID
    public let approvalID: UUID
    public let interactiveSessionID: UUID?
    public let remoteAuthorityEnded: Bool

    public init(
        deviceID: UUID,
        requestID: UUID,
        approvalID: UUID,
        interactiveSessionID: UUID?,
        remoteAuthorityEnded: Bool
    ) {
        self.deviceID = deviceID
        self.requestID = requestID
        self.approvalID = approvalID
        self.interactiveSessionID = interactiveSessionID
        self.remoteAuthorityEnded = remoteAuthorityEnded
    }

    fileprivate func validate(
        against command: LocalInteractiveStopCommandV0
    ) throws {
        guard deviceID == command.deviceID,
              requestID == command.requestID,
              approvalID == command.approvalID,
              interactiveSessionID == command.interactiveSessionID else {
            throw LocalInteractiveStopHandlerErrorV0.commandMismatch
        }
        guard remoteAuthorityEnded else {
            throw LocalInteractiveStopHandlerErrorV0.remoteAuthorityNotEnded
        }
    }
}

public struct LocalInteractiveRuntimeTeardownProofV0: Equatable, Sendable {
    public let deviceID: UUID
    public let requestID: UUID
    public let approvalID: UUID
    public let interactiveSessionID: UUID?
    public let runtimeTeardownComplete: Bool
    public let completedAtUnixMilliseconds: Int64

    public init(
        deviceID: UUID,
        requestID: UUID,
        approvalID: UUID,
        interactiveSessionID: UUID?,
        runtimeTeardownComplete: Bool,
        completedAtUnixMilliseconds: Int64
    ) {
        self.deviceID = deviceID
        self.requestID = requestID
        self.approvalID = approvalID
        self.interactiveSessionID = interactiveSessionID
        self.runtimeTeardownComplete = runtimeTeardownComplete
        self.completedAtUnixMilliseconds = completedAtUnixMilliseconds
    }

    fileprivate func validate(
        against command: LocalInteractiveStopCommandV0
    ) throws {
        guard deviceID == command.deviceID,
              requestID == command.requestID,
              approvalID == command.approvalID,
              interactiveSessionID == command.interactiveSessionID,
              completedAtUnixMilliseconds
                >= command.occurredAtUnixMilliseconds else {
            throw LocalInteractiveStopHandlerErrorV0.commandMismatch
        }
        guard runtimeTeardownComplete else {
            throw LocalInteractiveStopHandlerErrorV0.runtimeTeardownIncomplete
        }
    }
}

public protocol LocalInteractiveRemoteAuthorityEndingV0: Sendable {
    /// Idempotently removes the exact pending approval or active session from
    /// all remote admission paths before returning success.
    func endRemoteAuthority(
        for command: LocalInteractiveStopCommandV0
    ) async throws -> LocalInteractiveRemoteEndProofV0
}

public protocol LocalInteractiveRuntimeTearingDownV0: Sendable {
    /// Idempotently obtains the menu runtime's complete safety teardown proof.
    /// For a still-pending session this proves that no runtime was installed.
    func teardownRuntime(
        for command: LocalInteractiveStopCommandV0,
        after remoteEnd: LocalInteractiveRemoteEndProofV0
    ) async throws -> LocalInteractiveRuntimeTeardownProofV0
}

/// Enforces the safety order: remote authority is closed first, visible-menu
/// runtime teardown is proven second, and only then can local presentation show
/// the session as stopped.
public actor LocalInteractiveStopHandlerV0 {
    public static let maximumCompletedStops = 128

    private struct Completion: Sendable {
        let command: LocalInteractiveStopCommandV0
        let receipt: LocalInteractiveStoppedReceiptV0
    }

    private let remote: any LocalInteractiveRemoteAuthorityEndingV0
    private let runtime: any LocalInteractiveRuntimeTearingDownV0
    private let auditWriter: (any LocalInteractiveStopAuditWritingV0)?
    private var inFlight: Set<UUID> = []
    private var completions: [UUID: Completion] = [:]
    private var completionOrder: [UUID] = []

    public init(
        remote: any LocalInteractiveRemoteAuthorityEndingV0,
        runtime: any LocalInteractiveRuntimeTearingDownV0,
        auditWriter: (any LocalInteractiveStopAuditWritingV0)? = nil
    ) {
        self.remote = remote
        self.runtime = runtime
        self.auditWriter = auditWriter
    }

    public func handle(
        _ command: LocalInteractiveStopCommandV0
    ) async throws -> LocalInteractiveStoppedReceiptV0 {
        if let completion = completions[command.commandID] {
            guard completion.command == command else {
                throw LocalInteractiveStopHandlerErrorV0.commandMismatch
            }
            return completion.receipt
        }
        guard !inFlight.contains(command.commandID) else {
            throw LocalInteractiveStopHandlerErrorV0.commandInFlight(
                command.commandID
            )
        }
        inFlight.insert(command.commandID)
        defer { inFlight.remove(command.commandID) }

        let remoteEnd = try await remote.endRemoteAuthority(for: command)
        try remoteEnd.validate(against: command)
        let teardown = try await runtime.teardownRuntime(
            for: command,
            after: remoteEnd
        )
        try teardown.validate(against: command)
        let receipt = try LocalInteractiveStoppedReceiptV0(
            correlationID: command.commandID,
            deviceID: command.deviceID,
            requestID: command.requestID,
            approvalID: command.approvalID,
            interactiveSessionID: command.interactiveSessionID,
            reason: command.reason,
            remoteAuthorityEnded: remoteEnd.remoteAuthorityEnded,
            runtimeTeardownComplete: teardown.runtimeTeardownComplete,
            completedAtUnixMilliseconds: teardown.completedAtUnixMilliseconds
        )
        try receipt.validate(against: command)
        await auditWriter?.recordCompletedStop(
            command: command,
            receipt: receipt
        )
        retain(command: command, receipt: receipt)
        return receipt
    }

    private func retain(
        command: LocalInteractiveStopCommandV0,
        receipt: LocalInteractiveStoppedReceiptV0
    ) {
        completions[command.commandID] = Completion(
            command: command,
            receipt: receipt
        )
        completionOrder.append(command.commandID)
        if completionOrder.count > Self.maximumCompletedStops {
            let evicted = completionOrder.removeFirst()
            completions.removeValue(forKey: evicted)
        }
    }
}
