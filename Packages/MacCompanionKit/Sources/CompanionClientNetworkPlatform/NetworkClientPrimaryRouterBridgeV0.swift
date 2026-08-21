import CompanionClient
import CompanionInteractiveClient
import Foundation

public enum NetworkClientPrimaryRouterBridgeErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidState
    case unavailable
}

/// Construction bridge for the circular runtime edge between the primary
/// pump's authenticated sender and the connection-bound product router. Bind
/// the pump before beginning authentication, then pass `authenticated` and
/// `receive` into that same pump's callbacks.
public actor NetworkClientPrimaryRouterBridgeV0:
    ClientAuthenticatedCommandSendingV1
{
    private let pairedHost: ClientDurablePairedHostV0
    private let approvalSigner: any ClientOperationApprovalSigningV1
    private let interactiveApprovalSigner:
        (any ClientInteractiveApprovalSigningV0)?
    private let interactiveEnvironment:
        ClientInteractivePrimaryEnvironmentV0?
    private let monotonicNowNanoseconds: @Sendable () -> UInt64
    private let observeEnvironment: ClientObserveChannelEnvironmentV0
    private let actEnvironment: ClientActChannelEnvironmentV1
    private let publishObserve: @Sendable (
        ClientObserveChannelEventV0
    ) -> Void
    private let publishAct: @Sendable (ClientActChannelEventV1) -> Void
    private let publishControl: @Sendable (
        ClientInteractivePrimarySessionEventV0
    ) -> Void

    private var pump: NetworkClientPrimaryFramePumpV0?
    private var router: ClientPrimaryCommandRouterV0?
    private var observeChannel: ClientObserveChannelV0?
    private var actChannel: ClientActChannelV1?
    private var controlChannel: ClientInteractivePrimaryChannelV0?
    private var invalidated = false

    public init(
        pairedHost: ClientDurablePairedHostV0,
        approvalSigner: any ClientOperationApprovalSigningV1,
        interactiveApprovalSigner:
            (any ClientInteractiveApprovalSigningV0)? = nil,
        interactiveEnvironment:
            ClientInteractivePrimaryEnvironmentV0? = nil,
        monotonicNowNanoseconds: @escaping @Sendable () -> UInt64,
        observeEnvironment: ClientObserveChannelEnvironmentV0 = .live,
        actEnvironment: ClientActChannelEnvironmentV1 = .live,
        publishObserve: @escaping @Sendable (
            ClientObserveChannelEventV0
        ) -> Void = { _ in },
        publishAct: @escaping @Sendable (
            ClientActChannelEventV1
        ) -> Void = { _ in },
        publishControl: @escaping @Sendable (
            ClientInteractivePrimarySessionEventV0
        ) -> Void = { _ in }
    ) {
        self.pairedHost = pairedHost
        self.approvalSigner = approvalSigner
        self.interactiveApprovalSigner = interactiveApprovalSigner
        self.interactiveEnvironment = interactiveEnvironment
        self.monotonicNowNanoseconds = monotonicNowNanoseconds
        self.observeEnvironment = observeEnvironment
        self.actEnvironment = actEnvironment
        self.publishObserve = publishObserve
        self.publishAct = publishAct
        self.publishControl = publishControl
    }

    public func bind(
        pump: NetworkClientPrimaryFramePumpV0
    ) throws {
        guard !invalidated, self.pump == nil, router == nil else {
            throw NetworkClientPrimaryRouterBridgeErrorV0.invalidState
        }
        self.pump = pump
    }

    public func authenticated(
        _ session: ClientAuthenticatedSessionV0
    ) async throws {
        guard !invalidated, pump != nil, router == nil,
              session.clientID == pairedHost.clientID,
              session.hostID == pairedHost.hostID,
              session.deviceID == pairedHost.deviceID else {
            throw NetworkClientPrimaryRouterBridgeErrorV0.invalidState
        }
        let router = try ClientPrimaryCommandRouterV0(
            authenticatedSession: session,
            transport: self,
            monotonicNowNanoseconds: monotonicNowNanoseconds
        )
        let observeChannel = try ClientObserveChannelV0(
            authenticatedSession: session,
            sender: router.sender(for: .observe),
            environment: observeEnvironment,
            publish: publishObserve
        )
        let channel = try ClientActChannelV1(
            pairedHost: pairedHost,
            authenticatedSession: session,
            signer: approvalSigner,
            sender: router.sender(for: .act),
            environment: actEnvironment
        )
        let actReceiver = ClientActPrimaryReplyReceiverV1(
            channel: channel,
            publish: publishAct
        )
        try await router.installReceiver(observeChannel, for: .observe)
        try await router.installReceiver(actReceiver, for: .act)
        let controlChannel: ClientInteractivePrimaryChannelV0?
        if let signer = interactiveApprovalSigner,
           let environment = interactiveEnvironment {
            let channel = try ClientInteractivePrimaryChannelV0(
                pairedHost: pairedHost,
                authenticatedSession: session,
                signer: signer,
                sender: router.sender(for: .control),
                environment: environment,
                publish: publishControl
            )
            try await router.installReceiver(channel, for: .control)
            controlChannel = channel
        } else {
            guard interactiveApprovalSigner == nil,
                  interactiveEnvironment == nil else {
                await router.invalidate()
                throw NetworkClientPrimaryRouterBridgeErrorV0.invalidState
            }
            controlChannel = nil
        }
        try await router.activate()
        guard !invalidated else {
            await router.invalidate()
            throw NetworkClientPrimaryRouterBridgeErrorV0.invalidState
        }
        self.router = router
        self.observeChannel = observeChannel
        actChannel = channel
        self.controlChannel = controlChannel
    }

    public func receive(_ frame: Data) async throws {
        guard !invalidated, let router else {
            throw NetworkClientPrimaryRouterBridgeErrorV0.unavailable
        }
        try await router.receive(frame)
    }

    public func sendAuthenticatedCommand(_ frame: Data) async throws {
        guard !invalidated, let pump else {
            throw NetworkClientPrimaryRouterBridgeErrorV0.unavailable
        }
        try await pump.sendAuthenticatedCommand(frame)
    }

    public func currentRouter() -> ClientPrimaryCommandRouterV0? { router }
    public func currentObserveChannel() -> ClientObserveChannelV0? {
        observeChannel
    }
    public func currentActChannel() -> ClientActChannelV1? { actChannel }
    public func currentControlChannel() -> ClientInteractivePrimaryChannelV0? {
        controlChannel
    }

    /// Use from the pump terminal callback. The pump already owns I/O closure.
    public func primaryTerminated() async {
        guard !invalidated else { return }
        invalidated = true
        let router = self.router
        self.router = nil
        observeChannel = nil
        actChannel = nil
        controlChannel = nil
        pump = nil
        await router?.invalidate()
    }

    /// Use for application backgrounding, explicit disconnect, or shutdown.
    public func cancel() async {
        guard !invalidated else { return }
        invalidated = true
        let router = self.router
        let pump = self.pump
        self.router = nil
        observeChannel = nil
        actChannel = nil
        controlChannel = nil
        self.pump = nil
        await router?.invalidate()
        await pump?.cancel()
    }
}
