# Simulator-first development gate

Effective 2026-08-28, per user direction: keep the development/debugging loop
on Simulator. Do not install, launch, interrupt, or use the physical iPhone as
the next debugging step without a fresh explicit request. A goal to keep
iterating does not override that boundary. Simulator failures stay in the
automated loop until understood; a green smoke test is not full-product proof.

## Required checks before proposing a physical checkpoint

1. `scripts/validate.sh` on the current source, including production runtime,
   Agent renewal, authentication/pairing, and teardown regressions.
2. Full Simulator UI suite, including independent Observe/Act/Control paths,
   repeated real UIKit background/return notifications, injected reachability
   and terminal-failure behavior.
3. Real-window lane: three minutes of uninterrupted video (90 seconds Desktop,
   90 seconds focused view), visible-pixel and renewed-lease checks, and zero
   host/client failures.
4. Five alternating Stop/abrupt-drop/reconnect cycles with keyboard open;
   verify the keyboard/view disappear, host capture stops, runtime authority
   becomes idle, and media queue is empty before a fresh session renders.
   Stop must be reachable through the top menu while the keyboard covers the
   bottom toolbar.
5. Three consecutive live feature runs including odd encoded geometry,
   focused-to-focused input pauses, Desktop recovery, pinch, both keyboards,
   and reconnect. Any new failure needs a targeted regression and rerun.
6. Integrated route-to-Control lane: production workspace navigation, selected
   primary publication, role binding, UIKit lifecycle, and reconnect scheduling
   must work together over the isolated transport. Exercise background/return,
   offline/online, abrupt primary loss, and cancellation during a delayed dial.
   Recovery must retire capture/input before selecting a replacement, dismiss
   stale video/keyboards, and require a fresh explicit Control request.
   Include deterministic retired-callback and canceled-construction checks so
   a former stream cannot report failures into a replacement product.
7. Authenticated journey lane: fresh real pairing over pinned TLS, rejection
   of a wrong fingerprint, durable client/host store reload, actual client and
   host process restarts, verified Observe replies, explicitly approved Control,
   real role-channel proofs, both keyboards, pinch, and Stop preserving the
   same primary. Repeat background/return, listener loss, abrupt disconnect,
   host restart during Control, and revoked-device rejection. Reconnection
   must never restore Control automatically.
8. Agent-renewal lane: the authenticated host uses the production lease
   scheduler over its own installed runtime. Cross two real renewal deadlines
   after a focus transition, then inject a lost renewal receipt and delayed
   renewal beyond expiry. Require capture/input retirement, an empty queue,
   dismissed keyboard/video, no retry, verified Observe recovery, and a fresh
   explicit Control request. This is scheduler integration, not shipping Agent
   admission, lease issuance, or authenticated XPC evidence.

`scripts/verify_simulator_features.sh` selects only a booted Simulator and
never invokes physical-device tools. `MACCOMPANION_LAB_SUITE` selects `full`
(default), `live`, `soak`, `reconnect`, `lifecycle`, `semantic`, `integration`,
`journey`, `journey-observe` (a focused six-reopen status regression), or
`journey-renewal` (production scheduler and fail-closed recovery). The
`semantic` lane isolates ordinary iOS keyboard and Stop reachability without
per-key Xcode idleness dependence. Set
`MACCOMPANION_LAB_SOURCE=real-mac-window` for the owned-window real-capture lane;
generated mode remains permission-free. Set `MACCOMPANION_LAB_ITERATIONS=3`
for repeated runs. A denied real-window preflight is a reported gap, not
permission to request TCC or move to the phone.
The runner owns a per-Simulator lock through final cleanup. Do not overlap runs
or remove a lock without checking that its owner has exited; after an abnormal
hard termination, inspect the stale lock and processes before retrying.
Do not edit a running shell runner; stop it and await cleanup before changing
the script or starting another run.
Every run writes a content-free `report.json` next to its `.xcresult`. Missing,
failed, skipped, malformed, non-Simulator, or cleanup-failed evidence cannot
produce a passing report. Test software keys and pairing databases are removed
from the owned temporary host directory and disposable Simulator container.

## Complementary isolated Agent/XPC gate

Run `python3 scripts/verify_agent_xpc.py` for the signed macOS process lane
documented in [AGENT-XPC.md](../Experiments/LiveControlLab/AGENT-XPC.md).
Its 55 required checks cover the production startup coordinator, durable
disabled-to-enabled bootstrap/restart, signed local-XPC readiness/status,
identity rejection, old-generation retirement, timeout/late reply, and
disposable Agent death/recovery. It verifies cleanup of its UUID-scoped
launchd job, processes, state, and signed helper copies. Eight primary-production
checks use real prepared primary/lifecycle/status owners and verify persisted
identity reload across graceful and abrupt process restart. The presentation
lane adds the production enabled runtime, signed review delivery, QR create/
dismiss, and a shared listener verified as loopback-only. Real client pairing,
signed code comparison/approval, exact decision replay and altered-decision
rejection, fresh-process reconnect, durable remote Observe sequence advancement,
Agent restart/crash recovery, and menu-loss QR recovery now run through that graph.

After that full matrix, run
`python3 scripts/verify_agent_startup_stress.py --iterations 25` for 100
fail-fast launch cycles. Its presentation cycles include the signed menu
handshake and generated presentation flow; it uses the same disposable-only
custody and does not replace Simulator or physical acceptance.

This is not a Simulator replacement or permission to operate installed
products. The original fault cases inject preparation/status; the primary cases
substitute software custody, empty providers, and inert platform edges. The
presentation lane substitutes loopback/private-endpoint readiness for Bonjour.
One transport case uses a generated review; the real pairing case substitutes
software client custody and human approval while preserving the production
protocol owners. Hardware custody and installed-product behavior remain gaps.
Its Debug-only address seam cannot select the
permanent Mach service and never changes peer identity requirements.

## Coverage limits that must remain visible

The live lab uses production codec, rendering, input, surface, and menu-runtime
components, but seeds pairing and approval and supplies its own loopback host
and renewal scheduler. The `integration` profile additionally uses the shared
production configured-route application factory, selected-primary candidate
and command router, role-binding owner, UIKit application owner, reconnect
controller, and complete workspace/live-view composition. Only transport
establishment, paired inventory, signer/user presence, and scheduling-only
reachability are injected. Real loopback sockets carry the command/input/media
traffic; every replacement primary receives a fresh connection ID.

These older lanes do not run shipping TLS/session authentication, Bonjour/LAN,
Keychain publication, or the outer release bootstrap/rebuild shell. Status data
is synthetic, Act execution is unsupported, and the host's renewal scheduler
is lab-owned. A test-host Stop also closes the primary, so it is not proof of
shipping Stop preserving Observe. Agent scheduler and pairing tests must run
separately. The older isolated lifecycle and live feature lanes remain useful
regressions, not substitutes for this combined test.

The newer `journey` profile closes the TLS/pairing/session-authentication gap
using production factories and authorities on real loopback connections. Client
keys are created by the client; they and the production-format paired records
survive app restart. The host's disposable SQLite store and software identity
survive an actual process replacement. Status uses the production Mac sampler
and must be accepted by the production client freshness checker. Stop must
allow a new verified Observe reply without a new authentication. The wrong-pin
test requires an actual TLS verifier rejection, not merely a connection error.

This does not certify the shipping release bootstrap, LAN/Bonjour, Keychain or
Secure Enclave custody, Face ID, local Mac consent UI, final signing/TCC, or
installed Agent lifecycle. Local consent and iOS presence are simulated;
status sequence persistence, host runtime composition, and lease issuance in
the older journey remain lab-owned. The authenticated lanes now use the production Agent renewal
scheduler through an internal Debug-only entry after the lab's real runtime
install. They do not test the Agent's final admission or XPC transport. Older
live/integration lanes retain their accelerated lab scheduler. The signed
Agent + Simulator lane separately combines signed administration, Act and
Control with the production client UI. Real-window mode still captures/posts
only to the disposable host's own window/PID, never the user's apps.

Further integration work should compose more production owners behind narrowly
injected test transports, not add test bypasses to release targets. Physical
checks are later, user-authorized evidence for LAN/Bonjour/TLS integration,
Secure Enclave/Face ID, final signing/TCC attribution, and device-specific
behavior. Never describe these as covered by the lab or ask the user to repeat
manual steps just because an automated reproduction is missing.

The historical [signed Control Agent/XPC checkpoint](evidence/2026-08-28-signed-control-agent-xpc.md)
passed 43 signed multi-process cases in three consecutive runs, with
1,750 repository tests, Release seam exclusion and verified cleanup. It adds
real Control grants, production lease issuance/install/renewal/client Stop,
role authentication, final visible-admission race rejection and menu-loss
retirement while preserving Observe. It fixes explicit-null encoding for
no-display publications and receipts. Its test capture/input/indicator effects
were substitutes, not proof of video rendering or user input. The later
[signed Agent + Simulator checkpoint](evidence/2026-08-28-signed-agent-simulator-observe-act.md)
connects those owners to rendered media, pointer, focus/zoom, both keyboards,
Stop and lifecycle recovery without using a physical phone.

The subsequent [signed revocation checkpoint](evidence/2026-08-28-signed-revocation-agent-xpc.md)
extends this to three final 48/48 runs and 1,755 repository tests. It verifies
reviewed revocation during active Control, stale-review/changed-replay rejection,
durable receipt/state across graceful/forced Agent restarts, and fresh signed
menu recovery after endpoint failure. The latter uncovered and fixed permanent
router closure; replacement generations now wait for old cleanup. These are
signed transport/Agent-owner checks, not visible Mac administration UI or
Simulator media/input proof. Release seam exclusion and cleanup pass. Continue
the combined automated journey before asking for a physical-device checkpoint.

The [pending-Control revocation checkpoint](evidence/2026-08-28-pending-control-revocation.md)
adds a signed race test: revocation closes primary before releasing a paused
Desktop descriptor, and capture must never start. The final 49-case matrix
passes three times, with 1,760 repository tests, Release isolation and independent
cleanup. Runtime and renewal owners fence late preparation/lease lookup; Stop
and primary closure deliver termination before surface cleanup. This is still
substituted capture/indicator/input evidence, not a combined Simulator pixel or
keyboard test. Bounded Act and the remaining integration work continue before
physical acceptance testing.

The [signed bounded Act checkpoint](evidence/2026-08-28-signed-act-agent-xpc.md)
adds Agent-owned published-capability review/decision over signed XPC and real
catalog/operation/native-provider routing with a test-only audio controller.
Decline/approval, read-back failure and exact operation replay after graceful/
abrupt Agent restart pass; Control stays inactive and Observe stays available.
Three final 52/52 runs, 1,765 repository tests, Release isolation and independent
cleanup pass. These are macOS CLI client-owner checks, not Simulator UI or real
audio evidence.

The [signed Act concurrency/recovery checkpoint](evidence/2026-08-28-act-concurrency-recovery.md)
extends that matrix to 55 checks. Real network testing exposed and fixed the
host reader blocking status/cancel behind provider execution. Direct host denial,
same-primary cancellation and post-effect crash recovery now pass with explicit
test-only audio/result-delivery substitutes. These remain signed macOS CLI
client-owner checks; the combined signed-Agent Simulator UI/media/input journey
and broader faults are still required. No physical iPhone was used.
