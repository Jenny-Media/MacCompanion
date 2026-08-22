#if os(macOS)
import CompanionAgent
import CompanionDomain
import CompanionNetworkPlatform
import Dispatch
import Foundation

/// Fixed v0.1 LAN profile. The port is deliberately in IANA's dynamic/private
/// range; listener failure is terminal for this prepared startup rather than
/// silently selecting a different port and invalidating saved private routes.
public enum MacAgentEnabledProductProfileV1 {
    public static let listenerPort: UInt16 = 59_653
    public static let initialPairingPolicyRevision = PolicyRevision(
        rawValue: 1
    )
}

package struct SystemAgentLocalPairingTimeSourceV1:
    AgentLocalPairingTimeSamplingV0,
    Sendable
{
    package init() {}

    package func currentPairingTime() throws
        -> AgentLocalPairingTimeSampleV0
    {
        let wall = Date().timeIntervalSince1970 * 1_000
        guard wall.isFinite, wall >= 0, wall <= Double(Int64.max) else {
            throw AgentLocalPairingSessionErrorV0.invalidClock
        }
        let monotonic = DispatchTime.now().uptimeNanoseconds / 1_000_000
        guard monotonic <= UInt64(Int64.max) else {
            throw AgentLocalPairingSessionErrorV0.invalidClock
        }
        return try AgentLocalPairingTimeSampleV0(
            wallNowUnixMilliseconds: Int64(wall.rounded(.down)),
            monotonicNowMilliseconds: Int64(monotonic)
        )
    }
}

@available(macOS 26.0, *)
package protocol MacAgentEnabledProductRuntimeProductV1:
    AnyObject,
    Sendable
{
    func composeForEnabledRuntime(
        port: UInt16,
        timeSource: any AgentLocalPairingTimeSamplingV0,
        policySource: any AgentLocalPairingPolicyReadingV0
    ) async throws

    func startListenerForEnabledRuntime(
        queue: DispatchQueue,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        primaryContext: @escaping @Sendable () ->
            NetworkHostRequestContextV0,
        pairingContext: @escaping @Sendable () ->
            NetworkHostPairingRequestContextV0
    ) async throws

    func finish() async
}

@available(macOS 26.0, *)
extension MacAgentPreparedProductV1:
    MacAgentEnabledProductRuntimeProductV1
{
    package func composeForEnabledRuntime(
        port: UInt16,
        timeSource: any AgentLocalPairingTimeSamplingV0,
        policySource: any AgentLocalPairingPolicyReadingV0
    ) async throws {
        try await startAndComposeNetworkPairingProduct(
            port: port,
            timeSource: timeSource,
            policySource: policySource
        )
    }

    package func startListenerForEnabledRuntime(
        queue: DispatchQueue,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        primaryContext: @escaping @Sendable () ->
            NetworkHostRequestContextV0,
        pairingContext: @escaping @Sendable () ->
            NetworkHostPairingRequestContextV0
    ) async throws {
        try await startNetworkListener(
            queue: queue,
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            primaryContext: primaryContext,
            pairingRequestContext: pairingContext
        )
    }
}

/// Single enabled-startup owner for the permanent Agent. It keeps the product
/// inert until called, then preserves the required order: authenticated local
/// authorization, authenticated menu generation, one network/pairing product,
/// and one listener using the same conservative request-context authority.
/// Any failure or cancellation terminally retires the complete preparation.
@available(macOS 26.0, *)
package actor MacAgentEnabledProductRuntimeV1 {
    package typealias PrimaryContext = @Sendable () ->
        NetworkHostRequestContextV0
    package typealias PairingContext = @Sendable () ->
        NetworkHostPairingRequestContextV0

    private let product: any MacAgentEnabledProductRuntimeProductV1
    private let queue: DispatchQueue
    private let timeSource: any AgentLocalPairingTimeSamplingV0
    private let policySource: any AgentLocalPairingPolicyReadingV0
    private let monotonicNowMilliseconds: @Sendable () -> UInt64
    private var startTask: Task<Void, Error>?
    private var finishTask: Task<Void, Never>?

    package init(
        product: any MacAgentEnabledProductRuntimeProductV1,
        queue: DispatchQueue = DispatchQueue(
            label: "media.jenny.maccompanion.agent.listener",
            qos: .userInitiated
        ),
        timeSource: any AgentLocalPairingTimeSamplingV0 =
            SystemAgentLocalPairingTimeSourceV1(),
        policySource: any AgentLocalPairingPolicyReadingV0 =
            StaticAgentLocalPairingPolicySourceV0(
                MacAgentEnabledProductProfileV1
                    .initialPairingPolicyRevision
            ),
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds / 1_000_000
        }
    ) {
        self.product = product
        self.queue = queue
        self.timeSource = timeSource
        self.policySource = policySource
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
    }

    package func start(
        primaryContext: @escaping PrimaryContext,
        pairingContext: @escaping PairingContext
    ) async throws {
        guard finishTask == nil else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        guard startTask == nil else {
            throw MacAgentPreparedProductCompositionErrorV1
                .networkListenerAlreadyStarted
        }
        let product = self.product
        let queue = self.queue
        let timeSource = self.timeSource
        let policySource = self.policySource
        let monotonicNowMilliseconds = self.monotonicNowMilliseconds
        let task = Task {
            try await product.composeForEnabledRuntime(
                port: MacAgentEnabledProductProfileV1.listenerPort,
                timeSource: timeSource,
                policySource: policySource
            )
            try Task.checkCancellation()
            try await product.startListenerForEnabledRuntime(
                queue: queue,
                monotonicNowMilliseconds: monotonicNowMilliseconds,
                primaryContext: primaryContext,
                pairingContext: pairingContext
            )
            try Task.checkCancellation()
        }
        startTask = task
        do {
            try await withTaskCancellationHandler {
                try await task.value
                try Task.checkCancellation()
            } onCancel: {
                task.cancel()
            }
            guard finishTask == nil else {
                throw MacAgentPreparedProductCompositionErrorV1.terminal
            }
        } catch {
            await finish()
            throw error
        }
    }

    package func finish() async {
        if let finishTask {
            await finishTask.value
            return
        }
        let product = self.product
        let startTask = self.startTask
        startTask?.cancel()
        let task = Task {
            await product.finish()
            if let startTask { _ = await startTask.result }
        }
        finishTask = task
        await task.value
    }
}
#endif
