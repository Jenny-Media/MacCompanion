import CompanionDiscovery
import CompanionIPC
import CompanionPairing
import CompanionWire
import Foundation

public enum AgentLocalPairingSessionErrorV0: Error, Equatable, Sendable {
    case invalidContext
    case invalidClock
    case busy
    case presentationAlreadyActive
    case staleCommand
    case notActive
    case bindingMismatch
    case qrConstructionFailed
    case authorityUnavailable
}

/// The exact listener-owned facts advertised in a pairing QR code. A menu app
/// never supplies either the host identity or routes across local IPC.
public struct AgentLocalPairingContextV0: Equatable, Sendable {
    public let hostFingerprint: Data
    public let endpoints: [EndpointCandidate]

    public init(
        hostFingerprint: Data,
        endpoints: [EndpointCandidate]
    ) throws {
        guard hostFingerprint.count == 32,
              (1...8).contains(endpoints.count),
              Set(endpoints).count == endpoints.count else {
            throw AgentLocalPairingSessionErrorV0.invalidContext
        }
        self.hostFingerprint = hostFingerprint
        self.endpoints = endpoints.sorted {
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            if $0.value != $1.value { return $0.value < $1.value }
            return $0.port < $1.port
        }
    }
}

public protocol AgentLocalPairingContextReadingV0: Sendable {
    func currentPairingContext() async throws -> AgentLocalPairingContextV0
}

public struct StaticAgentLocalPairingContextSourceV0:
    AgentLocalPairingContextReadingV0,
    Sendable
{
    private let context: AgentLocalPairingContextV0

    public init(_ context: AgentLocalPairingContextV0) {
        self.context = context
    }

    public func currentPairingContext() async throws
        -> AgentLocalPairingContextV0
    {
        context
    }
}

public struct AgentLocalPairingTimeSampleV0: Equatable, Sendable {
    public let wallNowUnixMilliseconds: Int64
    public let monotonicNowMilliseconds: Int64

    public init(
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: Int64
    ) throws {
        guard wallNowUnixMilliseconds >= 0,
              wallNowUnixMilliseconds <= WireLimits.maximumSafeInteger
                - PairingSessionAuthority.lifetimeMilliseconds,
              monotonicNowMilliseconds >= 0,
              monotonicNowMilliseconds <= Int64.max
                - PairingSessionAuthority.lifetimeMilliseconds else {
            throw AgentLocalPairingSessionErrorV0.invalidClock
        }
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
    }
}

public protocol AgentLocalPairingTimeSamplingV0: Sendable {
    func currentPairingTime() throws -> AgentLocalPairingTimeSampleV0
}

public struct StaticAgentLocalPairingTimeSourceV0:
    AgentLocalPairingTimeSamplingV0,
    Sendable
{
    private let sample: AgentLocalPairingTimeSampleV0

    public init(_ sample: AgentLocalPairingTimeSampleV0) {
        self.sample = sample
    }

    public func currentPairingTime() throws -> AgentLocalPairingTimeSampleV0 {
        sample
    }
}

/// Narrow adapter protocol keeps the local IPC handler testable without
/// weakening PairingSessionAuthority's ownership of secrets and tombstones.
public protocol AgentLocalPairingSessionManagingV0: Sendable {
    func createLocalPairingSession(
        pairingID: UUID,
        hostFingerprint: Data,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: Int64
    ) async throws -> PairingAdvertisement

    func cancelLocalPairingSession(
        pairingID: UUID,
        monotonicNowMilliseconds: Int64
    ) async throws
}

extension PairingSessionAuthority: AgentLocalPairingSessionManagingV0 {
    public func createLocalPairingSession(
        pairingID: UUID,
        hostFingerprint: Data,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: Int64
    ) throws -> PairingAdvertisement {
        try createSession(
            pairingID: pairingID,
            hostFingerprint: hostFingerprint,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }

    public func cancelLocalPairingSession(
        pairingID: UUID,
        monotonicNowMilliseconds: Int64
    ) throws {
        try cancel(
            pairingID: pairingID,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }
}

/// Agent-owned composition for the two secret-bearing local pairing methods.
/// It permits one visible QR at a time, makes create/dismiss retries exact,
/// and reports successful dismissal only after the session is tombstoned or
/// the pairing authority proves that it is already terminal.
public actor AgentLocalPairingSessionHandlerV0 {
    public static let maximumCommandHistory = 32

    private struct ActivePresentation: Sendable {
        let createCommand: LocalPairingSessionCreateCommandV0
        let receipt: LocalPairingSessionCreatedReceiptV0
        let monotonicDeadlineMilliseconds: Int64
    }

    private struct DismissCompletion: Sendable {
        let command: LocalPairingSessionDismissCommandV0
        let receipt: LocalPairingSessionDismissedReceiptV0
    }

    private let authority: any AgentLocalPairingSessionManagingV0
    private let contextSource: any AgentLocalPairingContextReadingV0
    private let timeSource: any AgentLocalPairingTimeSamplingV0
    private let pairingIDGenerator: @Sendable () -> UUID
    private var active: ActivePresentation?
    private var mutationInProgress = false
    private var sourceTerminal = false
    private var createHistory: [UUID: LocalPairingSessionCreatedReceiptV0] = [:]
    private var createOrder: [UUID] = []
    private var dismissHistory: [UUID: DismissCompletion] = [:]
    private var dismissOrder: [UUID] = []

    public init(
        authority: any AgentLocalPairingSessionManagingV0,
        contextSource: any AgentLocalPairingContextReadingV0,
        timeSource: any AgentLocalPairingTimeSamplingV0,
        pairingIDGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.authority = authority
        self.contextSource = contextSource
        self.timeSource = timeSource
        self.pairingIDGenerator = pairingIDGenerator
    }

    public func create(
        _ command: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0 {
        guard !sourceTerminal else {
            throw AgentLocalPairingSessionErrorV0.invalidContext
        }
        if let prior = createHistory[command.commandID] {
            guard active?.createCommand == command,
                  active?.receipt == prior else {
                throw AgentLocalPairingSessionErrorV0.staleCommand
            }
            return prior
        }
        guard !mutationInProgress else {
            throw AgentLocalPairingSessionErrorV0.busy
        }
        mutationInProgress = true
        defer { mutationInProgress = false }

        let time = try readTime()
        try await clearExpiredPresentation(at: time)
        guard active == nil else {
            throw AgentLocalPairingSessionErrorV0.presentationAlreadyActive
        }
        let context = try await readContext()
        let pairingID = pairingIDGenerator()
        let advertisement: PairingAdvertisement
        do {
            advertisement = try await authority.createLocalPairingSession(
                pairingID: pairingID,
                hostFingerprint: context.hostFingerprint,
                wallNowUnixMilliseconds: time.wallNowUnixMilliseconds,
                monotonicNowMilliseconds: time.monotonicNowMilliseconds
            )
        } catch {
            throw AgentLocalPairingSessionErrorV0.authorityUnavailable
        }

        guard !sourceTerminal else {
            try await compensateCreatedSession(
                pairingID: pairingID,
                monotonicNowMilliseconds: time.monotonicNowMilliseconds
            )
            throw AgentLocalPairingSessionErrorV0.invalidContext
        }

        guard advertisement.pairingID == pairingID,
              advertisement.hostFingerprint == context.hostFingerprint,
              advertisement.oneTimeSecret.count == 32,
              advertisement.expiresAtUnixMilliseconds
                == time.wallNowUnixMilliseconds
                    + PairingSessionAuthority.lifetimeMilliseconds else {
            try await compensateCreatedSession(
                pairingID: pairingID,
                monotonicNowMilliseconds: time.monotonicNowMilliseconds
            )
            throw AgentLocalPairingSessionErrorV0.authorityUnavailable
        }

        let receipt: LocalPairingSessionCreatedReceiptV0
        do {
            let payload = try PairingQRCodePayload(
                pairingID: WireUUID(advertisement.pairingID),
                oneTimeSecret: WireBytes32(advertisement.oneTimeSecret),
                expiresAtUnixMilliseconds:
                    advertisement.expiresAtUnixMilliseconds,
                hostFingerprint: WireFingerprint(
                    advertisement.hostFingerprint
                ),
                endpoints: context.endpoints
            )
            receipt = try LocalPairingSessionCreatedReceiptV0(
                correlationID: command.commandID,
                pairingID: advertisement.pairingID,
                encodedQRCode: PairingQRCodeCodec.encode(payload),
                createdAtUnixMilliseconds: time.wallNowUnixMilliseconds,
                expiresAtUnixMilliseconds:
                    advertisement.expiresAtUnixMilliseconds
            )
        } catch {
            try await compensateCreatedSession(
                pairingID: pairingID,
                monotonicNowMilliseconds: time.monotonicNowMilliseconds
            )
            throw AgentLocalPairingSessionErrorV0.qrConstructionFailed
        }

        active = ActivePresentation(
            createCommand: command,
            receipt: receipt,
            monotonicDeadlineMilliseconds:
                time.monotonicNowMilliseconds
                    + PairingSessionAuthority.lifetimeMilliseconds
        )
        retainCreate(receipt, commandID: command.commandID)
        return receipt
    }

    /// Invalidates a visible or in-flight QR after listener/advertisement
    /// authority is lost. Terminal invalidation permanently disables this
    /// handler instance; a replacement listener must receive a new handler.
    public func invalidateForNetworkLoss(
        monotonicNowMilliseconds: UInt64,
        terminal: Bool
    ) async throws {
        if terminal { sourceTerminal = true }
        guard monotonicNowMilliseconds <= UInt64(Int64.max) else {
            throw AgentLocalPairingSessionErrorV0.invalidClock
        }
        guard let current = active else { return }
        do {
            try await authority.cancelLocalPairingSession(
                pairingID: current.receipt.pairingID,
                monotonicNowMilliseconds: Int64(monotonicNowMilliseconds)
            )
            active = nil
        } catch let error as PairingSessionError {
            switch error {
            case .expired, .alreadyConsumed, .notFound, .invalidState:
                active = nil
            default:
                throw AgentLocalPairingSessionErrorV0.authorityUnavailable
            }
        } catch {
            throw AgentLocalPairingSessionErrorV0.authorityUnavailable
        }
    }

    public func dismiss(
        _ command: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0 {
        if let prior = dismissHistory[command.commandID] {
            guard prior.command == command else {
                throw AgentLocalPairingSessionErrorV0.bindingMismatch
            }
            return prior.receipt
        }
        guard !mutationInProgress else {
            throw AgentLocalPairingSessionErrorV0.busy
        }
        mutationInProgress = true
        defer { mutationInProgress = false }

        let time = try readTime()
        guard let current = active else {
            throw AgentLocalPairingSessionErrorV0.notActive
        }
        guard current.receipt.pairingID == command.pairingID else {
            throw AgentLocalPairingSessionErrorV0.bindingMismatch
        }
        do {
            try await authority.cancelLocalPairingSession(
                pairingID: command.pairingID,
                monotonicNowMilliseconds: time.monotonicNowMilliseconds
            )
        } catch let error as PairingSessionError {
            switch error {
            case .expired, .alreadyConsumed, .notFound:
                let receipt = try makeDismissedReceipt(
                    command: command,
                    time: time
                )
                active = nil
                retainDismiss(command: command, receipt: receipt)
                return receipt
            default:
                throw AgentLocalPairingSessionErrorV0.authorityUnavailable
            }
        } catch {
            throw AgentLocalPairingSessionErrorV0.authorityUnavailable
        }

        let receipt = try makeDismissedReceipt(
            command: command,
            time: time
        )
        active = nil
        retainDismiss(command: command, receipt: receipt)
        return receipt
    }

    private func makeDismissedReceipt(
        command: LocalPairingSessionDismissCommandV0,
        time: AgentLocalPairingTimeSampleV0
    ) throws -> LocalPairingSessionDismissedReceiptV0 {
        try LocalPairingSessionDismissedReceiptV0(
            correlationID: command.commandID,
            pairingID: command.pairingID,
            completedAtUnixMilliseconds: time.wallNowUnixMilliseconds
        )
    }

    private func readTime() throws -> AgentLocalPairingTimeSampleV0 {
        do { return try timeSource.currentPairingTime() }
        catch { throw AgentLocalPairingSessionErrorV0.invalidClock }
    }

    private func readContext() async throws -> AgentLocalPairingContextV0 {
        do { return try await contextSource.currentPairingContext() }
        catch { throw AgentLocalPairingSessionErrorV0.invalidContext }
    }

    private func clearExpiredPresentation(
        at time: AgentLocalPairingTimeSampleV0
    ) async throws {
        guard let current = active,
              time.monotonicNowMilliseconds
                >= current.monotonicDeadlineMilliseconds else { return }
        do {
            try await authority.cancelLocalPairingSession(
                pairingID: current.receipt.pairingID,
                monotonicNowMilliseconds: time.monotonicNowMilliseconds
            )
            active = nil
        } catch let error as PairingSessionError {
            switch error {
            case .expired, .alreadyConsumed, .notFound:
                active = nil
            default:
                throw AgentLocalPairingSessionErrorV0.authorityUnavailable
            }
        } catch {
            throw AgentLocalPairingSessionErrorV0.authorityUnavailable
        }
    }

    private func compensateCreatedSession(
        pairingID: UUID,
        monotonicNowMilliseconds: Int64
    ) async throws {
        do {
            try await authority.cancelLocalPairingSession(
                pairingID: pairingID,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
        } catch {
            throw AgentLocalPairingSessionErrorV0.authorityUnavailable
        }
    }

    private func retainCreate(
        _ receipt: LocalPairingSessionCreatedReceiptV0,
        commandID: UUID
    ) {
        createHistory[commandID] = receipt
        createOrder.append(commandID)
        if createOrder.count > Self.maximumCommandHistory {
            let evicted = createOrder.removeFirst()
            createHistory.removeValue(forKey: evicted)
        }
    }

    private func retainDismiss(
        command: LocalPairingSessionDismissCommandV0,
        receipt: LocalPairingSessionDismissedReceiptV0
    ) {
        dismissHistory[command.commandID] = DismissCompletion(
            command: command,
            receipt: receipt
        )
        dismissOrder.append(command.commandID)
        if dismissOrder.count > Self.maximumCommandHistory {
            let evicted = dismissOrder.removeFirst()
            dismissHistory.removeValue(forKey: evicted)
        }
    }
}
