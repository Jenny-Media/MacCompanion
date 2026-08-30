# Revocation while Control prepares — 2026-08-28

## Scope

The [pre-physical goal](../pre-physical-execution-plan.md) remains active.
This extends the [48-case signed revocation checkpoint](2026-08-28-signed-revocation-agent-xpc.md)
with a second genuinely paired disposable client and revocation during paused
Desktop preparation. The original revoked client is not revived or rewritten.
The final source passes **three consecutive 49/49 signed runs, 1,760 repository
tests, Release isolation and independent cleanup verification**.

The test uses real pairing, pinned TLS authentication, signed local Control
grant and revocation, production binding/runtime/renewal owners and signed XPC.
It pauses only the test Desktop preparer, observes primary closure before
releasing the descriptor, requires **zero capture starts**, and verifies a
durable revocation receipt, exact replay and usable signed local status.
SQLite assertions require two separate revoked devices, no grants and exactly
two completed receipts/security events. Cleanup removes both private identities.

This proves revocation-driven termination wins over a pending install. It does
not claim a durable-row mutation raced past the primary fence, or that actual
screen capture/input was exercised: those platform effects remain substitutes.

## Reproduced failures

1. `/private/tmp/maccompanion-agent-xpc-evidence._yv4gjy_/report.json` passed
   the earlier 48 cases, then failed the new race. Its
   `130-revocation-race.log` records primary closure before descriptor release,
   followed by `revocation-race-install-count:1`. Cleanup was verified.
   The primary-close path waited for serialized surface cleanup before reaching
   runtime termination, and both runtime wrappers queued termination behind
   the pending install. Capture could therefore start briefly after closure.
2. `/private/tmp/maccompanion-pending-scheduler-before.log` deterministically
   fails a new test: an active-lease lookup returning after termination still
   completed install successfully and started the renewal timer. This is a
   second await boundary, not the same Desktop-preparation failure.

## Repair and focused coverage

- Primary closure and explicit Stop deliver exact runtime termination before
  potentially blocking surface cleanup. The existing remote-End test now
  asserts that runtime termination has occurred when surface cleanup begins.
- The binding retains a token for the pending session/connection and forwards
  its termination fence outside the install serialization tail. Exact menu
  invalidation and owner shutdown do the same, while retaining their cleanup
  barriers. Stale session/connection/generation requests cannot fence another
  install.
- The concrete runtime checks its retained token after awaited admission and
  preparation, before first-lease send, and after an install receipt returns.
  A cancelled preparation sends no install; an already-sent install receives
  the existing four-effect revocation rather than publishing active authority.
- The renewal wrapper retains the same attempt boundary across both underlying
  install and active-lease lookup. A lookup returning after exact termination
  cannot start renewal, including in the internal Debug test entry.
- Normative preparation/local IPC rules and the indexed lease-transport fixture
  were updated before the corresponding behavior changes. No cryptographic
  transcript, proof or operation-signature semantics changed.

`/private/tmp/maccompanion-pending-install-final-focused.log` passes 20 focused
tests, including four preparation/late-receipt cases (direct and wrapped), two
menu-loss/shutdown cases, stale-connection/generation exclusion, and the new
late-lease-lookup regression. Existing runtime/renewal regressions pass too.
The initial repaired signed run is
`/private/tmp/maccompanion-agent-xpc-evidence.vv8yvh2x/report.json`: 49/49 with
cleanup, before the supplementary scheduler repair and final repetitions.

## Final verification

- Three consecutive final signed runs pass **49/49**, with independently
  verified cleanup:
  `/private/tmp/maccompanion-agent-xpc-evidence.8f037gm4/report.json`,
  `/private/tmp/maccompanion-agent-xpc-evidence.dlnh9f8s/report.json`, and
  `/private/tmp/maccompanion-agent-xpc-evidence.ablldc3g/report.json`.
  Durations: 39.365, 46.169 and 40.919 seconds; not long-duration soak evidence.
  Command: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify_agent_xpc.py`.
- Their source fingerprint, independently recomputed after the runs, is
  `97d97b57adc6cc508b1bf582b6126fc9ab62d9259f273f3532ede4a8bfbfd665`.
  Exact case sets, missing UUID jobs, removed state/helpers/plists and absence
  of matching helper processes were independently verified.
- Release `CompanionAgentApplicationPlatform` build passes:
  `/private/tmp/maccompanion-pending-control-final-release.log`. Defined-symbol
  inspection of the previous seven transport/startup/network objects plus
  `CompanionAgent/AgentInteractiveLeaseRenewalOwnerV1` finds **401 Debug test
  symbols and zero Release test symbols**, including `startForInstalledTestRuntime`.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/validate.sh`
  passes **1,760 Swift tests across 42 runners**, all 77 indexed JSON fixtures,
  both experiment isolation guards, repository/policy checks and platform
  builds. Log: `/private/tmp/maccompanion-pending-control-final-validation.log`.
  The explicit-Stop ordering assertion and receiver helper regression are
  included. `git diff --check` also passes.

### Test-infrastructure failure found during validation

`/private/tmp/maccompanion-pending-install-final-validation.log` failed the
existing receiver cross-family FIFO test. Its surface substitute published a
retained-event marker before registering its continuation; the test could see
that marker and resume too early, losing the wakeup indefinitely. This was not
evidence of a production FIFO or timeout failure.

A deterministic resume-before-registration regression reproduces it in
`/private/tmp/maccompanion-receiver-resume-before.log`. The helper now retains
an early resume under its lock. The regression and all six production-receiver
tests pass in `/private/tmp/maccompanion-receiver-resume-after.log`. No production
timeout, assertion, test set or application code was relaxed for this repair.

## Remaining work and limits

Pending durable-intent crash/recovery boundaries, broader persistent-storage
faults and direct durable-admission revalidation coverage remain open. Earlier
launch/handshake stalls are not resolved by successful repetitions. Signed
administration UI binding, other administrative commands, bounded Act, combined
Simulator media/input, UX/compatibility/performance/actual seven-day soak,
release preparation and consolidated physical acceptance remain goal work.

The active console/display, software key custody, approval gesture and capture/
input/indicator effects are explicitly substituted. No screen pixels, real
input, installed app/Agent, production Keychain/TCC, Simulator or iPhone was
used. These checks neither certify the stable toolchain nor authorize release.
