# Mac dashboard action coordinator evidence — 2026-08-21

## Claim

The Mac administration dashboard now has one application-owned execution
boundary for all seven typed actions. SwiftUI and execution consume the same
closed admission policy, preventing enabled-state drift between rendering and
effect invocation.

`MacAgentDashboardActionCoordinatorV0` re-reads and validates current status
before every action, permits only one suspended action at a time, and delegates
privileged work through injected lifecycle, status-retry, pairing, and
sanitized-diagnostic capabilities. Devices and activity history are closed
local navigation outputs and invoke no remote effect.

Effect adapters return only `completed`, `notCompleted`, or `outcomeUnknown`.
The coordinator preserves that distinction: a button tap is never completion,
and ambiguity is never converted to success or definitive failure. Connection
authority invalidation fences a suspended revision, leaves the replacement in
idle state, and permits its original caller to receive only `outcomeUnknown`.
Application invalidation is terminal.

The existing `MacPairingApplicationOwnerV0` directly implements the pairing
action boundary. It reports completion only when its validated Agent-issued QR
receipt is visible; an IPC or receipt failure remains not completed.

## Automated evidence

Twelve focused tests prove:

- exact admission for loading, unavailable, off, ready, paired, and locked
  sources;
- revalidation and denial before any effect call;
- completed lifecycle postcondition publication;
- single-action serialization across a suspended effect;
- authority invalidation fencing without late-state resurrection;
- distinct not-completed and outcome-unknown results;
- revalidated diagnostic export and malformed-export rejection;
- effect-free typed devices/activity navigation;
- distinct status-retry and pairing dispatch;
- terminal application invalidation; and
- existing pairing-owner success only with a visible receipt.

The final hardened unsigned gate passed with 63 indexed JSON fixtures, 779
repository files, 34 historical blob paths, 14 repository-material fixtures, 4
manifests, 12 dependency fixtures, 3 privacy manifests, 12 privacy fixtures, 9
required-reason source records, 10 SBOM fixtures, 16 release-evidence fixtures,
1,073 listed Swift tests, both platform cross-compiles including the macOS
SwiftUI target, and all three construction probes. Only the expected read-only
user SwiftPM cache warnings appeared.

## Deliberate limits

This is bundle-independent application orchestration. It does not authenticate
XPC, construct final login services, execute a real lifecycle transition, save
an export file, or navigate a permanent target. The injected lifecycle adapter
must compose the existing remote-safety and login-role convergence authorities;
the status and diagnostics adapters require final signed peer authentication.
