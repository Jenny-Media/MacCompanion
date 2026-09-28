import CompanionClient
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
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
    private var automaticFocusHandler:
        (@Sendable (ClientSurfaceFocusEventV0) async throws -> Void)?
    private var pendingFocusPublication: NetworkClientFocusPublicationV0?
    private var nativeEnrollment: ClientNativeVideoEnrollmentSessionV0?
    private var webRTC:
        ClientWebRTCNegotiationCoordinatorV0?

    private var currentInteractiveSessionID: UUID? {
        switch state {
        case .connecting(let id), .roleChannelsReady(let id),
             .initialSurfacePreparing(let id), .active(let id),
             .ending(let id), .failed(let id):
            id
        case .inactive, .closed:
            nil
        }
    }

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
            publishFocus: { [weak self] publication in
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
            },
            // `NWConnection.waiting` is a bounded primary-transport pause,
            // not primary loss. Retain independently authenticated media and
            // input roles until the primary either recovers or emits its exact
            // terminal event. Immediate retirement here turned ordinary Wi-Fi
            // path changes into a user-visible Control disconnect.
            primaryTransportInterrupted: { _, _ in }
        )
    }

    public func close() async {
        guard state != .closed else { return }
        await retirePair()
        state = .closed
    }

    /// Starts the candidate video peer on the selected authenticated primary.
    /// The caller supplies a peer whose renderer blanks on close. This never
    /// promotes Control or enables input; the existing visible-frame gate
    /// remains authoritative until WebRTC has its own receipt profile.
    public func startWebRTC(
        descriptor: AdaptiveSurfaceDescriptor,
        peer: any ClientWebRTCVideoPeerV0
    ) async throws {
        let expectedConnectionID = connectionID
        let expectedActivationID = activationID
        let sessionID: UUID
        switch state {
        case .initialSurfacePreparing(let id), .active(let id):
            sessionID = id
        default:
            await peer.close()
            throw NetworkClientInteractiveInitialDesktopErrorV0.unavailable
        }
        guard descriptor.interactiveSessionID == sessionID,
              let channel = channelFactory(),
              expectedConnectionID != nil,
              expectedActivationID != nil else {
            await peer.close()
            throw NetworkClientInteractiveInitialDesktopErrorV0.unavailable
        }
        let candidate = ClientWebRTCNegotiationCoordinatorV0(
            signaling: channel
        )
        let previous = webRTC
        webRTC = candidate
        await previous?.close()
        do {
            try await candidate.start(descriptor: descriptor, peer: peer)
            guard webRTC === candidate,
                  connectionID == expectedConnectionID,
                  activationID == expectedActivationID else {
                await candidate.close()
                throw NetworkClientInteractiveInitialDesktopErrorV0.unavailable
            }
        } catch {
            if webRTC === candidate { webRTC = nil }
            await candidate.close()
            throw error
        }
    }

    @discardableResult
    public func acknowledgeNativePresentation(nativeGeneration: Int64, encodedWidth: UInt16, encodedHeight: UInt16) async throws -> InteractiveNativeVideoPresentationReceiptBodyV0 {
        guard case let .active(sessionID) = state, let owner = nativeEnrollment,
              let connectionID, let activationID else { throw NetworkClientInteractiveInitialDesktopErrorV0.unavailable }
        let receipt = try await owner.acknowledgePresentation(nativeGeneration: nativeGeneration,
            encodedWidth: encodedWidth, encodedHeight: encodedHeight)
        guard nativeEnrollment === owner, state == .active(interactiveSessionID: sessionID),
              self.connectionID == connectionID, self.activationID == activationID, await owner.isCurrent() else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.unavailable
        }
        return receipt
    }

    /// Uses the selected primary's existing session-key custody. Platform TLS
    /// identity/launch and the native renderer remain separately admitted seams.
    public func enrollNativeVideo(
        descriptor: AdaptiveSurfaceDescriptor,
        clientCertificateDER: Data,
        signer: any ClientSessionAuthenticationSigningV0,
        validateCertificate: @escaping @Sendable (Data) async throws -> Bool
    ) async throws -> ClientNativeVideoEnrolledSessionV0 {
        guard case let .active(sessionID) = state,
              descriptor.interactiveSessionID == sessionID,
              nativeEnrollment == nil, let channel = channelFactory(),
              let connectionID, let activationID else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.unavailable
        }
        let candidate = ClientNativeVideoEnrollmentSessionV0(channel: channel, signer: signer,
            validateCertificate: validateCertificate)
        nativeEnrollment = candidate
        do {
            let result = try await candidate.enroll(descriptor: descriptor, clientCertificateDER: clientCertificateDER)
            guard nativeEnrollment === candidate, self.connectionID == connectionID,
                  self.activationID == activationID, await candidate.isCurrent() else {
                throw NetworkClientInteractiveInitialDesktopErrorV0.unavailable
            }
            return result
        } catch {
            if nativeEnrollment === candidate { nativeEnrollment = nil }
            await candidate.close()
            throw error
        }
    }

    public func isNativeVideoEnrollmentCurrent() async -> Bool {
        guard let nativeEnrollment else { return false }
        return await nativeEnrollment.isCurrent()
    }

    public func stopNativeVideoEnrollment() async {
        let retiring = nativeEnrollment
        nativeEnrollment = nil
        await retiring?.close()
    }

    public func stopWebRTC() async {
        let retiring = webRTC
        webRTC = nil
        await retiring?.close()
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
                renderer: renderer,
                failure: { [weak self] in
                    await self?.initialDesktopFailed(activationID: activationID,
                        interactiveSessionID: interactiveSessionID,
                        connectionID: connectionID)
                }
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
        let interactiveSessionID: UUID
        switch state {
        case .active(let id), .initialSurfacePreparing(let id): interactiveSessionID = id
        default: return false
        }
        guard
              let activation = initialDesktop,
              let connectionID,
              let activationID else { return false }
        let active = await activation.refreshPrimaryState()
        guard self.activationID == activationID,
              initialDesktop === activation else { return false }
        if active {
            if case .active = state { return true }
            setState(
                .active(interactiveSessionID: interactiveSessionID),
                progress: .active,
                connectionID: connectionID,
                interactiveSessionID: interactiveSessionID
            )
            if let pendingFocusPublication {
                self.pendingFocusPublication = nil
                await accept(pendingFocusPublication)
            }
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

    package func bindAutomaticFocusHandler(
        activation: NetworkClientInteractiveInitialDesktopActivationV0,
        handler: @escaping @Sendable (
            ClientSurfaceFocusEventV0
        ) async throws -> Void
    ) throws {
        guard automaticFocusHandler == nil,
              initialDesktop === activation,
              activationID != nil else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.unavailable
        }
        automaticFocusHandler = handler
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
                if case .connecting = state {
                    await retirePair()
                    connectionID = publication.connectionID
                }
                state = .ending(
                    interactiveSessionID: interactiveSessionID
                )
                await initialDesktop?.beginEnding()
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
        case .requestSubmitted, .approvalFailed, .approvalSubmitted,
             .remoteRejected:
            if connectionID == publication.connectionID {
                await retirePair()
                state = .inactive
            }
        case let .mediaOffer(offer):
            guard connectionID == publication.connectionID,
                  offer.body.fence.interactiveSessionID.rawValue
                    == currentInteractiveSessionID else { return }
            await webRTC?.receiveOffer(offer)
        case let .mediaReady(ready):
            guard connectionID == publication.connectionID,
                  ready.body.fence.interactiveSessionID.rawValue
                    == currentInteractiveSessionID else { return }
            await webRTC?.receiveReady(ready)
        case .mediaRejected:
            if connectionID == publication.connectionID {
                await webRTC?.reject()
            }
        }
    }

    private func accept(
        _ publication: NetworkClientFocusPublicationV0
    ) async {
        if case .initialSurfacePreparing = state,
           publication.hostID == hostID,
           publication.connectionID == connectionID {
            pendingFocusPublication = publication
            return
        }
        guard case let .active(interactiveSessionID) = state,
              publication.hostID == hostID,
              publication.connectionID == connectionID,
              let activation = initialDesktop,
              let activationID,
              let automaticFocusHandler else { return }
        do {
            try await automaticFocusHandler(publication.event)
        } catch {
            IOSClientRuntimeDiagnosticLogV0.record(
                "interactive.automatic-focus-handler.terminal",
                error: error
            )
            guard self.activationID == activationID,
                  initialDesktop === activation else { return }
            await activation.close()
            initialDesktop = nil
            failInitialSurfaceIfCurrent(
                activationID: activationID,
                interactiveSessionID: interactiveSessionID,
                connectionID: publication.connectionID
            )
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
        IOSClientRuntimeDiagnosticLogV0.record("interactive.roles.primary-terminated")
        connectTask?.cancel()
        connectTask = nil
        await webRTC?.close()
        webRTC = nil
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

    private func initialDesktopFailed(
        activationID: UUID, interactiveSessionID: UUID, connectionID: Data
    ) async {
        guard self.activationID == activationID,
              self.connectionID == connectionID else { return }
        IOSClientRuntimeDiagnosticLogV0.record("interactive.roles.initial-desktop-failed")
        failInitialSurfaceIfCurrent(activationID: activationID,
            interactiveSessionID: interactiveSessionID, connectionID: connectionID)
        await webRTC?.close()
        webRTC = nil
        self.activationID = nil
        initialDesktop = nil
        automaticFocusHandler = nil
        pendingFocusPublication = nil
        readyPair = nil
        let retiring = pair
        pair = nil
        await retiring?.close()
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
        let native = nativeEnrollment
        nativeEnrollment = nil
        activationID = nil
        await native?.close()
        await webRTC?.close()
        webRTC = nil
        activationID = nil
        automaticFocusHandler = nil
        pendingFocusPublication = nil
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
