# Primary keepalive and congestion recovery — 2026-08-30

## Scope

This source checkpoint applies the transport-lifetime lessons from the Reminal
code audit without copying AGPL-licensed source. The source verification is
supplemented below by a signed Mac and physical-iPad deployment; it is not a
release-acceptance claim.

## Implemented

- Closed `keepalive.ping` and `keepalive.pong` wire bodies, canonical fixtures,
  host revalidation/replay admission, correlated pong handling, one-ping client
  ownership, and a distinct 15-second pong deadline.
- Authenticated traffic resets the idle timer. An unexpected, duplicate,
  malformed, wrongly correlated, or missing pong closes only the exact primary
  connection and enters the existing reconnect path.
- Post-authentication Network.framework `waiting` is treated as a bounded
  recoverable transport state rather than immediate connection death. New
  primary commands are denied while the path is unavailable, but roles already
  bound to that exact authenticated primary are preserved during the 15-second
  recovery grace. A return to `ready` resumes the same ownership without
  replaying a command, credential, input event, or media record. Only terminal
  primary failure retires the bound roles.
- The encoded media handoff no longer tears down Control merely because its
  bounded queue is momentarily full. One complete record waits for capacity,
  preserving H.264 order while upstream encoder backpressure retains the
  existing newest-source-frame latency policy. Purge rejects the waiter and
  cannot revive retired runtime authority.

## Deliberate safety boundary

Transport recovery does not create or restart a Control session. It may preserve
an already-authenticated Control role across a short interruption of the same
primary connection, but terminal primary failure still retires Control and a
new explicit request is required. Reusing an approval, role credential, input
event, or media record after terminal failure remains prohibited.

## Verification

- `python3 scripts/validate_fixtures.py`: 80 indexed JSON fixtures pass.
- Focused combined suites pass:
  - `CompanionWireTests`: 55 tests.
  - `CompanionInteractiveRuntimeTests`: 32 tests.
  - `CompanionClientNetworkPlatformTests`: 54 tests.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/validate.sh`
  completes successfully, including the full package graph, repository policy
  validators, experiment builds/tests, C syntax probes, and final diff check.

## Still required

- Build/install fresh signed Mac, iPad, and iPhone candidates from this exact
  committed source and exercise idle keepalive, rapid app/display changes,
  short Wi-Fi path interruption, sustained high-motion congestion, keyboard,
  pointer, and multi-device reconnect on physical LAN.
- If seamless automatic Control restoration is desired later, specify a new
  resume protocol with fresh role credentials, a clean media fence/keyframe,
  explicit input reset, and a reviewed user-presence policy before coding it.

## Signed Mac and physical-iPad deployment

- Xcode 27 beta built fresh Debug candidates for `media.jenny.maccompanion`
  and `media.jenny.maccompanion.ios` with the Jenny Media development team.
  Both bundles passed strict signature verification; the Mac bundle also
  passed deep verification across its Agent and Sparkle graph.
- The Mac app was shut down through its ordered termination barrier, retained
  at `/private/tmp/maccompanion-quiet-mac-backup.bCyymY`, replaced at its existing
  per-user installation path, and relaunched. The installed app and Agent
  Debug dylibs matched the verified build byte-for-byte, and the registered
  replacement Agent was running.
- The iPad app was installed over its existing bundle without uninstalling,
  clearing pairing, changing grants, or changing privacy permissions. The
  iPhone was not built, installed, launched, or otherwise used in this run.
- The first activation after installation exposed a deployment hazard: an
  already-running iPad process continued executing the preceding binary.
  Merely asking Launch Services to launch the bundle did not replace that
  process, and its old primary expired at the host session deadline. The
  physical deployment procedure must therefore terminate the exact existing
  app process after installation before launching the candidate under test.
- After an explicit terminate-and-relaunch of only the iPad app, its console
  showed three consecutive authenticated `keepalive.ping` / `keepalive.pong`
  cycles at the 15-second idle cadence. The process remained alive after the
  bounded console detached, while the Agent retained one active primary. A
  separately expiring parallel/older primary reduced the Agent's active count
  from two to one without terminating the verified iPad connection.
- Debug-only client timer diagnostics now expose keepalive ping, pong, and
  configured-route heartbeat milestones so a future physical
  failure can be attributed without guessing from a host deadline alone.
- A later physical-iPad trace kept the primary healthy through repeated idle
  ping/pong cycles, then captured a disconnect whose client-side termination
  reason was `localCancel` at the exact `didEnterBackground` transition. The
  connection returned immediately after foreground activation, isolating this
  failure from Wi-Fi loss, Agent failure, keepalive expiry, and host rejection.
- iOS now applies one UUID-fenced 10-second grace to an actual background
  transition. Returning through either foreground lifecycle boundary cancels
  that exact pending deadline, while remaining backgrounded still publishes
  foreground loss inside the protocol's 15-second fail-closed bound. Focused
  tests cover current-token consumption and stale-deadline fencing.
- The real-window Simulator live suite passed after this change, including its
  pairing regressions, and a permanent iOS Simulator Xcode build completed
  successfully. The report is retained at
  `/private/tmp/maccompanion-feature-tests.Q4hK7n/report.json`.
- The final milestone-only diagnostics source passed the complete repository
  validator again with exit status 0. The retained log is
  `/private/tmp/maccompanion-mac-ipad-final-validation-2.log`.

This verifies signed installation, existing-pairing reconnection, and idle
keepalive on Mac plus iPad. It does not yet verify a new Face ID Control grant,
high-motion media backpressure, display/app switching, path interruption, or
interactive input on this exact candidate.

The background-grace source also passes the complete repository validator. A
fresh signed iPad candidate from that exact source was strictly verified for
bundle `media.jenny.maccompanion.ios` and team `5736QK4NZX`, then installed over
the existing app without clearing pairing or grants. It retained one primary
through a three-minute idle trace with successful ping/pong cycles throughout.
An automated immediate Settings-and-back transition retained the same process
and primary, published no `localCancel`, and continued keepalive afterward. A
separate harness run returned at the 10-second boundary and closed normally,
confirming the durable-background deadline rather than silently weakening it.

## Exact role-lifetime root cause and source repair

The later source audit attributed a major class of the apparently random
active-Control disconnects. The primary frame pump already treated
`NWConnection.waiting` as recoverable, but the Interactive-role product binding
independently retired media and input roles as soon as it received the
transient interruption event. When the same authenticated primary recovered,
its Control roles were already gone. This made ordinary short path changes and
Wi-Fi jitter look like terminal session failures.

The binding now preserves roles on the transient event and retires them only on
the primary's terminal event. Focused regressions prove transient preservation
and terminal retirement. The Simulator integration journey proves short app
switches retain the same primary and Control role, while sustained background
still retires fail closed. The authenticated journey additionally proves
pairing, explicit Control, visible media, keyboard input, repeated quick app
switches, abrupt drop/reconnect, host restart, offline/online recovery, and
revocation.

After the local Xcode account was refreshed, Xcode built fresh signed Mac and
iPad candidates from the exact source containing this role-lifetime repair plus
the request-local approval, stale-approval, and fresh-workspace repairs. Both
candidates passed strict signature verification. The Mac app completed its
ordered termination barrier, its previous bundle was moved to the recoverable
backup at
`/private/tmp/maccompanion-pre-reliability.rbQpMU/Mac Companion.app`, and the
installed main-app and Agent Debug dylibs matched the verified candidate
byte-for-byte after relaunch. The registered Agent and containing app were both
running from the intended per-user installation.

The already-running iPad process was terminated before installation so it
could not retain the preceding binary. The signed app was installed over the
existing bundle without uninstalling or clearing pairing, grants, or privacy
permissions, and a new process launched from the replacement application
container. The iPhone was not built, installed, launched, or otherwise used.
This establishes exact-candidate installation, not the remaining human-visible
physical connection and interaction soak.

## Local Smart Zoom terminal-failure root cause and Simulator gate

The next physical-iPad failure left both the iPad application and Mac Agent
processes alive, while the Agent observed its input-role peer close after a few
seconds. A new bounded, content-free iOS diagnostic trail identified the
upstream cause exactly: automatic Smart Zoom emitted
`ClientVisualZoomTransformErrorV0`, the UI coordinator treated that local
presentation error as terminal, and activation teardown then closed both input
and media roles. The apparent network disconnect was therefore downstream of a
local viewport calculation, not evidence of primary transport loss.

Normalized focus rectangles are now mapped and edge-clamped inside the current
aspect-fit content before Smart Zoom calculates its transform. Automatic visual
zoom owns its local geometry failures: it returns to fit and waits for a later
verified focus refresh without changing the authenticated Control session,
surface authority, input fence, or role lifetime. Transient UIKit mapper
geometry likewise retains the session while withholding input until a later
layout pass can rebuild the mapper.

Simulator-first verification then passed all of the following before another
physical candidate was built:

- nine focused visual-transform tests, including every content edge and 900
  repeated normalized focus calculations across phone portrait, phone
  landscape, and iPad viewports;
- three consecutive 121–122 second production Control UI scenarios covering
  H.264 encode/decode, local Smart Zoom, focus churn, focus-pause races,
  pointer, double-click, pinch, keyboard, surface changes, drop, and reconnect;
- a separate three-minute continuously rendered idle-video soak; and
- the repeated Stop/drop/reconnect suite plus the pairing reliability
  regressions after each Simulator lane.

The retained passing reports are:

- `/private/tmp/maccompanion-feature-tests.7Z1JGz/report.json` (three repeated
  interaction runs);
- `/private/tmp/maccompanion-feature-tests.me3PSU/report.json` (idle soak); and
- `/private/tmp/maccompanion-feature-tests.edAahR/report.json` (reconnect).

The complete repository validator passed afterward; its retained log is
`/private/tmp/maccompanion-smart-zoom-stability-validation-2.log`. A fresh
signed iPad candidate was then built, strictly signature-verified, and installed
over the existing app without clearing pairing or app data. Remote launch was
correctly refused while the iPad was locked, so physical behavior on this exact
candidate remains a separate human-visible check rather than an inferred pass.

## Reconciled candidate and consolidated Simulator gate

Before freezing the next physical candidate, the pending connection, media,
background-grace, and Smart Zoom changes were reconciled as one source slice.
The Simulator journeys were updated to assert the intended product contract:
Smart Zoom changes only local viewport geometry, a quick app switch remains
inside the 10-second foreground grace, and durable backgrounding still retires
the connection inside the protocol's 15-second fail-closed bound.

The audit also found that the approved-action detail view retained its mutable
parameter draft and explicit-effect review as plain `Binding` values rather
than SwiftUI dynamic bindings. The detail view now owns those bindings through
`@Binding`. Its boolean editor maintains immediate local state and presents a
fixed trailing switch instead of a size-class-dependent full-row toggle. The
same real tap now updates and invokes `setAudioMuted` on both iPhone and iPad
Simulators.

Verification from this exact uncommitted source checkpoint:

- focused protocol, client, network-platform, host-session, interactive-host,
  interactive-runtime, and interactive-client suites passed;
- the focused approved-action/client-UI suites passed 49 of 49 tests;
- the complete iPad Simulator feature lab passed 16 of 16 serialized journeys
  in 986.027 seconds, followed by the pairing reliability regressions;
- the retained source-bound report is
  `/private/tmp/maccompanion-feature-tests.nRPmIN/report.json`; and
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash
  scripts/validate.sh` completed with exit status 0 after all source changes.

This is automated pre-install evidence only. It does not claim that the next
signed Mac, iPad, or iPhone artifacts have been built or installed, nor that
the physical checkpoint matrix or fresh post-install soak has passed.

## Frozen `b869941` signed-install checkpoint

The reconciled source was committed locally as `b869941` with subject
`Stabilize persistent remote control sessions`. Fresh Debug Mac and universal
iOS device candidates were built from that clean commit with Xcode 27 beta and
the configured Jenny Media development team. The checked-in signed-build
checkpoint passed its pairing tests and strict Mac/iOS signature verification.
The retained derived-data root is
`/private/tmp/maccompanion-b869941-signed`.

The Mac containing app completed its ordered AppKit termination barrier. Its
previous bundle remains recoverable at
`/private/tmp/maccompanion-b869941-backup.UJIaha/Mac Companion.app`. The signed
candidate was copied to the existing per-user Applications location and passed
strict deep verification there. SHA-256 comparison proved that both the main
executable and nested Agent executable match the verified build byte for byte.
The narrow `maccompanion://repair-agent-registration` command replaced the
still-running previous Agent process; the new Agent is executing from the
replacement bundle, reports an active launchd job, and restored its private
TLS listener on port 59653.

The same signed iOS bundle was installed over the existing physical iPad and
iPhone applications without uninstalling them or clearing pairing, grants, or
application data. The prior iPad process was terminated before installation so
it could not retain the old executable. Both clients initially launched and
the Agent admitted two independent authenticated primaries. One primary later
closed when its client became unavailable, while the other remained active;
the clients were then traced independently rather than attributing the event to
transport code.

The physical iPad replacement authenticated and completed three consecutive
idle keepalive ping/pong cycles during a bounded 50-second console trace. The
console command ended only at its external timeout while the app remained
running. The equivalent iPhone trace could not start because SpringBoard
reported the phone locked. This is an external human checkpoint, not a source
failure and not an iPhone physical pass. The full interactive device matrix and
fresh post-install soak therefore remain open.

## Dashboard status-timeout Control teardown and repair

Physical testing of the frozen `b869941` candidate exposed a separate local-XPC
failure after the iPhone had authenticated and started Control. At
22:00:02.695 the menu app began the first Control lease renewal. At
22:00:03.371 it canceled its own authenticated XPC generation; the Agent then
reported `endpointClosed` and `safetyRecoveryRequired`, and the later
`bindingMismatch` was a downstream consequence of that teardown. Media and
input roles stopped even though the primary client connection itself had not
failed.

The bounded unified log and source audit identified the initiating event: the
visible Mac dashboard performs a diagnostic Agent-status read every second on
the same authenticated XPC generation that carries pairing presentation and
Control administration. Under live-media load, one read exceeded its exact
three-second client deadline. Both sides treated that non-authorizing status
delay as a terminal transport failure, so a dashboard refresh revoked unrelated
Control authority.

The transport now converts a server-side slow status source into the existing
exact `sourceUnavailable` reply. The client likewise publishes
`agentStatusUnavailable` on its current generation, permitting the dashboard's
existing sequential retry without canceling authentication or Control. A late
reply for the retired read operation is ignored and cannot invalidate either a
new same-generation retry or a replacement generation. Malformed current
replies, authentication failures, and an actual reply-send failure remain
terminal.

Verification of this source repair includes:

- 154 focused Mac local-XPC tests, covering status recovery, generation
  fencing, late completion, serialized lease renewal, and role transport;
- an explicit regression proving a timed-out status operation can retire,
  admit a same-generation recovery, reject the late old completion, and leave
  the recovery current; and
- the complete repository `scripts/validate.sh` gate with Xcode 27 beta,
  which completed with exit status 0.

This is source evidence only until fresh signed Mac, iPad, and iPhone artifacts
from the repair commit are installed and Control remains active across multiple
lease renewals under live video. The failed `b869941` interactive attempt is not
a soak pass.

## Frozen `f301469` signed physical checkpoint

The status-timeout repair and its evidence were committed locally as `f301469`
with subject `Preserve control across status timeouts`. Fresh Debug Mac and
universal iOS-device candidates were built from that clean commit with Xcode 27
beta and the configured Jenny Media development team. The pairing reliability
checkpoint and strict Mac/iOS signature verification both passed. The retained
derived-data root is `/private/tmp/maccompanion-f301469-signed`.

The installed Mac app completed its normal AppKit termination barrier before
replacement. Its previous bundle remains recoverable at
`/private/tmp/maccompanion-f301469-backup.2ccRbn/Mac Companion.app`. The new
bundle passed strict deep verification at its per-user installation path. Both
its main executable and nested Agent executable matched the verified build
byte-for-byte. The narrow Agent-registration repair replaced the preceding
Agent, and launchd reported the new Agent running.

The same signed iOS bundle was installed over the existing iPad and iPhone apps
without uninstalling either app or clearing pairing, grants, permissions, or
application data. The prior iPad process was terminated first so it could not
retain the preceding binary. Both replacement apps launched successfully and
the Agent admitted two authenticated primaries.

One physical client started live Control at 22:22:42 EDT. Video capture and
focus polling remained active while the Agent completed 12 consecutive lease
renewals, from counter 1 at 22:22:50 through counter 12 at 22:24:18. The trace
contained no `bindingMismatch`, `endpointClosed`, `safetyRecoveryRequired`,
capture stop, primary cleanup, or interactive-role teardown. This crosses the
exact prior failure boundary, which canceled authenticated XPC during the first
renewal after three seconds.

This is a passing exact-candidate physical rollover checkpoint, not yet a full
multi-device interaction matrix or long-duration soak. The fresh soak may start
from `f301469`; evidence from `b869941` must not be counted toward it.

The first fresh Simulator soak run then passed for 199.421 seconds, followed by
the pairing reliability regressions and verified runner cleanup. Its source
fingerprint is
`fee429c654088c609592416a87723e63f44c7103afeacddf9e9a6d2a28bf5b48`;
the hash-bound report is retained at
`docs/evidence/soak-runs/2026-08-31T02-29-33Z-fee429c65408.json`. The ledger
records one of seven required distinct UTC dates and zero elapsed campaign-span
seconds. The campaign is therefore active but incomplete; the old scheduler
remains paused and no historical run was credited to this source.
