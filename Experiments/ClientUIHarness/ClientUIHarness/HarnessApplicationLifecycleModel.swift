import Combine
import CompanionClient
import CompanionClientPlatform
import CompanionClientUI
import CompanionTransport
import CompanionWire
import Dispatch
import Foundation

private actor HarnessPairedHostInventory:
    ClientPairedHostInventoryV1
{
    let host: ClientDurablePairedHostV0

    init(host: ClientDurablePairedHostV0) {
        self.host = host
    }

    func pairedHost(hostID: UUID) -> ClientDurablePairedHostV0? {
        host.hostID == hostID ? host : nil
    }
}

private final class HarnessSyntheticDialer:
    DialRouteAttemptingV0,
    @unchecked Sendable
{
    func attempt(
        _ attempt: DialAttempt,
        roundID: UUID,
        requiredHostFingerprint: Data
    ) async -> DialRouteAttemptOutcomeV0 {
        // This lifecycle scenario asserts Local Discovery. Its catalog also
        // contains Private DNS for route-configuration UI, and the executor
        // deliberately skips stagger delays. Let only the intended synthetic
        // route answer so task scheduling cannot choose a different winner.
        guard attempt.endpoint.kind == .bonjour else {
            return .transientFailure
        }
        return .authenticated(AuthenticatedDialRouteV0(
            endpoint: attempt.endpoint,
            close: {}
        ))
    }
}

@MainActor
private final class HarnessManualReachabilitySource:
    ClientCoarseReachabilitySourceV1
{
    let events: AsyncStream<Bool>

    private let continuation: AsyncStream<Bool>.Continuation
    private var running = false

    init() {
        var captured: AsyncStream<Bool>.Continuation?
        events = AsyncStream(bufferingPolicy: .bufferingNewest(1)) {
            captured = $0
        }
        continuation = captured!
    }

    func start() throws {
        guard !running else {
            throw NetworkClientCoarseReachabilityErrorV1.invalidPhase
        }
        running = true
    }

    func stop() {
        guard running else { return }
        running = false
        continuation.finish()
    }

    func send(_ value: Bool) {
        guard running else { return }
        continuation.yield(value)
    }
}

@MainActor
final class HarnessApplicationLifecycleModel: ObservableObject {
    @Published private(set) var bindingState = "Preparing"
    @Published private(set) var foreground = false
    @Published private(set) var networkReachable = false
    @Published private(set) var dialRounds = 0
    @Published private(set) var terminalFailures = 0
    @Published private(set) var routeGuidance =
        ClientPrivateRouteGuidanceProjectionV1(
            snapshot: HarnessFixtures.initialRouteSnapshot
        )

    private var reachability: HarnessManualReachabilitySource?
    private var owner:
        UIKitClientConfiguredRouteNetworkApplicationOwnerV1?
    private var startedEligibleRound = false

    func start() async {
        guard owner == nil else { return }
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "maccompanion-client-ui-lifecycle-\(UUID())",
                    isDirectory: true
                )
            let routes = try AtomicFileClientConfiguredRouteStoreV1(
                directory: directory
            )
            _ = try await routes.replaceAtomically(
                HarnessFixtures.initialRouteSnapshot,
                expectedRevision: nil
            )
            let lifecycle = try await ClientConfiguredRouteLifecycleV1(
                hostID: HarnessFixtures.hostID,
                pairedHosts: HarnessPairedHostInventory(
                    host: HarnessFixtures.pairedHost
                ),
                routes: routes,
                foreground: false,
                networkReachable: false,
                makeController: { configuration, foreground, reachable in
                    ReconnectControllerV0(
                        state: try configuration.makeReconnectState(
                            foreground: foreground,
                            networkReachable: reachable
                        ),
                        executor: DialRoundExecutorV0(
                            attempter: HarnessSyntheticDialer(),
                            wait: { _ in }
                        ),
                        monotonicNow: Self.monotonicMilliseconds,
                        jitterBasisPoints: { 10_000 }
                    )
                },
                newRouteID: {
                    try WireBytes16(Data(UUID().uuidString.utf8.prefix(16)))
                }
            )
            let invalidRoundID = ProcessInfo.processInfo.arguments.contains(
                "--invalid-round-id"
            )
            let binding = try await ClientConfiguredRouteApplicationBindingV1(
                lifecycle: lifecycle,
                monotonicNow: Self.monotonicMilliseconds,
                roundID: {
                    invalidRoundID
                        ? UUID(uuid: (
                            0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0
                        ))
                        : UUID()
                }
            )
            let reachability = HarnessManualReachabilitySource()
            let owner = UIKitClientConfiguredRouteNetworkApplicationOwnerV1(
                binding: binding,
                source: reachability,
                failure: { [weak self] error in
                    self?.terminalFailures += 1
                    self?.bindingState = "Closed: \(error)"
                },
                stateChanged: { [weak self] snapshot in
                    self?.apply(snapshot)
                }
            )
            self.reachability = reachability
            self.owner = owner
            try await owner.start()
        } catch {
            bindingState = "Closed: \(error)"
        }
    }

    func toggleReachability() {
        reachability?.send(!networkReachable)
    }

    private func apply(
        _ snapshot: ClientConfiguredRouteApplicationBindingSnapshotV1
    ) {
        bindingState = snapshot.phase.rawValue.capitalized
        foreground = snapshot.foreground
        networkReachable = snapshot.networkReachable
        if snapshot.hasStartedEligibleRound, !startedEligibleRound {
            dialRounds += 1
        }
        startedEligibleRound = snapshot.hasStartedEligibleRound
        routeGuidance = ClientPrivateRouteGuidanceProjectionV1(
            bindingSnapshot: snapshot
        )
    }

    nonisolated private static func monotonicMilliseconds() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }
}
