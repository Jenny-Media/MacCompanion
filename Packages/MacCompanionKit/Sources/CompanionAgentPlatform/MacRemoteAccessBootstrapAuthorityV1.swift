import CompanionIPC
import Foundation

public enum MacRemoteAccessBootstrapAuthorityErrorV1:
    Error,
    Equatable,
    Sendable
{
    case invalidGeneration
    case staleGeneration
    case operationInProgress
    case generationExhausted
    case unsafeDurableState
    case alreadyEnabled
    case offerUnavailable
    case offerExpired
    case commandMismatch
    case storageAmbiguous
    case invalidTime
}

/// Agent-owned durable authority for the disabled-to-enabled transition. It
/// creates no listener, registers no login role, and grants no Observe, Act,
/// or Control capability. Every storage suspension is fenced by peer generation
/// and a monotonic operation identity so actor reentrancy cannot revive stale
/// work.
public actor MacRemoteAccessBootstrapAuthorityV1 {
    public typealias OfferIDSource = @Sendable () -> UUID

    private struct ActiveOperation: Equatable, Sendable {
        let generation: UInt64
        let identifier: UInt64
    }

    private struct CompletedEnable: Sendable {
        let command: LocalRemoteAccessEnableCommandV0
        let receipt: LocalRemoteAccessEnabledReceiptV0
    }

    private let intentStore: any MacRemoteAccessIntentPersistenceV1
    private let wallClock: any MacDashboardLifecycleWallClockV1
    private let offerIDSource: OfferIDSource
    private var highestGeneration: UInt64 = 0
    private var currentGeneration: UInt64?
    private var nextOperation: UInt64 = 0
    private var activeOperation: ActiveOperation?
    private var currentOffer: LocalRemoteAccessBootstrapOfferV0?
    private var completedEnable: CompletedEnable?

    public init(
        intentStore: any MacRemoteAccessIntentPersistenceV1,
        wallClock: any MacDashboardLifecycleWallClockV1 =
            SystemMacDashboardLifecycleWallClockV1(),
        offerIDSource: @escaping OfferIDSource = { UUID() }
    ) {
        self.intentStore = intentStore
        self.wallClock = wallClock
        self.offerIDSource = offerIDSource
    }

    public func readOffer(
        generation: UInt64
    ) async throws -> LocalRemoteAccessBootstrapOfferV0 {
        let operation = try beginRead(generation: generation)
        do {
            let durable = try await intentStore.current()
            try requireCurrent(operation)
            guard durable?.desiredEnabled != true else {
                throw MacRemoteAccessBootstrapAuthorityErrorV1.alreadyEnabled
            }
            let durableRevision = durable?.revision ?? 0
            guard durableRevision <
                    MacRemoteAccessIntentSnapshotV1.maximumSafeInteger,
                  let expectedRevision = Int64(exactly: durableRevision)
            else {
                throw MacRemoteAccessBootstrapAuthorityErrorV1
                    .unsafeDurableState
            }

            let now = wallClock.nowUnixMilliseconds()
            if let currentOffer {
                guard currentOffer.expectedIntentRevision
                        == expectedRevision else {
                    throw MacRemoteAccessBootstrapAuthorityErrorV1
                        .unsafeDurableState
                }
                guard now >= currentOffer.createdAtUnixMilliseconds,
                      now < currentOffer.expiresAtUnixMilliseconds else {
                    throw MacRemoteAccessBootstrapAuthorityErrorV1
                        .offerExpired
                }
                finish(operation)
                return currentOffer
            }

            let expiresAt: Int64
            let (candidate, overflow) = now.addingReportingOverflow(300_000)
            guard now >= 0, !overflow else {
                throw MacRemoteAccessBootstrapAuthorityErrorV1.invalidTime
            }
            expiresAt = candidate
            let offer: LocalRemoteAccessBootstrapOfferV0
            do {
                offer = try LocalRemoteAccessBootstrapOfferV0(
                    offerID: offerIDSource(),
                    expectedIntentRevision: expectedRevision,
                    createdAtUnixMilliseconds: now,
                    expiresAtUnixMilliseconds: expiresAt
                )
            } catch {
                throw MacRemoteAccessBootstrapAuthorityErrorV1.invalidTime
            }
            try requireCurrent(operation)
            currentOffer = offer
            finish(operation)
            return offer
        } catch {
            terminalizeIfCurrent(operation)
            throw map(error)
        }
    }

    public func enable(
        generation: UInt64,
        command: LocalRemoteAccessEnableCommandV0
    ) async throws -> LocalRemoteAccessEnabledReceiptV0 {
        if currentGeneration == generation,
           let completedEnable,
           completedEnable.command == command {
            return completedEnable.receipt
        }

        let operation = try beginEnable(
            generation: generation,
            command: command
        )
        do {
            let now = wallClock.nowUnixMilliseconds()
            guard now >= command.confirmedAtUnixMilliseconds,
                  now < command.offer.expiresAtUnixMilliseconds else {
                throw MacRemoteAccessBootstrapAuthorityErrorV1.offerExpired
            }

            let before = try await intentStore.current()
            try requireCurrent(operation)
            if let replay = try exactDurableReplay(
                before,
                command: command,
                nowUnixMilliseconds: now
            ) {
                completedEnable = .init(
                    command: command,
                    receipt: replay
                )
                finish(operation)
                return replay
            }

            let expectedRevision = UInt64(
                command.offer.expectedIntentRevision
            )
            guard before?.desiredEnabled != true,
                  (before?.revision ?? 0) == expectedRevision else {
                throw MacRemoteAccessBootstrapAuthorityErrorV1
                    .commandMismatch
            }
            let successor = expectedRevision + 1
            let snapshot: MacRemoteAccessIntentSnapshotV1
            do {
                snapshot = try MacRemoteAccessIntentSnapshotV1(
                    revision: successor,
                    desiredEnabled: true,
                    commandID: command.commandID,
                    recordedAtUnixMilliseconds: now
                )
            } catch {
                throw MacRemoteAccessBootstrapAuthorityErrorV1
                    .unsafeDurableState
            }

            do {
                _ = try await intentStore.replaceAtomically(
                    snapshot,
                    expectedRevision: before?.revision
                )
            } catch {
                // A rename may have committed even when a later sync failed.
                // Only exact durable read-back can convert that ambiguity into
                // success; every other shape remains terminal.
            }
            try requireCurrent(operation)
            let after = try await intentStore.current()
            try requireCurrent(operation)
            guard after == snapshot else {
                throw MacRemoteAccessBootstrapAuthorityErrorV1
                    .storageAmbiguous
            }

            let receipt: LocalRemoteAccessEnabledReceiptV0
            do {
                receipt = try LocalRemoteAccessEnabledReceiptV0(
                    correlationID: command.commandID,
                    offerID: command.offer.offerID,
                    intentRevision: Int64(successor),
                    completedAtUnixMilliseconds:
                        snapshot.recordedAtUnixMilliseconds
                )
                try receipt.validate(against: command)
            } catch {
                throw MacRemoteAccessBootstrapAuthorityErrorV1
                    .unsafeDurableState
            }
            completedEnable = .init(command: command, receipt: receipt)
            finish(operation)
            return receipt
        } catch {
            terminalizeIfCurrent(operation)
            throw map(error)
        }
    }

    public func invalidate(generation: UInt64) {
        guard currentGeneration == generation else { return }
        terminalizeCurrentGeneration()
    }

    private func beginRead(
        generation: UInt64
    ) throws -> ActiveOperation {
        guard generation > 0 else {
            throw MacRemoteAccessBootstrapAuthorityErrorV1.invalidGeneration
        }
        if currentGeneration != generation {
            guard generation > highestGeneration else {
                throw MacRemoteAccessBootstrapAuthorityErrorV1.staleGeneration
            }
            highestGeneration = generation
            currentGeneration = generation
            activeOperation = nil
            currentOffer = nil
            completedEnable = nil
        }
        return try beginOperation(generation: generation)
    }

    private func beginEnable(
        generation: UInt64,
        command: LocalRemoteAccessEnableCommandV0
    ) throws -> ActiveOperation {
        guard generation > 0 else {
            throw MacRemoteAccessBootstrapAuthorityErrorV1.invalidGeneration
        }
        guard currentGeneration == generation else {
            throw MacRemoteAccessBootstrapAuthorityErrorV1.staleGeneration
        }
        guard let currentOffer else {
            throw MacRemoteAccessBootstrapAuthorityErrorV1.offerUnavailable
        }
        guard currentOffer == command.offer,
              completedEnable == nil else {
            terminalizeCurrentGeneration()
            throw MacRemoteAccessBootstrapAuthorityErrorV1.commandMismatch
        }
        return try beginOperation(generation: generation)
    }

    private func beginOperation(
        generation: UInt64
    ) throws -> ActiveOperation {
        guard activeOperation == nil else {
            throw MacRemoteAccessBootstrapAuthorityErrorV1.operationInProgress
        }
        guard nextOperation < UInt64.max else {
            terminalizeCurrentGeneration()
            throw MacRemoteAccessBootstrapAuthorityErrorV1
                .generationExhausted
        }
        nextOperation += 1
        let operation = ActiveOperation(
            generation: generation,
            identifier: nextOperation
        )
        activeOperation = operation
        return operation
    }

    private func requireCurrent(
        _ operation: ActiveOperation
    ) throws {
        guard currentGeneration == operation.generation,
              activeOperation == operation else {
            throw MacRemoteAccessBootstrapAuthorityErrorV1.staleGeneration
        }
    }

    private func finish(_ operation: ActiveOperation) {
        guard activeOperation == operation else { return }
        activeOperation = nil
    }

    private func terminalizeIfCurrent(_ operation: ActiveOperation) {
        guard currentGeneration == operation.generation,
              activeOperation == operation else {
            return
        }
        terminalizeCurrentGeneration()
    }

    private func terminalizeCurrentGeneration() {
        currentGeneration = nil
        activeOperation = nil
        currentOffer = nil
        completedEnable = nil
    }

    private func exactDurableReplay(
        _ snapshot: MacRemoteAccessIntentSnapshotV1?,
        command: LocalRemoteAccessEnableCommandV0,
        nowUnixMilliseconds: Int64
    ) throws -> LocalRemoteAccessEnabledReceiptV0? {
        guard let snapshot, snapshot.desiredEnabled else { return nil }
        let successor = UInt64(command.offer.expectedIntentRevision) + 1
        guard snapshot.revision == successor,
              snapshot.commandID == command.commandID,
              snapshot.recordedAtUnixMilliseconds >=
                command.confirmedAtUnixMilliseconds,
              snapshot.recordedAtUnixMilliseconds <=
                nowUnixMilliseconds else {
            throw MacRemoteAccessBootstrapAuthorityErrorV1.alreadyEnabled
        }
        do {
            let receipt = try LocalRemoteAccessEnabledReceiptV0(
                correlationID: command.commandID,
                offerID: command.offer.offerID,
                intentRevision: Int64(snapshot.revision),
                completedAtUnixMilliseconds:
                    snapshot.recordedAtUnixMilliseconds
            )
            try receipt.validate(against: command)
            return receipt
        } catch {
            throw MacRemoteAccessBootstrapAuthorityErrorV1
                .unsafeDurableState
        }
    }

    private func map(_ error: any Error)
        -> MacRemoteAccessBootstrapAuthorityErrorV1
    {
        if let error = error as?
            MacRemoteAccessBootstrapAuthorityErrorV1 {
            return error
        }
        return .storageAmbiguous
    }
}
