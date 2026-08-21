import CompanionClient
import CompanionInteractiveClient
import Foundation

public enum NetworkClientInteractiveRoleProductStateV0:
    Equatable, Sendable
{
    case inactive
    case connecting(interactiveSessionID: UUID)
    case roleChannelsReady(interactiveSessionID: UUID)
    case initialSurfacePreparing(interactiveSessionID: UUID)
    case active(interactiveSessionID: UUID)
    case ending(interactiveSessionID: UUID)
    case failed(interactiveSessionID: UUID)
    case closed
}

/// Configured-product owner that turns only the selected primary's accepted
/// Control event into one all-or-none role pair. Product callback ordering
/// stores the accepted session in `primaryState` before this actor attempts
/// construction. No state here means media is clean or input is active.
public actor NetworkClientInteractiveRoleProductBindingV0 {
    public private(set) var state:
        NetworkClientInteractiveRoleProductStateV0 = .inactive

    private typealias PairFactory = @Sendable ()
        -> (any NetworkClientInteractiveRolePairOwningV0)?
    private typealias ChannelFactory = @Sendable ()
        -> ClientInteractivePrimaryChannelV0?

    private let hostID: UUID
    private let pairFactory: PairFactory
    private let channelFactory: ChannelFactory
    private let progressPublisher: @Sendable (
        Data,
        UUID,
        NetworkClientInteractiveProductProgressV0
    ) -> Void
    private var pair: (any NetworkClientInteractiveRolePairOwningV0)?
    private var readyPair: NetworkClientInteractiveReadyRolePairV0?
    private var initialDesktop:
        NetworkClientInteractiveInitialDesktopActivationV0?
    private var connectionID: Data?
    private var activationID: UUID?
    private var connectTask: Task<Void, Never>?

    package init(
        hostID: UUID,
        primaryState: NetworkClientPrimaryApplicationStateV0,
        connector: any NetworkClientInteractiveRoleConnectingV0
    ) {
        self.hostID = hostID
        pairFactory = { [weak primaryState] in
            primaryState?.makeInteractiveRolePairOwner(
                connector: connector
            )
        }
        channelFactory = { [weak primaryState] in
            primaryState?.interactiveControlChannelForInitialDesktop()
        }
        progressPublisher = { [weak primaryState]
            connectionID, interactiveSessionID, progress in
            primaryState?.acceptInteractiveProductProgress(
                connectionID: connectionID,
                interactiveSessionID: interactiveSessionID,
                progress: progress
            )
        }
    }

    package init(
        hostID: UUID,
        pairFactory: @escaping @Sendable ()
            -> (any NetworkClientInteractiveRolePairOwningV0)?,
        channelFactory: @escaping @Sendable ()
            -> ClientInteractivePrimaryChannelV0? = { nil },
        progressPublisher: @escaping @Sendable (
            Data,
            UUID,
            NetworkClientInteractiveProductProgressV0
        ) -> Void = { _, _, _ in }
    ) {
        self.hostID = hostID
        self.pairFactory = pairFactory
        self.channelFactory = channelFactory
        self.progressPublisher = progressPublisher
    }

    package nonisolated var productEvents:
        NetworkClientPrimaryProductEventsV0
    {
        NetworkClientPrimaryProductEventsV0(
            publishControl: { [weak self] publication in
                Task { await self?.accept(publication) }
            },
            primarySelected: { [weak self] selection in
                Task { await self?.selected(selection.authenticatedSession) }
            },
            primaryTerminated: { [weak self] hostID, connectionID in
                Task {
                    await self?.terminated(
                        hostID: hostID,
                        connectionID: connectionID
                    )
                }
            }
        )
    }

    public func close() async {
        guard state != .closed else { return }
        await retirePair()
        state = .closed
    }

    public func startInitialDesktop(
        renderer: any ClientInteractiveInitialMediaRenderingV0
    ) async throws -> NetworkClientInteractiveInitialDesktopStartV0 {
        guard case let .roleChannelsReady(interactiveSessionID) = state,
              initialDesktop == nil,
              let readyPair,
              let channel = channelFactory(),
              let connectionID,
              let activationID else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.unavailable
        }
        setState(
            .initialSurfacePreparing(
                interactiveSessionID: interactiveSessionID
            ),
            progress: .initialSurfacePreparing,
            connectionID: connectionID,
            interactiveSessionID: interactiveSessionID
        )
        let activation: NetworkClientInteractiveInitialDesktopActivationV0
        do {
            activation = try NetworkClientInteractiveInitialDesktopActivationV0(
                channel: channel,
                inputConnection: readyPair.input,
                mediaConnection: readyPair.media,
                renderer: renderer
            )
        } catch {
            failInitialSurfaceIfCurrent(
                activationID: activationID,
                interactiveSessionID: interactiveSessionID,
                connectionID: connectionID
            )
            throw error
        }
        initialDesktop = activation
        do {
            let descriptor = try await activation.start()
            guard self.activationID == activationID,
                  initialDesktop === activation else {
                await activation.close()
                throw NetworkClientInteractiveInitialDesktopErrorV0
                    .unavailable
            }
            return NetworkClientInteractiveInitialDesktopStartV0(
                activation: activation,
                descriptor: descriptor
            )
        } catch {
            if self.activationID == activationID,
               initialDesktop === activation {
                initialDesktop = nil
                failInitialSurfaceIfCurrent(
                    activationID: activationID,
                    interactiveSessionID: interactiveSessionID,
                    connectionID: connectionID
                )
            }
            throw error
        }
    }

    /// Promotes the product only after the primary reply pump confirms the
    /// exact rendered-frame acknowledgement. Role-channel readiness alone is
    /// never reported as an active Remote Control surface.
    @discardableResult
    public func refreshInitialDesktopState() async -> Bool {
        if case .active = state { return true }
        guard case let .initialSurfacePreparing(interactiveSessionID) = state,
              let activation = initialDesktop,
              let connectionID,
              let activationID else { return false }
        let active = await activation.refreshPrimaryState()
        guard self.activationID == activationID,
              initialDesktop === activation else { return false }
        if active {
            setState(
                .active(interactiveSessionID: interactiveSessionID),
                progress: .active,
                connectionID: connectionID,
                interactiveSessionID: interactiveSessionID
            )
            return true
        }
        let phase = await activation.phase
        if phase == .failed || phase == .closed {
            initialDesktop = nil
            failInitialSurfaceIfCurrent(
                activationID: activationID,
                interactiveSessionID: interactiveSessionID,
                connectionID: connectionID
            )
        }
        return false
    }

    private func selected(_ session: ClientAuthenticatedSessionV0) async {
        guard state != .closed, session.hostID == hostID else { return }
        if let connectionID, connectionID != session.connectionID {
            await retirePair()
            state = .inactive
        }
    }

    private func accept(
        _ publication: NetworkClientControlPublicationV0
    ) async {
        guard state != .closed, publication.hostID == hostID else { return }
        switch publication.event {
        case let .accepted(session, _):
            await activate(
                sessionID: session.interactiveSessionID,
                connectionID: publication.connectionID
            )
        case let .endSubmitted(interactiveSessionID, _):
            if connectionID == publication.connectionID {
                await retirePair()
                connectionID = publication.connectionID
                state = .ending(
                    interactiveSessionID: interactiveSessionID
                )
            }
        case .ended:
            if connectionID == publication.connectionID {
                await retirePair()
                state = .inactive
            }
        case let .endRejected(interactiveSessionID, _):
            if connectionID == publication.connectionID {
                await retirePair()
                connectionID = publication.connectionID
                state = .failed(
                    interactiveSessionID: interactiveSessionID
                )
            }
        case .requestSubmitted, .approvalSubmitted, .remoteRejected:
            if connectionID == publication.connectionID {
                await retirePair()
                state = .inactive
            }
        }
    }

    private func activate(sessionID: UUID, connectionID: Data) async {
        await retirePair()
        self.connectionID = connectionID
        guard let pair = pairFactory() else {
            setState(
                .failed(interactiveSessionID: sessionID),
                progress: .failed(.roleChannelsConnecting),
                connectionID: connectionID,
                interactiveSessionID: sessionID
            )
            return
        }
        let activationID = UUID()
        self.activationID = activationID
        self.pair = pair
        setState(
            .connecting(interactiveSessionID: sessionID),
            progress: .roleChannelsConnecting,
            connectionID: connectionID,
            interactiveSessionID: sessionID
        )
        connectTask = Task { [weak self] in
            do {
                let readyPair = try await pair.connect()
                await self?.finished(
                    activationID: activationID,
                    sessionID: sessionID,
                    readyPair: readyPair
                )
            } catch {
                await self?.finished(
                    activationID: activationID,
                    sessionID: sessionID,
                    readyPair: nil
                )
            }
        }
    }

    private func finished(
        activationID: UUID,
        sessionID: UUID,
        readyPair: NetworkClientInteractiveReadyRolePairV0?
    ) async {
        guard self.activationID == activationID else { return }
        connectTask = nil
        if let readyPair {
            self.readyPair = readyPair
            guard let connectionID else { return }
            setState(
                .roleChannelsReady(interactiveSessionID: sessionID),
                progress: .roleChannelsReady,
                connectionID: connectionID,
                interactiveSessionID: sessionID
            )
        } else {
            await pair?.close()
            pair = nil
            self.readyPair = nil
            self.activationID = nil
            guard let connectionID else { return }
            setState(
                .failed(interactiveSessionID: sessionID),
                progress: .failed(.roleChannelsConnecting),
                connectionID: connectionID,
                interactiveSessionID: sessionID
            )
        }
    }

    private func terminated(hostID: UUID, connectionID: Data) async {
        guard state != .closed,
              hostID == self.hostID,
              connectionID == self.connectionID else { return }
        connectTask?.cancel()
        connectTask = nil
        await initialDesktop?.close()
        initialDesktop = nil
        await pair?.primaryTerminated(
            hostID: hostID,
            connectionID: connectionID
        )
        pair = nil
        readyPair = nil
        self.connectionID = nil
        activationID = nil
        state = .inactive
    }

    private func failInitialSurfaceIfCurrent(
        activationID: UUID,
        interactiveSessionID: UUID,
        connectionID: Data
    ) {
        guard self.activationID == activationID,
              self.connectionID == connectionID else { return }
        setState(
            .failed(interactiveSessionID: interactiveSessionID),
            progress: .failed(.initialSurface),
            connectionID: connectionID,
            interactiveSessionID: interactiveSessionID
        )
    }

    private func setState(
        _ value: NetworkClientInteractiveRoleProductStateV0,
        progress: NetworkClientInteractiveProductProgressV0,
        connectionID: Data,
        interactiveSessionID: UUID
    ) {
        state = value
        progressPublisher(connectionID, interactiveSessionID, progress)
    }

    private func retirePair() async {
        activationID = nil
        connectTask?.cancel()
        connectTask = nil
        await initialDesktop?.close()
        initialDesktop = nil
        await pair?.close()
        pair = nil
        readyPair = nil
        connectionID = nil
    }
}
