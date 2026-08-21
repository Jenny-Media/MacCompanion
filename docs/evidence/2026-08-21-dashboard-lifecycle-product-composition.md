# Dashboard lifecycle product composition evidence — 2026-08-21

## Claim

The dashboard lifecycle boundary now has a bundle-independent product adapter
that composes the Agent reducer/remote-safety authority, two-role login
convergence, and injected process-start requests without optimistically
committing enablement before registration succeeds.

`AgentRemoteLifecycleCoordinatorV1` can prepare an exact immutable transition
without mutation and later compare-and-commit it. A lock, logout, crash, or
other accepted event between those calls makes the prepared transition stale.
The real primary-service integration test proves stale rejection and a later
fresh prepared commit through the same root-bound status and remote-session
authority.

`MacDashboardLifecycleProductAdapterV1` performs enable in this order:

1. prepare the exact transition;
2. converge Agent then menu login registration;
3. commit only that exact before-state transition; and
4. request Agent and menu process starts.

Registration failure uses the existing reverse rollback. If commit fails while
desired state remains disabled, both roles are unregistered as compensation.
If another accepted enable already owns enabled state, the stale caller does
not tear down its roles and reports `outcomeUnknown`. Process-start failure
keeps enabled intent truthful and a same-desired-state retry reconverges both
registrations and starts.

Disable commits remote-safe state and completes Interactive/primary teardown
before attempting both role removals. Cleanup failure returns not completed but
cannot restore remote ingress. An already-disabled retry still converges both
roles absent. All lifecycle commands serialize, and transition construction now
rejects wall times outside the safe-integer profile.

## Automated evidence

Twelve focused product tests plus the existing real-root lifecycle integration
prove:

- Agent-then-menu registration before exact remote commit;
- process starts only after commit;
- registration rollback without a remote commit;
- rollback-failure ambiguity;
- stale-commit compensation while disabled;
- protection of roles owned by another accepted enable;
- remote-safe disable before both unregistrations;
- cleanup failure preserving known disabled state;
- committed enabled intent under process-start failure;
- same-desired-state enabled and disabled convergence;
- unsafe-time rejection before registration; and
- independent lifecycle-command serialization.

The final hardened unsigned gate passed with 63 indexed JSON fixtures, 782
repository files, 34 historical blob paths, 14 repository-material fixtures, 4
manifests, 12 dependency fixtures, 3 privacy manifests, 12 privacy fixtures, 9
required-reason source records, 10 SBOM fixtures, 16 release-evidence fixtures,
1,085 listed Swift tests, both platform cross-compiles including the macOS
SwiftUI target, and all three construction probes. Only the expected read-only
user SwiftPM cache warnings appeared.

## Deliberate limits

The process-start executor remains an injected final-target capability and this
slice does not claim process readiness, final `SMAppService` identities, signed
XPC, or durable enabled-intent recovery across app/Agent restart. Durable
desired-state storage and boot-time reconciliation are the next lifecycle gate.
