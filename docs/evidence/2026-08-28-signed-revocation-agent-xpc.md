# Signed revocation and replacement-menu recovery — 2026-08-28

## Scope and result

The [pre-physical goal](../pre-physical-execution-plan.md) remains active.
This extends the [43-case Control checkpoint](2026-08-28-signed-control-agent-xpc.md)
to 48 signed, disposable multi-process cases. **Three consecutive final runs
pass all 48 with independently verified cleanup**, alongside the full regression
suite and Release isolation checks. This is not a physical-device or complete
Simulator acceptance.

The new production route carries exact device-revocation review and confirmation
over the existing authenticated `command.device-administration` XPC family.
It uses the existing `administerDevices` authorization, closed canonical codecs,
single-flight gate, exact request/reply correlation and command deadlines.
Each menu generation owns its unconfirmed review handler. Loss withdraws that
review; exact durable confirmation replay still works after reconnect/restart.
No cryptographic transcript or operation-signature semantics changed.

The real Agent revocation handler/coordinator, primary fence, SQLite store and
runtime owners now verify:

- A replacement signed menu can request a review after active Control loses
  its previous signed menu connection.
- Abandoned-generation and replaced reviews cannot revoke; changed reuse of
  a retained review request ID fails, while its exact retry is unchanged.
- A fresh confirmed review revokes the actual test device during active
  Control. The primary closes, the menu runtime becomes idle, and test capture/
  input/frame/indicator cleanup effects run.
- Both authorization revisions advance exactly once, all device grants are
  removed, and one completed revocation receipt and security event remain.
- Exact command retry returns the same receipt; altered command reuse fails.
- Saved revoked clients complete a failed reconnect round without becoming
  connected. Signed local status still works. Graceful and forced Agent restart
  preserve the receipt, revoked state, revisions and absent grants.

## Reproduced defect and repair

The first new case consistently failed before sending the revocation request.
The replacement menu authenticated and acknowledged readiness, then its local
XPC connection was invalidated while the independent network Observe path
continued working. Failed reports with cleanup include:

- `/private/tmp/maccompanion-agent-xpc-evidence.do9u5juo/report.json`
- `/private/tmp/maccompanion-agent-xpc-evidence.mkt_i6qt/report.json`
- `/private/tmp/maccompanion-agent-xpc-evidence.sozaw2pw/report.json`

The prior router implementation called permanent `beginFinish()` when one
endpoint failed. This fenced the failed connection correctly but also poisoned
the shared Agent presentation router: every future authenticated menu failed
to bind until Agent restart. The previous 43-case matrix ended immediately
after menu loss and therefore did not test this recovery.

Endpoint failure now retires only the exact generation and retains its
asynchronous cleanup. A fresh higher authenticated generation cannot receive
facets until endpoint retirement and product-loss notification finish. Old
facets/callbacks remain fenced; explicit owner shutdown remains permanently
terminal. The callback still returns without awaiting teardown of the operation
that reported failure, preserving the earlier deadlock repair.

The normative local IPC specification and indexed presentation fixture define
this distinction. A new regression failed against the old implementation with
`.invalidated`, then passed after repair; it also checks two consecutive failed
generations, delayed cleanup and stale callbacks. Existing finish/replacement/
callback tests remain passing. Temporary diagnosis logging was removed.

Reproduction: `/private/tmp/maccompanion-router-replacement-before.log`.
Focused repaired checks: `/private/tmp/maccompanion-router-replacement-after.log`.
Initial repaired 48/48 run (before strengthening the security-event assertion):
`/private/tmp/maccompanion-agent-xpc-evidence.mgx7mbah/report.json`.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/validate.sh`:
  passed, **1,755 Swift tests across 42 runners**, all 77 indexed JSON fixtures,
  repository/policy/isolation checks and platform builds. Log:
  `/private/tmp/maccompanion-revocation-xpc-validation.log`.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --package-path Packages/MacCompanionKit -c release --target CompanionAgentApplicationPlatform`:
  passed. Log: `/private/tmp/maccompanion-revocation-xpc-release.log`.
- `xcrun nm -U` defined-symbol inspection of the same seven transport/startup/
  product/network objects as the previous checkpoint: **393 matching Debug test
  symbols, zero Release symbols**. Both source-isolation validators pass.
- Three consecutive final runs of
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify_agent_xpc.py`:
  **48/48 pass with cleanup** in each report:
  `/private/tmp/maccompanion-agent-xpc-evidence.44yjnmhm/report.json`,
  `/private/tmp/maccompanion-agent-xpc-evidence.4kprqfbq/report.json`, and
  `/private/tmp/maccompanion-agent-xpc-evidence.j7jqeryr/report.json`.
  Durations: 43.143, 39.890 and 42.151 seconds. These are repetition checks,
  not long-duration soak evidence. The loop stops on any failed run.
- Shared source SHA-256, independently recomputed after testing:
  `0bc5ae09cf2a63eb3a4ad43fbc3ce0aa462dbabaa6534da2c455e8b62431bdc4`.
- Independently confirmed exact case sets, all three UUID launchd jobs absent,
  private state/helper binaries/plists removed, and no matching helper process.
  `git diff --check` and the fixture/isolation validators also pass.

## Remaining boundaries

This tests the signed administration API and Agent business owners, not the
visible paired-device management UI. Reconnect rejection is observed as a
completed failed production reconnect round against the live Agent, not as a
specific client-visible authentication error code. Pending durable-intent crash
boundaries and revocation during paused admission remain separate required
fault cases; revoking an already active session does not prove those races.

Software test key custody and local approval gestures are substituted. The
active console/display and capture/input/indicator effects are test substitutes;
no pixels are captured/rendered and no keys or pointer events are posted.
Providers are empty, and confirmed loopback readiness substitutes for Bonjour.
No installed product, production Keychain/TCC, Simulator or physical iPhone was
operated. Tests use UUID-scoped signed helper processes and private temporary
state. Beta-toolchain success is not stable-release certification.

P1/P2/P3/P6 remain active. Remaining work includes other signed administration
and UI binding, bounded Act, durable-admission faults, surface/focus/input/media
integration, combined Simulator journeys, UX/performance/actual seven-day soak,
local release preparation and one consolidated physical handoff. Earlier
launch/handshake stalls remain open; these passing runs do not resolve them.
