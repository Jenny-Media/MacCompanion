# Real pairing through the isolated production Agent — 2026-08-28

## Result and scope

The [pre-physical goal](../pre-physical-execution-plan.md) remains active.
The signed integration matrix now has **40 required cases**, extending the
[enabled-runtime checkpoint](2026-08-28-enabled-presentation-xpc.md) with real
client pairing, durable reconnect/Observe, Agent restart, and menu-loss recovery.
This is not completion of the overall goal or of the broader administration
and Interactive work.

The test runs the actual `NetworkClientPairingApplicationCompositionV0` and
configured-route client product against the signed Agent's production enabled
runtime, shared loopback listener, pairing/review/decision, authentication,
primary-session, required-audit SQLite and status owners. It proves:

- QR obtained from the authenticated menu-to-Agent XPC API, real TLS pinning
  and transcript verification, matching client/Mac authentication strings and
  both client-key fingerprints.
- Approval of the exact Agent-issued review through signed XPC, exact decision
  replay, and rejection of an altered decision using the same command ID.
- Durable monitor-only client pairing and a matching paired-device count on
  the Agent, without granting Act or Control.
- Fresh-process client reconnect and authenticated Observe responses. Two
  successive responses advance the same generation; a read-only SQLite query
  verifies the durable sequence advances by at least two.
- Graceful and forced Agent restart with unchanged persisted host identity,
  successful saved-client authentication, and continuing durable Observe
  sequence advancement. No automatic re-pairing or identity replacement.
- Loss of a signed menu process with an outstanding QR, then successful fresh
  QR creation/dismissal from a replacement authenticated menu.

## Product defect found and fixed

The initial menu-loss test failed with a handled `commandFailed`:
`/private/tmp/maccompanion-agent-xpc-evidence.6cuk1dla/report.json`.
The Agent cancelled pending approval reviews on menu loss but retained the
separate QR presentation. A replacement menu could not create another QR
until the orphan expired.

The network product now also retires the old QR presentation on exact menu
loss. The session handler fences pending creation before asynchronous cleanup,
tombstones an uncommitted session, rejects replay of the old create command,
and permits a fresh presentation. Late creation is compensated rather than
returning a stale secret. Cleanup/clock failures disable new creation; they do
not manufacture success. A durable approval commit already in progress is
left to converge, and the listener/Observe owners are not stopped.

The same generation fence covers nonterminal listener loss during creation.
Four new Swift tests cover visible QR retirement/fresh creation, suspended
creation under menu and network loss, cancellation failure, and clock failure.
The production aggregate test now checks fresh creation after menu loss as
well as terminal teardown. The normative local-IPC lifecycle rule and its
authoritative indexed fixture were updated before implementation; no wire
field, signing input, or cryptographic algorithm changed.

## Verification

- Full `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/validate.sh`:
  **passed, 1,748 Swift tests across 42 runners**, plus fixture/policy/isolation
  validators and platform builds.
  Log: `/private/tmp/maccompanion-real-pair-validation-final.log`.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --package-path Packages/MacCompanionKit -c release --target CompanionAgentApplicationPlatform`:
  passed. Log: `/private/tmp/maccompanion-real-pair-release.log`.
- Defined-symbol inspection across the seven affected transport/startup/
  product/network objects: **387 matching Debug symbols, zero Release symbols**.
  The experiment remains outside the permanent product graph.
- Three consecutive final runs of
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify_agent_xpc.py`:
  **40/40 passed with cleanup verified** in each report:
  `/private/tmp/maccompanion-agent-xpc-evidence.l_pbz5x_/report.json`,
  `/private/tmp/maccompanion-agent-xpc-evidence.lrrho047/report.json`, and
  `/private/tmp/maccompanion-agent-xpc-evidence.v8iss1mx/report.json`.
  Final run duration: 16.787 seconds.
- Final matrix source SHA-256:
  `8c9c13733d02d2608594b668d01ca195d6ef891bc74ddb205d790df898cb3789`.
- `git diff --check`, both experiment isolation validators, and all 77 indexed
  JSON fixtures passed. Final UUID job, test helpers, and private state were
  independently confirmed absent after the last run.

An initial Observe assertion incorrectly treated request-send completion as
response publication, then assumed sequence initialization at one rather than
zero. Those test assumptions were corrected; real asynchronous responses and
the SQLite sequence are now both checked. An earlier full-suite run failed
because its extended terminal-QR test still referenced an obsolete fixed ID;
the final run checks the actual new session ID and passes. Failed reports/logs
remain private evidence rather than being relabeled successful tests.

## Limits and next work

Software host/client key custody and the local human approval gesture are
explicit substitutes. The CLI uses platform-independent production client
owners, not UIKit or Face ID. The Agent still uses empty providers, unavailable
Interactive initial platform, inert process startup, conservative console
context, and explicit loopback/private-endpoint readiness in place of Bonjour.
The original generated-review transport check remains separate from the real
pairing flow. No production Keychain, privacy settings, installed product,
Simulator or physical device was operated in this checkpoint.

Required work remains: signed Act/Control grant administration, Stop/revoke,
history/diagnostics/recovery, full Interactive lease/admission/execution, more
pending-review/commit/supersession fault boundaries, combined Simulator
Observe/Act/Control, performance/soak and final release/handoff checks. The
earlier launch/handshake stalls remain open reliability findings; these
passing repetitions do not establish their cause or close them. The current
beta-toolchain results do not certify the stable release lane or hardware.
