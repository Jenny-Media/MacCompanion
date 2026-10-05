import CompanionClient
import CompanionDomain
import CompanionInteractiveClient
import CompanionTransport
import CompanionWire
import Dispatch
import Foundation
import Security

public enum NetworkClientReconnectRuntimeErrorV1:
    Error, Equatable, Sendable
{
    case randomnessUnavailable(Int32)
}

/// Stable runtime dependencies shared across configured-route revisions. The
/// paired identity and route catalog are deliberately absent: the composition
/// takes both only from `ClientReconnectConfigurationV1` on every rebuild.
public struct NetworkClientReconnectRuntimeV1: Sendable {
    package let sessionConsentProfile: InteractiveSessionConsentProfileV1
    package let custody: any ClientIdentityKeyCustodyV0
    package let clock: @Sendable () -> NetworkClientClockSnapshotV0
    package let nonce: NetworkClientRouteAttemptConfigurationV0.Nonce
    package let messageID: NetworkClientRouteAttemptConfigurationV0.MessageID
    package let pinnedLeafEvaluator: NetworkClientPinnedLeafEvaluatorV0
    package let verificationQueue: DispatchQueue
    package let connectionQueue: DispatchQueue
    package let productEvents: NetworkClientPrimaryProductEventsV0
    package let staggerWait: DialRoundExecutorV0.StaggerWait
    package let monotonicNow: ReconnectControllerV0.MonotonicNow
    package let jitterBasisPoints: ReconnectControllerV0.JitterBasisPoints
    package let retryScheduled: ReconnectControllerV0.RetryScheduled
    package let failureObserved: ReconnectControllerV0.FailureObserved

    public init(
        custody: any ClientIdentityKeyCustodyV0,
        sessionConsentProfile: InteractiveSessionConsentProfileV1 = .freshUserPresence,
        clock: @escaping @Sendable () -> NetworkClientClockSnapshotV0,
        verificationQueue: DispatchQueue,
        connectionQueue: DispatchQueue,
        productEvents: NetworkClientPrimaryProductEventsV0 = .discarding,
        staggerWait: @escaping DialRoundExecutorV0.StaggerWait = {
            milliseconds in
            guard milliseconds > 0 else { return }
            try? await Task.sleep(
                nanoseconds: UInt64(milliseconds) * 1_000_000
            )
        },
        monotonicNow: @escaping ReconnectControllerV0.MonotonicNow,
        jitterBasisPoints: @escaping ReconnectControllerV0.JitterBasisPoints,
        retryScheduled: @escaping ReconnectControllerV0.RetryScheduled = {
            _ in
        },
        failureObserved: @escaping ReconnectControllerV0.FailureObserved = {
            _ in
        }
    ) {
        self.init(
            custody: custody,
            sessionConsentProfile: sessionConsentProfile,
            clock: clock,
            nonce: Self.systemNonce,
            messageID: { WireUUID(UUID()) },
            pinnedLeafEvaluator: SecurityClientPinnedLeafEvaluatorV0.make(
                wallNowUnixMilliseconds: {
                    clock().wallNowUnixMilliseconds
                }
            ),
            verificationQueue: verificationQueue,
            connectionQueue: connectionQueue,
            productEvents: productEvents,
            staggerWait: staggerWait,
            monotonicNow: monotonicNow,
            jitterBasisPoints: jitterBasisPoints,
            retryScheduled: retryScheduled,
            failureObserved: failureObserved
        )
    }

    package init(
        custody: any ClientIdentityKeyCustodyV0,
        sessionConsentProfile: InteractiveSessionConsentProfileV1 = .freshUserPresence,
        clock: @escaping @Sendable () -> NetworkClientClockSnapshotV0,
        nonce: @escaping NetworkClientRouteAttemptConfigurationV0.Nonce,
        messageID: @escaping NetworkClientRouteAttemptConfigurationV0.MessageID,
        pinnedLeafEvaluator: @escaping NetworkClientPinnedLeafEvaluatorV0,
        verificationQueue: DispatchQueue,
        connectionQueue: DispatchQueue,
        productEvents: NetworkClientPrimaryProductEventsV0 = .discarding,
        staggerWait: @escaping DialRoundExecutorV0.StaggerWait = {
            milliseconds in
            guard milliseconds > 0 else { return }
            try? await Task.sleep(
                nanoseconds: UInt64(milliseconds) * 1_000_000
            )
        },
        monotonicNow: @escaping ReconnectControllerV0.MonotonicNow,
        jitterBasisPoints: @escaping ReconnectControllerV0.JitterBasisPoints,
        retryScheduled: @escaping ReconnectControllerV0.RetryScheduled = {
            _ in
        },
        failureObserved: @escaping ReconnectControllerV0.FailureObserved = {
            _ in
        }
    ) {
        self.sessionConsentProfile = sessionConsentProfile
        self.custody = custody
        self.clock = clock
        self.nonce = nonce
        self.messageID = messageID
        self.pinnedLeafEvaluator = pinnedLeafEvaluator
        self.verificationQueue = verificationQueue
        self.connectionQueue = connectionQueue
        self.productEvents = productEvents
        self.staggerWait = staggerWait
        self.monotonicNow = monotonicNow
        self.jitterBasisPoints = jitterBasisPoints
        self.retryScheduled = retryScheduled
        self.failureObserved = failureObserved
    }

    private static func systemNonce() throws -> WireBytes32 {
        var bytes = Data(count: WireBytes32Tag.byteCount)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(
                kSecRandomDefault,
                buffer.count,
                buffer.baseAddress!
            )
        }
        guard status == errSecSuccess else {
            throw NetworkClientReconnectRuntimeErrorV1
                .randomnessUnavailable(status)
        }
        return try WireBytes32(bytes)
    }

    package func replacingProductEvents(
        _ value: NetworkClientPrimaryProductEventsV0
    ) -> NetworkClientReconnectRuntimeV1 {
        NetworkClientReconnectRuntimeV1(
            custody: custody,
            sessionConsentProfile: sessionConsentProfile,
            clock: clock,
            nonce: nonce,
            messageID: messageID,
            pinnedLeafEvaluator: pinnedLeafEvaluator,
            verificationQueue: verificationQueue,
            connectionQueue: connectionQueue,
            productEvents: value,
            staggerWait: staggerWait,
            monotonicNow: monotonicNow,
            jitterBasisPoints: jitterBasisPoints,
            retryScheduled: retryScheduled,
            failureObserved: failureObserved
        )
    }

    package func makeInteractiveRoleConnector()
        -> NetworkClientInteractiveRoleConnectorV0
    {
        NetworkClientInteractiveRoleConnectorV0(
            pinnedLeafEvaluator: pinnedLeafEvaluator,
            verificationQueue: verificationQueue,
            connectionQueue: connectionQueue,
            monotonicNowMilliseconds: {
                clock().monotonicNowMilliseconds
            },
            nonce: nonce,
            messageID: messageID
        )
    }
}

public enum NetworkClientConfiguredReconnectCompositionV1 {
    public static func makeController(
        configuration: ClientReconnectConfigurationV1,
        foreground: Bool,
        networkReachable: Bool,
        runtime: NetworkClientReconnectRuntimeV1
    ) throws -> ReconnectControllerV0 {
        let routeAttempt = NetworkClientRouteAttemptV0(
            configuration: try makeRouteAttemptConfiguration(
                configuration: configuration,
                runtime: runtime
            )
        )
        return ReconnectControllerV0(
            state: try configuration.makeReconnectState(
                foreground: foreground,
                networkReachable: networkReachable
            ),
            executor: DialRoundExecutorV0(
                attempter: routeAttempt,
                wait: runtime.staggerWait
            ),
            monotonicNow: runtime.monotonicNow,
            jitterBasisPoints: runtime.jitterBasisPoints,
            retryScheduled: runtime.retryScheduled,
            failureObserved: runtime.failureObserved
        )
    }

    package static func makeRouteAttemptConfiguration(
        configuration: ClientReconnectConfigurationV1,
        runtime: NetworkClientReconnectRuntimeV1
    ) throws -> NetworkClientRouteAttemptConfigurationV0 {
        let signer = try ClientCustodiedSessionSignerV0(
            custody: runtime.custody,
            sessionKey: configuration.pairedHost.sessionKey
        )
        let approvalSigner = try ClientCustodiedOperationApprovalSignerV1(
            custody: runtime.custody,
            approvalKey: configuration.pairedHost.approvalKey
        )
        let interactiveApprovalSigner: any ClientInteractiveApprovalSigningV0
        switch runtime.sessionConsentProfile {
        case .freshUserPresence:
            interactiveApprovalSigner = try ClientCustodiedInteractiveApprovalSignerV0(
                custody: runtime.custody,
                approvalKey: configuration.pairedHost.approvalKey
            )
        case .trustedDevice:
            interactiveApprovalSigner = try ClientCustodiedTrustedInteractiveSignerV1(
                custody: runtime.custody,
                sessionKey: configuration.pairedHost.sessionKey
            )
        }
        return NetworkClientRouteAttemptConfigurationV0(
            clientID: configuration.pairedHost.clientID,
            expectedHostID: configuration.pairedHost.hostID,
            expectedDeviceID: configuration.pairedHost.deviceID,
            signer: signer,
            clock: runtime.clock,
            nonce: runtime.nonce,
            messageID: runtime.messageID,
            pinnedLeafEvaluator: runtime.pinnedLeafEvaluator,
            verificationQueue: runtime.verificationQueue,
            connectionQueue: runtime.connectionQueue,
            configuredRoutes: configuration.catalog,
            primaryProduct: NetworkClientPrimaryProductConfigurationV0(
                pairedHost: configuration.pairedHost,
                approvalSigner: approvalSigner,
                interactiveApprovalSigner: interactiveApprovalSigner,
                clock: runtime.clock,
                messageID: runtime.messageID,
                events: runtime.productEvents
            )
        )
    }
}
