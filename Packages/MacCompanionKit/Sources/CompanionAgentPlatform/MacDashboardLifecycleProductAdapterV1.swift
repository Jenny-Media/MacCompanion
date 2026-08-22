import CompanionAgent
import CompanionLifecycle
import CompanionMacApp
import Foundation

public protocol MacDashboardLifecycleWallClockV1: Sendable {
    func nowUnixMilliseconds() -> Int64
}

public struct SystemMacDashboardLifecycleWallClockV1:
    MacDashboardLifecycleWallClockV1
{
    public init() {}

    public func nowUnixMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
    }
}

/// The permanent containing-app adapter owns the exact mechanism for asking
/// already-registered processes to start. `completed` means both requests were
/// issued and their platform call postconditions were verified; it does not
/// claim either process has reached ready.
public protocol MacDashboardLifecycleProcessStartingV1: Sendable {
    func requestStarts(
        _ effects: [ProductLifecycleEffect]
    ) async -> MacAgentDashboardEffectOutcomeV0
}

/// Construction-only process-start seam for the permanent Agent before the
/// containing app owns authenticated lifecycle execution. It performs no
/// launch, registration, or process lookup and never reports completion.
public struct InertMacDashboardLifecycleProcessStarterV1:
    MacDashboardLifecycleProcessStartingV1
{
    public init() {}

    public func requestStarts(
        _: [ProductLifecycleEffect]
    ) async -> MacAgentDashboardEffectOutcomeV0 {
        .notCompleted
    }
}

/// Composes dashboard desired-state commands with the Agent's lifecycle and
/// login-role authorities. Enable is a saga: prepare, register Agent then menu,
/// compare-and-commit, then request process starts. A stale/failed commit is
/// compensated while authoritative desired state remains disabled. Disable
/// commits remote teardown first and only then unregisters both login roles.
public actor MacDashboardLifecycleProductAdapterV1:
    MacAgentDashboardLifecycleCommandingV0
{
    public typealias TransitionIDSource = @Sendable () -> UUID

    private let lifecycle: any AgentRemoteLifecycleCommandingV1
    private let loginRoles: AgentLoginRoleEffectExecutorV1
    private let processStarter: any MacDashboardLifecycleProcessStartingV1
    private let intentStore: any MacRemoteAccessIntentPersistenceV1
    private let wallClock: any MacDashboardLifecycleWallClockV1
    private let transitionIDSource: TransitionIDSource
    private var commandInProgress = false

    public init(
        lifecycle: any AgentRemoteLifecycleCommandingV1,
        loginRoles: AgentLoginRoleEffectExecutorV1,
        processStarter: any MacDashboardLifecycleProcessStartingV1,
        intentStore: any MacRemoteAccessIntentPersistenceV1,
        wallClock: any MacDashboardLifecycleWallClockV1 =
            SystemMacDashboardLifecycleWallClockV1(),
        transitionIDSource: @escaping TransitionIDSource = { UUID() }
    ) {
        self.lifecycle = lifecycle
        self.loginRoles = loginRoles
        self.processStarter = processStarter
        self.intentStore = intentStore
        self.wallClock = wallClock
        self.transitionIDSource = transitionIDSource
    }

    public func setEnabled(
        _ enabled: Bool
    ) async -> MacAgentDashboardEffectOutcomeV0 {
        guard !commandInProgress else { return .notCompleted }
        commandInProgress = true
        defer { commandInProgress = false }

        if !(await recordDurableIntent(enabled)),
           !(await durableIntentMatches(enabled)) {
            return .notCompleted
        }
        return await convergeToDurableIntent(enabled)
    }

    /// Converges roles and live lifecycle from the record loaded before Agent
    /// construction. The containing app invokes this before exposing readiness.
    /// An absent record is the safe-disabled default.
    public func reconcileAfterRestart() async -> MacAgentDashboardEffectOutcomeV0 {
        guard !commandInProgress else { return .notCompleted }
        commandInProgress = true
        defer { commandInProgress = false }

        let enabled: Bool
        do {
            enabled = try await intentStore.current()?.desiredEnabled ?? false
        } catch {
            return .notCompleted
        }
        return await convergeToDurableIntent(enabled)
    }

    private func convergeToDurableIntent(
        _ enabled: Bool
    ) async -> MacAgentDashboardEffectOutcomeV0 {
        let current = await lifecycle.currentState()
        guard current.desiredEnabled != enabled else {
            return await convergeExisting(enabled: enabled)
        }
        return enabled ? await enable() : await disable()
    }

    private func recordDurableIntent(_ enabled: Bool) async -> Bool {
        for _ in 0..<3 {
            let before: MacRemoteAccessIntentSnapshotV1?
            do {
                before = try await intentStore.current()
            } catch {
                return false
            }
            if before?.desiredEnabled == enabled { return true }
            guard before?.revision !=
                    MacRemoteAccessIntentSnapshotV1.maximumSafeInteger,
                  let snapshot = try? MacRemoteAccessIntentSnapshotV1(
                      revision: (before?.revision ?? 0) + 1,
                      desiredEnabled: enabled,
                      commandID: transitionIDSource(),
                      recordedAtUnixMilliseconds:
                          wallClock.nowUnixMilliseconds()
                  ) else {
                return false
            }
            do {
                _ = try await intentStore.replaceAtomically(
                    snapshot,
                    expectedRevision: before?.revision
                )
                return true
            } catch {
                // A post-rename error is accepted only by exact read-back.
                // A different revision may be a concurrent command; retry its
                // compare-and-set rather than overwriting it blindly.
                if (try? await intentStore.current()) == snapshot {
                    return true
                }
            }
        }
        return false
    }

    private func durableIntentMatches(_ enabled: Bool) async -> Bool {
        (try? await intentStore.current()?.desiredEnabled) == enabled
    }

    private func convergeExisting(
        enabled: Bool
    ) async -> MacAgentDashboardEffectOutcomeV0 {
        let transitionID = transitionIDSource()
        if enabled {
            do {
                let receipt = try await loginRoles
                    .registerForCurrentEnabledState(
                        transitionID: transitionID
                    )
                guard receipt.transitionID == transitionID,
                      receipt.remainingProcessEffects == [
                          .requestAgentStart,
                          .requestMenuStart,
                      ] else {
                    return .outcomeUnknown
                }
                if (await lifecycle.currentState()).consoleSession == .loggedOut {
                    return .completed
                }
                return await processStarter.requestStarts(
                    receipt.remainingProcessEffects
                )
            } catch let error as AgentLoginRoleEffectExecutorErrorV1 {
                return registrationFailureOutcome(error)
            } catch {
                return .outcomeUnknown
            }
        }

        do {
            let receipt = try await loginRoles
                .unregisterForCurrentDisabledState(
                    transitionID: transitionID
                )
            return receipt.transitionID == transitionID
                && receipt.remainingProcessEffects.isEmpty
                ? .completed
                : .outcomeUnknown
        } catch {
            return .notCompleted
        }
    }

    private func enable() async -> MacAgentDashboardEffectOutcomeV0 {
        let prepared: AgentRemoteLifecyclePreparedTransitionV1
        do {
            prepared = try await lifecycle.prepare(
                .enableRequested,
                transitionID: transitionIDSource(),
                observedAtUnixMilliseconds: wallClock.nowUnixMilliseconds()
            )
        } catch {
            return .notCompleted
        }

        let registration: AgentLoginRoleEffectReceiptV1
        do {
            registration = try await loginRoles.registerForEnablement(
                prepared.completed
            )
        } catch let error as AgentLoginRoleEffectExecutorErrorV1 {
            return registrationFailureOutcome(error)
        } catch {
            return .outcomeUnknown
        }

        do {
            let committed = try await lifecycle.commitPrepared(prepared)
            guard committed.completed == prepared.completed,
                  registration.transitionID ==
                    prepared.completed.transitionID,
                  registration.remainingProcessEffects == [
                      .requestAgentStart,
                      .requestMenuStart,
                  ] else {
                return .outcomeUnknown
            }
        } catch {
            // A separate accepted enable now owns the registered roles. Never
            // compensate them from this stale preparation.
            if await lifecycle.currentState().desiredEnabled {
                return .outcomeUnknown
            }
            do {
                _ = try await loginRoles
                    .unregisterAfterFailedEnablement(prepared.completed)
                return .notCompleted
            } catch {
                return .outcomeUnknown
            }
        }

        return await processStarter.requestStarts(
            registration.remainingProcessEffects
        )
    }

    private func disable() async -> MacAgentDashboardEffectOutcomeV0 {
        let prepared: AgentRemoteLifecyclePreparedTransitionV1
        do {
            prepared = try await lifecycle.prepare(
                .disableRequested,
                transitionID: transitionIDSource(),
                observedAtUnixMilliseconds: wallClock.nowUnixMilliseconds()
            )
        } catch {
            return .notCompleted
        }

        let committed: AgentRemoteLifecycleTransitionV1
        do {
            committed = try await lifecycle.commitPrepared(prepared)
        } catch {
            return .notCompleted
        }
        guard committed.completed == prepared.completed else {
            return .outcomeUnknown
        }

        do {
            let receipt = try await loginRoles
                .unregisterAfterRemoteSafety(committed)
            guard receipt.transitionID == prepared.completed.transitionID,
                  receipt.remainingProcessEffects.isEmpty else {
                return .outcomeUnknown
            }
            return .completed
        } catch {
            // Remote teardown and desired-disabled state are already exact;
            // login-role cleanup is incomplete but not ambiguous.
            return .notCompleted
        }
    }

    private func registrationFailureOutcome(
        _ error: AgentLoginRoleEffectExecutorErrorV1
    ) -> MacAgentDashboardEffectOutcomeV0 {
        switch error {
        case let .registrationFailed(_, rollbackFailures):
            rollbackFailures.isEmpty ? .notCompleted : .outcomeUnknown
        case .transitionInProgress, .unsupportedTransition,
             .unregistrationFailed:
            .notCompleted
        }
    }
}
