import CompanionAgent
import CompanionHostSession
import CompanionNetworkPlatform
import Foundation

private actor AgentNetworkPrimaryTransportV1:
    AgentPrimaryTransportClosingV1
{
    let pump: NetworkHostPrimaryFramePumpV0

    init(pump: NetworkHostPrimaryFramePumpV0) {
        self.pump = pump
    }

    func closeTransport() async {
        await pump.cancel()
    }
}

public struct AgentNetworkPrimaryConnectionV1:
    AgentNetworkBoundPrimaryConnectionV1, Sendable
{
    public let session: AuthenticatedPrimarySessionV0
    public let pump: NetworkHostPrimaryFramePumpV0
    private let primarySessions: AgentPrimarySessionAuthorityV1
    private let beginsFromClassifiedFrame: Bool

    fileprivate init(
        session: AuthenticatedPrimarySessionV0,
        pump: NetworkHostPrimaryFramePumpV0,
        primarySessions: AgentPrimarySessionAuthorityV1,
        beginsFromClassifiedFrame: Bool = false
    ) {
        self.session = session
        self.pump = pump
        self.primarySessions = primarySessions
        self.beginsFromClassifiedFrame = beginsFromClassifiedFrame
    }

    public func begin() async throws {
        if beginsFromClassifiedFrame {
            try await pump.beginOnClassifiedConnection()
        } else {
            try await pump.beginOnVerifiedReadyConnection()
        }
    }

    public func cancel() async {
        await pump.cancel()
        await primarySessions.closeIfCurrent(session)
    }

    public func authenticatedPrimaryConnectionID() async -> Data? {
        await session.authenticatedPrimaryConnectionID()
    }

    public func sendAuthenticatedEvent(
        _ eventJSON: Data,
        primaryConnectionID: Data
    ) async throws {
        let authenticatedID = await session.authenticatedPrimaryConnectionID()
        guard primaryConnectionID == authenticatedID else {
            throw AgentNetworkAuthenticatedEventSinkErrorV2.unavailable
        }
        try await pump.sendAuthenticatedEvent(eventJSON)
    }
}

/// Consumes one exact verified-ready connection and binds its frame pump to the
/// already startup-reconciled Agent authority. No semantic dependency can be
/// supplied by the listener or reconstructed from TLS metadata.
public struct AgentNetworkPrimaryConnectionFactoryV1: Sendable {
    private let primarySessions: AgentPrimarySessionAuthorityV1

    public init(primarySessions: AgentPrimarySessionAuthorityV1) {
        self.primarySessions = primarySessions
    }

    public func bind(
        verifiedReadyConnection: NetworkHostVerifiedReadyConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void = { _ in }
    ) async throws -> AgentNetworkPrimaryConnectionV1 {
        let session = try await primarySessions.open(
            tlsBinding: verifiedReadyConnection.tlsBinding,
            acceptedAtMonotonicMilliseconds: acceptedAtMonotonicMilliseconds
        )
        let pump: NetworkHostPrimaryFramePumpV0
        do {
            pump = try NetworkHostPrimaryFramePumpV0(
                verifiedReadyConnection: verifiedReadyConnection,
                session: session,
                context: context,
                terminal: { reason in
                    terminal(reason)
                    Task {
                        await primarySessions.closeIfCurrent(session)
                    }
                }
            )
        } catch {
            await primarySessions.closeIfCurrent(session)
            throw error
        }
        do {
            let transport = AgentNetworkPrimaryTransportV1(
                pump: pump
            )
            try await primarySessions.attachTransport(transport, to: session)
            return AgentNetworkPrimaryConnectionV1(
                session: session,
                pump: pump,
                primarySessions: primarySessions
            )
        } catch {
            await pump.cancel()
            await primarySessions.closeIfCurrent(session)
            throw error
        }
    }

    public func bind(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void = { _ in }
    ) async throws -> AgentNetworkPrimaryConnectionV1 {
        let session = try await primarySessions.open(
            tlsBinding: classifiedConnection.tlsBinding,
            acceptedAtMonotonicMilliseconds: acceptedAtMonotonicMilliseconds
        )
        let pump: NetworkHostPrimaryFramePumpV0
        do {
            pump = try NetworkHostPrimaryFramePumpV0(
                classifiedConnection: classifiedConnection,
                session: session,
                context: context,
                terminal: { reason in
                    terminal(reason)
                    Task {
                        await primarySessions.closeIfCurrent(session)
                    }
                }
            )
        } catch {
            classifiedConnection.cancel()
            await primarySessions.closeIfCurrent(session)
            throw error
        }
        do {
            let transport = AgentNetworkPrimaryTransportV1(pump: pump)
            try await primarySessions.attachTransport(transport, to: session)
            return AgentNetworkPrimaryConnectionV1(
                session: session,
                pump: pump,
                primarySessions: primarySessions,
                beginsFromClassifiedFrame: true
            )
        } catch {
            await pump.cancel()
            await primarySessions.closeIfCurrent(session)
            throw error
        }
    }
}

extension NetworkHostAcceptedConnectionV0:
    AgentNetworkAcceptedConnectionStartingV1 {}

extension AgentNetworkPrimaryConnectionFactoryV1:
    AgentNetworkPrimaryConnectionBindingV1
{
    public func bindPrimaryConnection(
        verifiedReadyConnection: NetworkHostVerifiedReadyConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void
    ) async throws -> any AgentNetworkBoundPrimaryConnectionV1 {
        try await bind(
            verifiedReadyConnection: verifiedReadyConnection,
            acceptedAtMonotonicMilliseconds: acceptedAtMonotonicMilliseconds,
            context: context,
            terminal: terminal
        )
    }
}
