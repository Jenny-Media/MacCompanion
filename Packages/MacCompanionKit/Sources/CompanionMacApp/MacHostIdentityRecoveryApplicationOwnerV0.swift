import CompanionIPC
import CompanionPresentation
import Foundation

public protocol MacHostIdentityRecoveryLocalIPCClientV0: Sendable {
    func recoverHostIdentity(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws -> LocalHostIdentityRecoveredReceiptV0
}

public protocol MacHostIdentityRecoveryWallClockV0: Sendable {
    func nowUnixMilliseconds() -> Int64
}

public struct SystemMacHostIdentityRecoveryWallClockV0:
    MacHostIdentityRecoveryWallClockV0
{
    public init() {}

    public func nowUnixMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
    }
}

public enum MacHostIdentityRecoveryApplicationOwnerErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidPhase
    case identifierReuse
    case revisionExhausted
}

/// Bundle-independent owner for an already-authenticated recovery review. It
/// retains the exact command across response loss and fences delayed results
/// after Agent invalidation. It owns no recovery or identity authority.
public actor MacHostIdentityRecoveryApplicationOwnerV0:
    LocalHostIdentityRecoverySurfaceV0
{
    public typealias IdentifierSource = @Sendable () -> UUID
    public typealias StateChanged =
        @Sendable (MacHostIdentityRecoveryPresentationV0) async -> Void

    private let client: any MacHostIdentityRecoveryLocalIPCClientV0
    private let clock: any MacHostIdentityRecoveryWallClockV0
    private let identifierSource: IdentifierSource
    private let stateChanged: StateChanged

    private var presentation = MacHostIdentityRecoveryPresentationV0()
    private var revision: UInt64 = 0
    private var inFlightRevision: UInt64?
    private var issuedIdentifiers: Set<UUID> = []

    public init(
        client: any MacHostIdentityRecoveryLocalIPCClientV0,
        clock: any MacHostIdentityRecoveryWallClockV0 =
            SystemMacHostIdentityRecoveryWallClockV0(),
        identifierSource: @escaping IdentifierSource = { UUID() },
        stateChanged: @escaping StateChanged = { _ in }
    ) {
        self.client = client
        self.clock = clock
        self.identifierSource = identifierSource
        self.stateChanged = stateChanged
    }

    public func snapshot() -> MacHostIdentityRecoveryPresentationV0 {
        presentation
    }

    public func publishReview(
        _ review: LocalHostIdentityRecoveryReviewV0
    ) async throws {
        do {
            try presentation.present(review)
        } catch {
            throw MacHostIdentityRecoveryApplicationOwnerErrorV0.invalidPhase
        }
        await publish()
    }

    /// Called only by the already-authenticated Agent-to-menu resume method.
    /// The owner adopts the exact persisted command and offers retry without
    /// issuing identifiers or asking the user to confirm a second time.
    public func publishRecoveryResume(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws {
        do {
            try presentation.resume(command)
        } catch {
            throw MacHostIdentityRecoveryApplicationOwnerErrorV0.invalidPhase
        }
        issuedIdentifiers.insert(command.commandID)
        issuedIdentifiers.insert(command.recoveryID)
        await publish()
    }

    public func presentHostIdentityRecoveryReview(
        _ review: LocalHostIdentityRecoveryReviewV0
    ) async throws {
        try await publishReview(review)
    }

    public func presentHostIdentityRecoveryResume(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws {
        try await publishRecoveryResume(command)
    }

    public func withdrawHostIdentityRecovery(reviewID: UUID) async {
        guard presentation.currentReviewID == reviewID else { return }
        invalidateCurrentRevision()
        presentation.agentInvalidated()
        await publish()
    }

    public func confirm() async throws {
        guard inFlightRevision == nil else {
            throw MacHostIdentityRecoveryApplicationOwnerErrorV0.invalidPhase
        }
        let commandID = try issueIdentifier()
        let recoveryID = try issueIdentifier()
        let command: LocalHostIdentityRecoveryCommandV0
        do {
            command = try presentation.confirm(
                commandID: commandID,
                recoveryID: recoveryID,
                confirmedAtUnixMilliseconds: clock.nowUnixMilliseconds()
            )
        } catch {
            throw MacHostIdentityRecoveryApplicationOwnerErrorV0.invalidPhase
        }
        let operationRevision = try startOperation()
        await publish()
        guard operationRevision == revision else { return }
        await perform(command, operationRevision: operationRevision)
    }

    public func retry() async throws {
        guard inFlightRevision == nil else {
            throw MacHostIdentityRecoveryApplicationOwnerErrorV0.invalidPhase
        }
        let command: LocalHostIdentityRecoveryCommandV0
        do {
            command = try presentation.retry()
        } catch {
            throw MacHostIdentityRecoveryApplicationOwnerErrorV0.invalidPhase
        }
        let operationRevision = try startOperation()
        await publish()
        guard operationRevision == revision else { return }
        await perform(command, operationRevision: operationRevision)
    }

    public func agentInvalidated() async {
        invalidateCurrentRevision()
        presentation.agentInvalidated()
        await publish()
    }

    private func perform(
        _ command: LocalHostIdentityRecoveryCommandV0,
        operationRevision: UInt64
    ) async {
        do {
            let receipt = try await client.recoverHostIdentity(command)
            guard operationRevision == revision,
                  inFlightRevision == operationRevision else { return }
            inFlightRevision = nil
            do {
                try presentation.receive(receipt)
            } catch {
                try? presentation.submissionFailed()
            }
            await publish()
        } catch {
            guard operationRevision == revision,
                  inFlightRevision == operationRevision else { return }
            inFlightRevision = nil
            try? presentation.submissionFailed()
            await publish()
        }
    }

    private func issueIdentifier() throws -> UUID {
        let identifier = identifierSource()
        guard issuedIdentifiers.insert(identifier).inserted else {
            throw MacHostIdentityRecoveryApplicationOwnerErrorV0.identifierReuse
        }
        return identifier
    }

    private func startOperation() throws -> UInt64 {
        guard revision < UInt64.max else {
            throw MacHostIdentityRecoveryApplicationOwnerErrorV0
                .revisionExhausted
        }
        revision += 1
        inFlightRevision = revision
        return revision
    }

    private func invalidateCurrentRevision() {
        if revision < UInt64.max { revision += 1 }
        inFlightRevision = nil
    }

    private func publish() async {
        await stateChanged(presentation)
    }
}
