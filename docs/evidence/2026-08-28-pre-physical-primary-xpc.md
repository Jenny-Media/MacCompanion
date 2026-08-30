# Pre-physical goal: real primary/local XPC checkpoint — 2026-08-28

## Scope and result

The approved [pre-physical goal](../pre-physical-execution-plan.md) is active.
The signed-process matrix now has 32 required cases, including eight that use
the real prepared primary product rather than an injected product/status pair.
This is a completed implementation slice, not completion of P1 or the goal.

The new lane exercises required-audit SQLite storage, primary startup and its
reconciliation, deferred local authorization, lifecycle observation/event
pumping, and the real local status reader over the existing signed XPC
transport. The client waits for actual Agent/menu readiness, requires advancing
local diagnostic sequences, and checks that no route, pairing or Control grant
appears. It also verifies bootstrap rejection, reconnect, peer supersession,
concurrent finish, and graceful/abrupt restart with the identical persisted
host-identity row. Missing established software keys fail without replacement.

The production certificate reload body was extracted into one internal helper
used by both public custody and the disposable test. Public custody still
resolves only its exact permitted Keychain tag; no public key-injection API or
authentication bypass was introduced. Tests cover unchanged certificate/key
reload, wrong-key rejection, malformed certificate and expiry.

## Verification

- `bash scripts/validate.sh`: passed, **1,742 Swift tests across 42 runners**,
  plus fixture/policy/isolation validators and platform builds.
  Log: `/private/tmp/maccompanion-primary-xpc-validation.log`.
- Release `CompanionAgentApplicationPlatform` build: passed on installed Xcode
  beta. Log: `/private/tmp/maccompanion-primary-xpc-release.log`.
- Defined-symbol inspection of transport, bootstrap client, startup bridge and
  coordinator objects: **154 matching Debug symbols, zero Release symbols**.
  Object-file headers are excluded from this count.
- Final matrix source fingerprint:
  `df9738e81fec7af1d544b7422d659fc35b3f899494abda99f4fd476439403967`.
- Three consecutive final 32/32 runs:
  `/private/tmp/maccompanion-agent-xpc-evidence.14mss767/report.json`,
  `/private/tmp/maccompanion-agent-xpc-evidence.0gr81lg_/report.json`, and
  `/private/tmp/maccompanion-agent-xpc-evidence.57d7lqvj/report.json`.
  Each records all required outcomes, exact UUID service, source fingerprint,
  elapsed time and verified cleanup. The last run took 14.895 seconds.
- `git diff --check` and isolated source guards passed.

## Open launch-stall finding

Two earlier repeats timed out before the disposable Agent printed anything:
`/private/tmp/maccompanion-agent-xpc-evidence.1kdap3g3/report.json` and
`/private/tmp/maccompanion-agent-xpc-evidence.hv4ksito/report.json`.
They remain **failed runs**, not successful negative tests. Both occurred while
other local builds were running; causation is not established.

In the second failure, exact-job evidence shows launchd progressed from
`xpcproxy` to a running PID, but the process produced no startup output. No
application stack was captured then, so the underlying cause is unresolved.
The runner now retains exact-job state before readiness and on failure,
tracks the PID before readiness for cleanup, and captures a read-only stack
sample of that exact disposable Agent if the deadline fails. The executable
also emits entry/preparation markers. The ten-second deadline was not relaxed,
and there is no hidden retry inside a case.

Later passes do not close this finding. P6/P8 must reproduce or explain the
stall and close the startup reliability gate before pre-physical handoff.

### 2026-08-29 current-source disposition

The failed runs above remain historical failures and their cause is not
retroactively asserted. The later
[startup and signed menu-handshake stress checkpoint](2026-08-29-agent-startup-handshake-stress.md)
adds a dedicated fail-fast gate with exact job/PID capture and completes two
independent 100-cycle runs against current source. All 200 launches crossed
entry, preparation, mode-specific readiness and cleanup under the unchanged
ten-second deadline. Presentation cycles also completed the signed menu
handshake and graceful shutdown. The historical evidence remains retained, but
it is no longer an unresolved current-source P6/P8 reliability gate.

## Deliberate substitutes and next work

- Identity custody: mode-0600 software key in the private test directory; no
  production Keychain or Secure Enclave. Certificate reload validation is real.
- Empty provider registry, unavailable Interactive platform, and inert process
  starter. No real audio, capture, input, privacy prompts or installed app.
- Only local authorization starts. Full authenticated menu/presentation and
  loopback-only enabled network composition are next; full lease/admission,
  durable remote Observe sequences and combined Simulator remain unproven.
- No physical iPhone, installed Agent, production data, or external account was
  changed. Test helpers/state/jobs are disposable; evidence stays private.
- Beta-toolchain module evidence is not stable-toolchain or release approval.
