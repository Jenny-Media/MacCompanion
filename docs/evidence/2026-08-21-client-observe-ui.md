# First-party Client Observe UI Evidence

Date: 2026-08-21

Environment: bundle-independent Swift projection tests, an iOS package
cross-compile, and an unsigned disposable iPhone 17 Pro Max Simulator harness
on iOS 27.0 with Xcode 27 beta. This is presentation, cross-compile, and
accessibility evidence. It is not a permanent target, live network, physical
device, stable-toolchain, signed-product, or release claim.

## Boundary

`ClientObserveWorkspaceProjectionV0` accepts only a status value already
validated by the authenticated Observe owner, explicit connection
reachability, a client monotonic time, at most one bounded self-audit page, and
an optional closed remote issue. It owns no socket, identity, grant, signer,
capture, input, or Control authority.

The status projection keeps five distinct user-facing states: connected but
waiting for the first validated status, live, stale at the exclusive freshness
deadline, unreachable with retained last-known facts, and unavailable with no
validated facts. Retained status can never be presented as live after
disconnect. The screen exposes the original observation time, host session
state, OS/build, CPU, memory, storage, and power facts from the validated closed
snapshot. It does not display host UUIDs, status generations, provider text, or
network-route inference.

Remote issues are reduced to a stable protocol code and closed retry guidance;
safe arguments and arbitrary remote text are not rendered. Activity reuses the
privacy-limited audit projection, holds only the latest bounded page, and makes
retention/compaction and dropped-event gaps visible.

## iOS surface

`ClientObserveViewV0` presents Mac status and health, refresh, scoped activity,
and explicit gap guidance in a first-party package view. The screen states that
Observe neither starts nor authorizes Remote Control. Its only callbacks ask
the application owner to refresh status, load activity, or request an older
page; the view cannot send a command itself.

The disposable workspace now exposes **Mac Status** beside Host Summary and
Approved Actions. Its typed synthetic fixture renders a live status and one
incomplete activity page while owning no socket or credentials. The real
Simulator accessibility flow reaches the status screen, confirms Live status,
Mac Health, the incomplete-history warning, Refresh Status, and View Activity,
opens the Activity screen, observes the scoped event, and confirms no Open
Remote Control action exists in the Observe flow.

## Verification

Five focused projection tests cover waiting versus unavailable, the exclusive
live/stale deadline, disconnected last-known truth, locked-session copy, closed
retry guidance, and preservation of one bounded audit page with explicit gap
evidence. `CompanionClientUI` cross-compiles for iOS 17 Simulator. The complete
four-test disposable UI target passes on iPhone 17 Pro Max Simulator with zero
failures.

The subsequent hardened unsigned repository gate passes with 60 indexed JSON
fixtures, 719 current repository files plus 34 historical blob paths and 14
repository-material fixtures, four package manifests and 12 dependency-policy
fixtures, three privacy manifests with 12 fixtures and six required-reason API
source records, 10 source-SBOM fixtures, 16 release-evidence fixtures, and 992
Swift tests, including 27 `CompanionClientUI` tests. All macOS/iOS package
cross-compiles and all three construction probes pass. Only the expected
read-only user SwiftPM cache warnings appear.

## Remaining gates

- Bind the real Observe event stream and connection lifecycle to this value
  projection in the configured-route application product and future permanent
  target.
- Exercise refresh, audit continuation, reconnect, Dynamic Type, VoiceOver,
  locked-session, and failure guidance on signed physical devices.
- Re-run on stable Xcode 26.6 and preserve signed release evidence separately.
