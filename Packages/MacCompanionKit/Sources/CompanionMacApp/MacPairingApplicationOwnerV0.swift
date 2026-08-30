import CompanionIPC
import CompanionPresentation
import Foundation

public protocol MacPairingLocalIPCClientV0: Sendable {
    func createPairingSession(
        _ command: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0

    func dismissPairingSession(
        _ command: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0
}

public protocol MacPairingWallClockV0: Sendable {
    func nowUnixMilliseconds() -> Int64
}

public struct SystemMacPairingWallClockV0: MacPairingWallClockV0 {
    public init() {}

    public func nowUnixMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
}

public protocol MacPairingExpiryCancellationV0: Sendable {
    func cancel()
}

public protocol MacPairingExpirySchedulingV0: Sendable {
    func schedule(
        afterMilliseconds: Int64,
        action: @escaping @Sendable () async -> Void
    ) -> any MacPairingExpiryCancellationV0
}

private final class SystemMacPairingExpiryCancellationV0:
    MacPairingExpiryCancellationV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        let task = lock.withLock {
            defer { self.task = nil }
            return self.task
        }
        task?.cancel()
    }
}

public struct SystemMacPairingExpirySchedulerV0:
    MacPairingExpirySchedulingV0
{
    public init() {}

    public func schedule(
        afterMilliseconds: Int64,
        action: @escaping @Sendable () async -> Void
    ) -> any MacPairingExpiryCancellationV0 {
        let boundedDelay = UInt64(max(0, afterMilliseconds))
        let task = Task {
            do {
                try await Task.sleep(
                    nanoseconds: boundedDelay.multipliedReportingOverflow(
                        by: 1_000_000
                    ).partialValue
                )
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await action()
        }
        return SystemMacPairingExpiryCancellationV0(task: task)
    }
}

public enum MacPairingApplicationOwnerErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidPhase
    case commandIDReuse
    case revisionExhausted
}

/// Bundle-independent menu-app composition for the secret-bearing pairing
/// sheet. The Agent remains the sole pairing authority. This owner only sends
/// authenticated local commands, retains exact commands across response loss,
/// fences delayed replies after Agent loss, and removes expired QR material.
public actor MacPairingApplicationOwnerV0 {
    public typealias CommandIDSource = @Sendable () -> UUID
    public typealias StateChanged =
        @Sendable (MacPairingSessionPresentationV0) async -> Void

    private let client: any MacPairingLocalIPCClientV0
    private let clock: any MacPairingWallClockV0
    private let expiryScheduler: any MacPairingExpirySchedulingV0
    private let commandIDSource: CommandIDSource
    private let stateChanged: StateChanged

    private var presentation = MacPairingSessionPresentationV0()
    private var revision: UInt64 = 0
    private var inFlightRevision: UInt64?
    private var issuedCommandIDs: Set<UUID> = []
    private var expiryCancellation:
        (any MacPairingExpiryCancellationV0)?

    public init(
        client: any MacPairingLocalIPCClientV0,
        clock: any MacPairingWallClockV0 = SystemMacPairingWallClockV0(),
        expiryScheduler: any MacPairingExpirySchedulingV0 =
            SystemMacPairingExpirySchedulerV0(),
        commandIDSource: @escaping CommandIDSource = { UUID() },
        stateChanged: @escaping StateChanged = { _ in }
    ) {
        self.client = client
        self.clock = clock
        self.expiryScheduler = expiryScheduler
        self.commandIDSource = commandIDSource
        self.stateChanged = stateChanged
    }

    public func snapshot() -> MacPairingSessionPresentationV0 {
        presentation
    }

    public func begin() async throws {
        guard case .idle = presentation.phase,
              inFlightRevision == nil else {
            throw MacPairingApplicationOwnerErrorV0.invalidPhase
        }
        let commandID = try issueCommandID()
        let command: LocalPairingSessionCreateCommandV0
        do {
            command = try presentation.begin(commandID: commandID)
        } catch {
            throw MacPairingApplicationOwnerErrorV0.invalidPhase
        }
        let operationRevision = try startOperation()
        await publish()
        guard operationRevision == revision else { return }
        await performCreate(command, operationRevision: operationRevision)
    }

    public func retryCreation() async throws {
        guard inFlightRevision == nil else {
            throw MacPairingApplicationOwnerErrorV0.invalidPhase
        }
        let command: LocalPairingSessionCreateCommandV0
        do {
            command = try presentation.retryCreation()
        } catch {
            throw MacPairingApplicationOwnerErrorV0.invalidPhase
        }
        let operationRevision = try startOperation()
        await publish()
        guard operationRevision == revision else { return }
        await performCreate(command, operationRevision: operationRevision)
    }

    public func requestDismissal() async throws {
        guard inFlightRevision == nil else {
            throw MacPairingApplicationOwnerErrorV0.invalidPhase
        }
        let commandID = try issueCommandID()
        let command: LocalPairingSessionDismissCommandV0
        do {
            command = try presentation.requestDismissal(commandID: commandID)
        } catch {
            throw MacPairingApplicationOwnerErrorV0.invalidPhase
        }
        cancelExpiry()
        let operationRevision = try startOperation()
        await publish()
        guard operationRevision == revision else { return }
        await performDismiss(command, operationRevision: operationRevision)
    }

    public func retryDismissal() async throws {
        guard inFlightRevision == nil else {
            throw MacPairingApplicationOwnerErrorV0.invalidPhase
        }
        let command: LocalPairingSessionDismissCommandV0
        do {
            command = try presentation.retryDismissal()
        } catch {
            throw MacPairingApplicationOwnerErrorV0.invalidPhase
        }
        cancelExpiry()
        let operationRevision = try startOperation()
        await publish()
        guard operationRevision == revision else { return }
        await performDismiss(command, operationRevision: operationRevision)
    }

    /// A successfully validated local pairing decision consumes the exact QR
    /// authority in the Agent. Mirror that terminal fact into the menu
    /// presentation without sending a redundant dismissal command. The exact
    /// pairing identifier prevents a delayed decision for an older session
    /// from removing a newer code.
    @discardableResult
    public func pairingDecisionCompleted(pairingID: UUID) async -> Bool {
        guard presentation.visibleReceipt?.pairingID == pairingID else {
            return false
        }
        cancelExpiry()
        invalidateCurrentRevision()
        presentation.invalidate()
        await publish()
        return true
    }

    /// Listener loss, Agent invalidation, logout, or app teardown is terminal
    /// for every currently displayed or in-flight pairing result.
    public func agentInvalidated() async {
        cancelExpiry()
        invalidateCurrentRevision()
        presentation.invalidate()
        await publish()
    }

    private func performCreate(
        _ command: LocalPairingSessionCreateCommandV0,
        operationRevision: UInt64
    ) async {
        do {
            let receipt = try await client.createPairingSession(command)
            guard operationRevision == revision,
                  inFlightRevision == operationRevision else { return }
            inFlightRevision = nil
            do {
                try presentation.receiveCreated(receipt)
            } catch {
                try? presentation.creationFailed()
                await publish()
                return
            }
            armExpiry(for: receipt, expectedRevision: operationRevision)
            await publish()
        } catch {
            guard operationRevision == revision,
                  inFlightRevision == operationRevision else { return }
            inFlightRevision = nil
            try? presentation.creationFailed()
            await publish()
        }
    }

    private func performDismiss(
        _ command: LocalPairingSessionDismissCommandV0,
        operationRevision: UInt64
    ) async {
        do {
            let receipt = try await client.dismissPairingSession(command)
            guard operationRevision == revision,
                  inFlightRevision == operationRevision else { return }
            inFlightRevision = nil
            do {
                try presentation.receiveDismissed(receipt)
            } catch {
                try? presentation.dismissalFailed()
                if let visibleReceipt = presentation.visibleReceipt {
                    armExpiry(
                        for: visibleReceipt,
                        expectedRevision: operationRevision
                    )
                }
                await publish()
                return
            }
            cancelExpiry()
            await publish()
        } catch {
            guard operationRevision == revision,
                  inFlightRevision == operationRevision else { return }
            inFlightRevision = nil
            try? presentation.dismissalFailed()
            if let visibleReceipt = presentation.visibleReceipt {
                armExpiry(
                    for: visibleReceipt,
                    expectedRevision: operationRevision
                )
            }
            await publish()
        }
    }

    private func armExpiry(
        for receipt: LocalPairingSessionCreatedReceiptV0,
        expectedRevision: UInt64
    ) {
        cancelExpiry()
        let now = clock.nowUnixMilliseconds()
        let effectiveNow: Int64
        if now < 0 {
            effectiveNow = receipt.expiresAtUnixMilliseconds
        } else {
            effectiveNow = max(receipt.createdAtUnixMilliseconds, now)
        }
        let remaining = max(
            0,
            receipt.expiresAtUnixMilliseconds - min(
                effectiveNow,
                receipt.expiresAtUnixMilliseconds
            )
        )
        expiryCancellation = expiryScheduler.schedule(
            afterMilliseconds: remaining
        ) { [weak self] in
            await self?.expire(
                pairingID: receipt.pairingID,
                expectedRevision: expectedRevision
            )
        }
    }

    private func expire(
        pairingID: UUID,
        expectedRevision: UInt64
    ) async {
        guard expectedRevision == revision,
              presentation.visibleReceipt?.pairingID == pairingID else {
            return
        }
        expiryCancellation = nil
        invalidateCurrentRevision()
        presentation.invalidate()
        await publish()

        guard let commandID = try? issueCommandID(),
              let command = try? LocalPairingSessionDismissCommandV0(
                commandID: commandID,
                pairingID: pairingID
              ) else { return }
        _ = try? await client.dismissPairingSession(command)
    }

    private func issueCommandID() throws -> UUID {
        let value = commandIDSource()
        guard issuedCommandIDs.insert(value).inserted else {
            throw MacPairingApplicationOwnerErrorV0.commandIDReuse
        }
        return value
    }

    private func startOperation() throws -> UInt64 {
        guard revision < UInt64.max else {
            throw MacPairingApplicationOwnerErrorV0.revisionExhausted
        }
        revision += 1
        inFlightRevision = revision
        return revision
    }

    private func invalidateCurrentRevision() {
        if revision < UInt64.max { revision += 1 }
        inFlightRevision = nil
    }

    private func cancelExpiry() {
        expiryCancellation?.cancel()
        expiryCancellation = nil
    }

    private func publish() async {
        await stateChanged(presentation)
    }
}
