# Enabled runtime and signed menu/presentation XPC — 2026-08-28

## Scope and result

The [pre-physical goal](../pre-physical-execution-plan.md) remains active. The
isolated signed-process matrix now has **35 required cases**. This checkpoint
adds the actual production enabled-runtime coordinator, full menu/presentation
composition and shared network listener to the earlier primary/local lane.
It does not complete P1, P2, client pairing, or the overall goal.

The production graph owns startup ordering, lifecycle observation/event
pumping, authenticated menu routing, local pairing commands, primary storage,
and shutdown. The Interactive authority bindings are constructed, but their
execution is not exercised by this checkpoint.

New signed multi-process checks prove:

- Agent-to-menu review delivery, duplicate suppression, wrong-ID withdrawal
  rejection, and exact withdrawal. The review is generated transport stimulus,
  not a real client pairing transcript or authority to approve a device.
- Real QR creation and exact retry, dismissal and exact retry, then creation
  and dismissal of a fresh QR. QR endpoints are restricted to loopback.
- Real Control-grant review rejection when no device is paired. No grants,
  paired devices, remote sessions, or LAN route facts appear.
- A real listener owned by the disposable Agent binds exactly
  `127.0.0.1:59654`, verified using the exact PID with `lsof`.
- Concurrent finish through the production enabled-runtime coordinator, plus
  disposable job/process/state cleanup.

## Explicit test boundaries

The Debug-only adapter substitutes the UUID service address, software identity
custody, empty providers, unavailable Interactive initial platform, inert
process starter, loopback binding, and generated review stimulus. Signing and
peer requirements remain enforced. Installed products and production Keychain,
TCC, and physical devices are untouched.

The loopback lane substitutes explicit private-endpoint readiness for Bonjour;
it does not advertise a service or invent LAN route facts. It requires the
actual shared listener to be listening and the pairing context to report
listener readiness. Unit tests prove premature readiness and additional routes
are rejected, and that the substitute cannot be applied to a Bonjour product.
This is not proof of Local Network permission or LAN discovery behavior.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/validate.sh`:
  passed, **1,744 Swift tests across 42 runners**, plus policy, fixture,
  isolation checks and platform builds.
  Log: `/private/tmp/maccompanion-presentation-xpc-validation.log`.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --package-path Packages/MacCompanionKit -c release --target CompanionAgentApplicationPlatform`:
  passed. Log: `/private/tmp/maccompanion-presentation-xpc-release.log`.
- Defined-symbol inspection across seven affected transport/bootstrap/startup/
  product/network objects found **387 matching Debug symbols and zero Release
  symbols**. Object-file headers were excluded from the count. Both static
  isolation validators and `git diff --check` passed.
- Final matrix source SHA-256:
  `9ae061a0bc4c3108e351960ffa6392bd762365262ae31f33d71b8a894c0bf406`.
- Three consecutive runs of
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify_agent_xpc.py`
  each passed **35/35 with verified cleanup**:
  `/private/tmp/maccompanion-agent-xpc-evidence.05ico09w/report.json`,
  `/private/tmp/maccompanion-agent-xpc-evidence.kkjz48ik/report.json`, and
  `/private/tmp/maccompanion-agent-xpc-evidence.smgv3zng/report.json`.
  The final run took 13.133 seconds; its UUID job was independently confirmed
  absent after completion, with no matching disposable helper processes.

These are beta-toolchain results, not stable-toolchain release certification.
Private runtime evidence is intentionally not committed.

## Failures retained and next work

The earlier [pre-output launch stalls](2026-08-28-pre-physical-primary-xpc.md)
remain unresolved. This checkpoint also encountered a signed menu handshake
timeout in
`/private/tmp/maccompanion-agent-xpc-evidence.rikymdty/report.json`:
the Agent reached readiness, while the client printed `probe-entered` followed
by `failure:timeout` before an authenticated event. Its cause is not established.
Later passing repetitions do not close these reliability findings. The runner
has not relaxed deadlines or added hidden retries.

The later
[2026-08-29 startup and signed menu-handshake stress checkpoint](2026-08-29-agent-startup-handshake-stress.md)
does close the current-source reliability gate without altering this historical
record: two independent runs complete 200 total launches, including 50 full
production-presentation signed menu cycles, with the same ten-second deadline,
no retry, and verified graceful cleanup. The original timeout cause remains
unknown and is not relabeled as a passing test.

An earlier no-listener test composition correctly failed QR creation. The
test was extended to use the real loopback listener and explicit Debug endpoint
readiness; the production readiness guard was not removed.

Next required work includes real client pairing/approval and durable reconnect
through this composed Agent; grants, Stop/revoke, history/diagnostics and
recovery; signed Interactive execution and real lease/admission; durable
remote Observe sequences; and the combined Simulator journey. Add an actual
menu-loss test with an outstanding QR and replacement-menu recovery rather
than assuming that source-level construction proves it. P1/P2 remain active,
and the launch/handshake reliability findings remain part of P6/P8.
