# Production Agent renewal scheduler in the Simulator journey

## Scope

The authenticated loopback journey now runs
`AgentInteractiveLeaseRenewalOwnerV1` over the disposable host's installed
`InteractiveMenuRuntimeOwnerV0`. The scheduler reads the current lease,
uses the production two-second renewal lead, validates the returned previous
and replacement leases across surface transitions, and never retries an
ambiguous renewal.

The internal `startForInstalledTestRuntime` entry is Debug-only and reached
through `@testable import`. Shipping installation and the test entry share the
same installed-lease validation and loop. It does not install a lease, create
a bootstrap, alter a grant, or authenticate a socket. The adapter's install
method rejects calls. Release builds contain no test entry.

The adapter serializes renewal with focus/surface mutations and completes
runtime retirement before returning a renewal error. Scheduler-initiated
cleanup cannot wait back on an external close that is joining the scheduler.
The older live/integration profiles retain their accelerated lab scheduler.

## Reproduction

```sh
MACCOMPANION_LAB_SUITE=journey-renewal \
MACCOMPANION_LAB_SOURCE=real-mac-window \
bash scripts/verify_simulator_features.sh
```

Use an already booted Simulator. The full profile includes this regression
and requires sixteen completed tests. Generated mode is available without
capture/input permissions; real-window mode checks existing permission and
never requests it or falls back silently.

The test pairs, verifies Observe, grants Control explicitly, focuses the owned
window, and crosses two actual renewal deadlines with visible-video checks.
With the iOS keyboard open, it then loses a renewal receipt after runtime
adoption, and separately delays a renewal beyond lease expiry. Each fault must
retire capture/runtime, empty media queues, dismiss keyboard/video, perform no
renewal retry, and recover verified Observe. Only a fresh explicit request may
restore Control. The final Stop must leave Observe usable.

The first run found a test expectation error: after waiting across two renewal
deadlines, the short-lived focused-text offer has expired, so Keyboard properly
selects the direct native keyboard. The test now checks that fallback rather
than expecting a stale composer. No production freshness check was weakened.

## Production defect exposed by fault injection

A lost renewal receipt stopped the host and closed the media socket. The
client activation correctly closed input and blanked its renderer, but had
no terminal notification to the role/workspace owner. In addition, the
application-state reducer rejected failure progress once Control was active.
The workspace therefore retained its live screen and keyboard after video
ended. This was not a pairing or primary-authentication failure.

Activation now reports failure after local retirement. The role owner accepts
only its current activation/primary binding, retires its role pair, and
publishes terminal progress. The application state accepts that progress from
active Control while leaving Observe connected. Explicit close remains silent,
and retired callbacks cannot affect a replacement. The existing Stop Failed
Session action completes the authenticated old-session exchange before another
explicit request. The test host acknowledges an exact already-retired session
without restarting capture or weakening any production authority.

Regressions cover media EOF after activation, notification only after input and
renderer shutdown, exactly-once notification, silent explicit close, and
wrong-primary/session failure rejection. The Simulator checks actual keyboard
and live-view removal rather than relying on decoder or host counters alone.

## Verification

- Focused scheduler tests: seven passed, including the installed-runtime entry,
  invalid bindings, transition handling, and no retry after ambiguity.
- Final repository validation: 1,740 Swift tests passed (1,724 main package, eight
  live-lab safety, eight platform probes), plus policy/isolation checks and
  platform compilation. Log: `/private/tmp/maccompanion-agent-renewal-validation-final.log`.
- Client networking regressions: fifty passed, including active media EOF and
  current-primary/session failure publication.
- Real-window renewal-failure/recovery test: 1/1 passed in 104.609 seconds
  (112.316 seconds result-bundle duration), run
  `/private/tmp/maccompanion-feature-tests.HMElgn`. All five subsequent pairing
  regressions passed, runner exit 0, and `report.json` passed.
- Production Agent Release compilation passed; its object contains the shared
  installed-runtime implementation and excludes the Debug-only entry.
- Shipping iOS Release compilation passed for both Simulator architectures,
  unsigned and uninstalled. Log: `/private/tmp/maccompanion-renewal-ios-release.log`.
- Full real-window Simulator suite: **16/16 passed**, zero failures or skips,
  1,005.164 seconds XCTest execution (1,015.519 seconds result-bundle duration),
  run `/private/tmp/maccompanion-feature-tests.HGV4Pw`. This includes a second
  passing renewal-fault scenario, the complete authenticated pairing/restart
  journey, repeated Observe reconnects, keyboard/zoom, UIKit lifecycle/network
  recovery, three-minute video soak, and five keyboard-open Stop/drop cycles.
  All five subsequent pairing regressions passed. Runner exit and final
  `report.json` both passed.
- Cleanup was verified: no disposable host process, host fixture/identity/store,
  current Simulator fixture or journey credentials, or per-Simulator lock
  remained. Logs, build products, and synthetic-UI xcresults remain local.
- Isolation and report validation passed (21 report positive/negative cases).

The Xcode beta auxiliary `simctl` diagnostic-collection warning remains
nonfatal; actual tests and report parsing completed. These are local beta
results, not release certification.

## Limits

This closes the lab-owned renewal-scheduling gap only. Lease issuance,
durable admission rereads, status-sequence persistence, focus recommendations,
outer Agent/bootstrap composition, and local XPC remain separate integration
work. Software custody and simulated local consent are not Keychain, Secure
Enclave, Face ID, or signed approval-UI evidence. LAN/Bonjour, installed Agent
lifecycle, final signing/TCC attribution, arbitrary-app input, and physical
devices remain unproven here. No installed product, production pairing state,
physical iPhone, permission, or account setting is changed. Local Xcode 27 beta
checks do not replace the stable release-toolchain gate.
