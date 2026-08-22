#if os(macOS)
import CompanionAgent
import CompanionIPC
import CompanionLocalXPCPlatform
import Foundation

@available(macOS 26.0, *)
public protocol MacRemoteAccessBootstrapClientV1: AnyObject, Sendable {
    func start() throws
    func readOffer()
    func enable(_ command: LocalRemoteAccessEnableCommandV0)
    func cancel()
}

@available(macOS 26.0, *)
extension MacLocalXPCRemoteAccessBootstrapClientV1:
    MacRemoteAccessBootstrapClientV1
{}

@available(macOS 26.0, *)
public enum MacRemoteAccessSetupFailureV1: Equatable, Sendable {
    case agentRegistration(AgentLoginRoleFailureReasonV1)
    case transportUnavailable
    case invalidOffer
    case consentExpired
    case agentCleanup(AgentLoginRoleFailureReasonV1)
    case menuRegistrationPending(AgentLoginRoleFailureReasonV1)
}

@available(macOS 26.0, *)
public enum MacRemoteAccessSetupStateV1: Equatable, Sendable {
    case idle
    case registeringAgent
    case connecting
    case readingOffer(generation: UInt64)
    case awaitingConsent(
        generation: UInt64,
        offer: LocalRemoteAccessBootstrapOfferV0
    )
    case enabling(
        generation: UInt64,
        command: LocalRemoteAccessEnableCommandV0
    )
    case convergingMenu(LocalRemoteAccessEnabledReceiptV0)
    case enabled(LocalRemoteAccessEnabledReceiptV0)
    case declined
    case failed(MacRemoteAccessSetupFailureV1)
    case outcomeUnknown
}

@available(macOS 26.0, *)
public enum MacRemoteAccessSetupCoordinatorErrorV1:
    Error,
    Equatable,
    Sendable
{
    case transitionInProgress
    case consentUnavailable
    case menuConvergenceUnavailable
    case invalidClock
}

/// Owns the first foreground disabled-to-enabled product transition.
///
/// The normal two-role lifecycle executor is deliberately not accepted here:
/// setup must register only the Agent before consent. The menu login role can
/// converge only after an exact durable receipt. Once an enable command may
/// have crossed the process boundary, this owner never unregisters the Agent;
/// transport loss is reported as outcome-unknown for later durable-state
/// reconciliation.
@available(macOS 26.0, *)
public actor MacRemoteAccessSetupCoordinatorV1 {
    public typealias StateChanged =
        @Sendable (MacRemoteAccessSetupStateV1) -> Void
    public typealias Milliseconds = @Sendable () -> Int64?
    public typealias CommandID = @Sendable () -> UUID

    private let agent: any AgentBootstrapLoginRoleServiceV1
    private let menuApp: any AgentLoginRoleServiceV1
    private let client: any MacRemoteAccessBootstrapClientV1
    private let milliseconds: Milliseconds
    private let commandID: CommandID
    private let stateChanged: StateChanged

    private var state: MacRemoteAccessSetupStateV1 = .idle
    private var activeGeneration: UInt64?
    private var receiptAwaitingMenuConvergence:
        LocalRemoteAccessEnabledReceiptV0?
    private var agentRegistrationOwnedBySetup = false

    public init(
        agent: any AgentBootstrapLoginRoleServiceV1,
        menuApp: any AgentLoginRoleServiceV1,
        client: any MacRemoteAccessBootstrapClientV1,
        milliseconds: @escaping Milliseconds = {
            let value = Date().timeIntervalSince1970 * 1_000
            guard value.isFinite,
                  value >= 0,
                  value <= Double(9_007_199_254_740_991) else { return nil }
            return Int64(value.rounded(.down))
        },
        commandID: @escaping CommandID = UUID.init,
        stateChanged: @escaping StateChanged = { _ in }
    ) {
        self.agent = agent
        self.menuApp = menuApp
        self.client = client
        self.milliseconds = milliseconds
        self.commandID = commandID
        self.stateChanged = stateChanged
    }

    public func snapshot() -> MacRemoteAccessSetupStateV1 { state }

    public func begin() async throws {
        guard permitsBegin else {
            throw MacRemoteAccessSetupCoordinatorErrorV1
                .transitionInProgress
        }
        activeGeneration = nil
        receiptAwaitingMenuConvergence = nil
        agentRegistrationOwnedBySetup = false
        setState(.registeringAgent)
        do {
            let acquisition = try await agent.acquireForBootstrap()
            agentRegistrationOwnedBySetup =
                acquisition == .newlyRegistered
        } catch {
            setState(.failed(.agentRegistration(failureReason(error))))
            return
        }
        guard state == .registeringAgent else {
            // A concurrent finish may have compensated before the asynchronous
            // register call completed. Repeat the idempotent compensation so a
            // late platform effect cannot strand a setup-only Agent.
            await cleanupAgent(after: .transportUnavailable)
            return
        }
        setState(.connecting)
        do {
            try client.start()
        } catch {
            await cleanupAgent(after: .transportUnavailable)
        }
    }

    public func receive(
        _ event: MacLocalXPCRemoteAccessBootstrapClientEventV1
    ) async {
        switch event {
        case let .authenticatedAgent(generation):
            guard state == .connecting else {
                await handleUnexpectedEvent()
                return
            }
            activeGeneration = generation
            setState(.readingOffer(generation: generation))
            client.readOffer()

        case let .offer(generation, offer):
            guard activeGeneration == generation,
                  state == .readingOffer(generation: generation) else {
                await handleUnexpectedEvent()
                return
            }
            setState(.awaitingConsent(
                generation: generation,
                offer: offer
            ))

        case let .enabled(generation, receipt):
            guard activeGeneration == generation,
                  case let .enabling(expectedGeneration, command) = state,
                  expectedGeneration == generation else {
                await handleUnexpectedEvent()
                return
            }
            do {
                try receipt.validate(against: command)
            } catch {
                client.cancel()
                activeGeneration = nil
                setState(.outcomeUnknown)
                return
            }
            activeGeneration = nil
            receiptAwaitingMenuConvergence = receipt
            agentRegistrationOwnedBySetup = false
            await convergeMenu(after: receipt)

        case let .invalidated(generation):
            let isPreAuthenticationInvalidation = state == .connecting
                && activeGeneration == nil
            guard activeGeneration == generation
                    || isPreAuthenticationInvalidation else { return }
            activeGeneration = nil
            switch state {
            case .enabling:
                setState(.outcomeUnknown)
            case .connecting, .readingOffer, .awaitingConsent:
                await cleanupAgent(after: .transportUnavailable)
            case .idle, .registeringAgent, .convergingMenu, .enabled,
                    .declined, .failed, .outcomeUnknown:
                break
            }
        }
    }

    public func confirm() async throws {
        guard case let .awaitingConsent(generation, offer) = state,
              activeGeneration == generation else {
            throw MacRemoteAccessSetupCoordinatorErrorV1
                .consentUnavailable
        }
        guard let now = milliseconds() else {
            throw MacRemoteAccessSetupCoordinatorErrorV1.invalidClock
        }
        let command: LocalRemoteAccessEnableCommandV0
        do {
            command = try LocalRemoteAccessEnableCommandV0(
                commandID: commandID(),
                offer: offer,
                confirmedAtUnixMilliseconds: now
            )
        } catch {
            client.cancel()
            activeGeneration = nil
            await cleanupAgent(after: .consentExpired)
            return
        }
        setState(.enabling(
            generation: generation,
            command: command
        ))
        client.enable(command)
    }

    public func decline() async throws {
        guard case .awaitingConsent = state else {
            throw MacRemoteAccessSetupCoordinatorErrorV1
                .consentUnavailable
        }
        client.cancel()
        activeGeneration = nil
        await cleanupAgent(
            after: nil,
            success: .declined,
            registrationIsProvenSafeToRemove: true
        )
    }

    public func retryMenuConvergence() async throws {
        guard case .failed(.menuRegistrationPending) = state,
              let receipt = receiptAwaitingMenuConvergence else {
            throw MacRemoteAccessSetupCoordinatorErrorV1
                .menuConvergenceUnavailable
        }
        await convergeMenu(after: receipt)
    }

    /// Terminal process cleanup. Before the enable-send boundary it removes
    /// the setup-only Agent registration. At or after that boundary it keeps
    /// the Agent registered and reports outcome-unknown.
    public func finish() async {
        client.cancel()
        activeGeneration = nil
        switch state {
        case .registeringAgent, .connecting, .readingOffer, .awaitingConsent:
            await cleanupAgent(after: .transportUnavailable)
        case .enabling:
            setState(.outcomeUnknown)
        case .idle, .convergingMenu, .enabled, .declined, .failed,
                .outcomeUnknown:
            break
        }
    }

    private var permitsBegin: Bool {
        switch state {
        case .idle, .declined,
                .failed(.agentRegistration),
                .failed(.transportUnavailable),
                .failed(.invalidOffer),
                .failed(.consentExpired), .outcomeUnknown:
            true
        case .registeringAgent, .connecting, .readingOffer,
                .awaitingConsent, .enabling, .convergingMenu, .enabled,
                .failed(.agentCleanup),
                .failed(.menuRegistrationPending):
            false
        }
    }

    private func convergeMenu(
        after receipt: LocalRemoteAccessEnabledReceiptV0
    ) async {
        setState(.convergingMenu(receipt))
        do {
            try await menuApp.register()
        } catch {
            setState(.failed(
                .menuRegistrationPending(failureReason(error))
            ))
            return
        }
        setState(.enabled(receipt))
    }

    private func handleUnexpectedEvent() async {
        switch state {
        case .enabling, .convergingMenu, .enabled, .outcomeUnknown:
            client.cancel()
            activeGeneration = nil
            setState(.outcomeUnknown)
        case .idle, .registeringAgent, .connecting, .readingOffer,
                .awaitingConsent, .declined, .failed:
            await failClosedBeforeEnable(.invalidOffer)
        }
    }

    private func failClosedBeforeEnable(
        _ failure: MacRemoteAccessSetupFailureV1
    ) async {
        client.cancel()
        activeGeneration = nil
        await cleanupAgent(after: failure)
    }

    private func cleanupAgent(
        after failure: MacRemoteAccessSetupFailureV1?,
        success: MacRemoteAccessSetupStateV1? = nil,
        registrationIsProvenSafeToRemove: Bool = false
    ) async {
        guard agentRegistrationOwnedBySetup
                || registrationIsProvenSafeToRemove else {
            setState(.outcomeUnknown)
            return
        }
        do {
            try await agent.unregister()
        } catch {
            setState(.failed(.agentCleanup(failureReason(error))))
            return
        }
        agentRegistrationOwnedBySetup = false
        if let success {
            setState(success)
        } else {
            setState(.failed(failure ?? .transportUnavailable))
        }
    }

    private func failureReason(
        _ error: any Error
    ) -> AgentLoginRoleFailureReasonV1 {
        guard let value = error as? AgentLoginRoleConvergenceErrorV1 else {
            return .platformFailure
        }
        return switch value {
        case .requiresApproval: .requiresApproval
        case .serviceNotFound: .serviceNotFound
        case .platformFailure: .platformFailure
        case .postconditionFailed: .postconditionFailed
        }
    }

    private func setState(_ value: MacRemoteAccessSetupStateV1) {
        state = value
        stateChanged(value)
    }
}
#endif
