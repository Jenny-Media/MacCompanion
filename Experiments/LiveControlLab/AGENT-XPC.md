# Isolated Agent startup and XPC integration

Run from the repository root on a macOS 26+ development host:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
python3 scripts/verify_agent_xpc.py
```

Requires an existing usable Apple-issued signing identity (defaults to
`Developer ID Application`; override with
`MACCOMPANION_XPC_PROBE_SIGNING_IDENTITY`) and access to the user's launchd
domain. This is an opt-in local integration lane, not an ordinary CI unit
test. It must not prompt for or change privacy permissions.

The runner builds the `maccompanion-agent-xpc-test` Debug-only executable,
signs disposable copies, and registers exactly one randomly UUID-named Mach
service. It never selects the installed service label. Server and client use
the production same-team **and exact signing identifier** requirements,
closed hello handshake, readiness/status transport, and generation fencing.
The adversarial C client sends only the constant or intentionally malformed
content-free hello and verifies rejection; a timeout is a failure, not proof
of rejection.

## What runs

- Production startup coordinator with injected preparation: first-unlock
  deferral, preparation failure, invalid initial revision, and listener failure
  without fallback to another service profile.
- Production disabled bootstrap runtime/authority and atomic intent store:
  exact enable receipt, latched restart request, and enabled startup after
  a fresh process loads that disposable intent.
- Real signed XPC between separate processes: repeated status, readiness
  ordering, duplicate readiness, same-instance reconnect, old-menu generation
  retirement, wrong menu/Agent identity, ad-hoc signer, and malformed hello.
- Source-unavailable responses, a two-second status timeout with a deliberately
  late completion, Agent death during a pending read, and fresh-process recovery.
- Concurrent finish calls share one terminal cleanup. The runner checks
  process exit, launchd removal, and deletion of disposable state/helpers.
- A separate `productionPrimary` lane prepares the real primary root with
  required-audit SQLite storage, durable startup reconciliation, lifecycle
  observation/event pump and local status reader. It verifies signed readiness,
  reconnect, supersession, graceful/abrupt restart with the exact same stored
  identity, and missing-established-key rejection without identity replacement.
- `productionPresentation` runs the production enabled-runtime coordinator,
  menu/presentation composition and shared listener owner with a Debug-only
  loopback binding. It checks generated review delivery/duplicate suppression/
  exact withdrawal, real QR create/dismiss retries, fresh QR creation, rejection
  of Control grant review without a paired device, and concurrent shutdown.
  `lsof` must show only `127.0.0.1:59654` for the owned Agent's listener.
- Menu-process loss with an outstanding QR, followed by fresh QR creation in
  a replacement signed menu process. The old QR is retired without stopping
  the listener or existing Observe authority.
- Real client pairing over pinned TLS against that production Agent graph:
  matching live pairing code/key fingerprints, signed local approval, exact
  decision replay, altered-decision rejection, and monitor-only durable state.
- Fresh-process client reconnect, real authenticated Observe responses with
  advancing SQLite-backed sequence numbers, then graceful and forced Agent
  restart with preserved host identity and durable client pairing.
- Signed Control-grant decline followed by a fresh exact review/approval,
  visible-admission publication, production lease issuance and runtime install,
  both authenticated Interactive role channels, two real scheduled renewals,
  and client Stop with Observe still using the same primary connection.
- Display-admission withdrawal while Desktop preparation is paused: no capture
  installation, a controlled denial, working signed status and continuing
  Observe. No-display publications and receipts encode explicit JSON null.
- Loss of the signed menu connection during active Control: the real menu
  runtime returns to idle and invokes capture/input/frame/indicator cleanup;
  the authenticated Observe connection remains usable.
- A fresh signed menu after that Control failure can review device revocation.
  Abandoned and replaced reviews, altered review requests, and changed durable
  command replays are rejected. Confirmed revocation retires the primary and
  active Control, removes grants, advances both authorization revisions once,
  and persists one completed receipt and security event. Exact retries preserve
  that receipt and do not repeat the revision or event changes.
- The revoked saved client fails to reconnect, including after graceful and
  forced Agent restart; signed status remains available and the durable
  revocation state is unchanged. No new pairing or identity is substituted.
- A second freshly paired test client is revoked while Desktop preparation is
  paused. The test observes primary closure before releasing the descriptor,
  requires zero capture starts, verifies exact receipt replay and signed local
  status, and checks two separate durable revoked-device records. The original
  revoked client's identity/state is never rewritten or revived.

- A separate Act-only journey starts with no grants, rejects an ungranted
  operation at the client, then obtains a signed Agent-issued capability review.
  It tests decline and exact retry, changed-decision rejection, fresh approval,
  primary fencing/reconnect, native `setAudioMuted` execution and verified
  read-back, injected mismatching read-back failure, and continued Observe with
  Control inactive. Exactly three test audio calls occur; duplicate invocation
  performs no extra effect. Graceful and abrupt Agent restarts preserve status
  and invocation replay without executing the provider again. Subsequent
  Control grant review preserves the independent Act grant.

- A raw client still uses real pinned TLS and application authentication, but
  bypasses client catalog guards to prove that the Agent denies an ungranted
  invoke without creating an operation or executing a provider. Missing status
  and cancel targets return the same opaque not-found response.
- A test-only wrapper pauses delivery of the real native provider's test result.
  On that same primary, status reports running and repeated cancellation reports
  cancelRequested while calling the provider hook once. Releasing the result
  permits succeeded, never a false cancelled claim. Killing the disposable Agent
  after the test effect but before terminal commit instead yields durable
  outcomeUnknown after restart; status and exact invoke replay do not execute it.

There are 55 required checks. Missing/duplicate checks, nonzero commands,
deadline expiry, wrong response markers, or cleanup failures fail the run.
Commands have bounded deadlines. SIGINT/SIGTERM and ordinary exceptions enter
cleanup; SIGKILL/power loss cannot run cleanup. In that exceptional case,
inspect the retained `disposable.plist` in the printed evidence directory and
remove **only its exact UUID label** before deleting its matching temporary
state. Never bootout the production Agent to recover this test.

Logs and `report.json` remain in the printed private temporary evidence
directory. Test state, signed helper copies, and the temporary launchd plist
are removed after normal cleanup. No screenshots or user input are recorded.

## Deliberate limits

The original 24 fault checks inject preparation and synthetic status. The eight
`primary-production-*` checks instead execute the real prepared primary product
and signed lifecycle/status composition. Custody is a disposable software key
and persisted certificate, the native audio provider has a test-only in-memory
controller, Interactive is unavailable,
and process startup is inert. The Agent starts only local authorization, not
the full shipping menu-presentation/network composition in `productionPrimary`.
The presentation lane does run that composition and enabled-runtime owner,
with loopback/port substituted by a Debug adapter. The original review-delivery
case uses generated transport stimulus; the subsequent real pairing case uses
the production client, transcript and signed approval owners. The private
endpoint confirmation is an explicit substitute for Bonjour readiness: it
requires actual listener readiness, emits no advertisement or LAN-route fact,
and cannot be used with the production Bonjour binding. Its QR contains only
the loopback endpoint. No readiness check was removed to create a QR.

The new client lane substitutes software client keys and the local human
approval gesture, not TLS pinning, transcript verification, durable pairing,
authentication or Observe ownership. It runs the platform-independent client
owners in a disposable macOS CLI process; it is not an iOS UI acceptance test.

The `productionInteractive` lane additionally substitutes an active console
fact and an opaque test display. Production Agent grant/admission/runtime/
renewal owners and the signed XPC route invoke the real menu runtime owner and
lease adapter. `ProbeInteractiveEffects` supplies capture/indicator/desktop
readiness and counts cleanup; it does not capture a screen, display an actual
indicator, render video, post input, or implement focus/surface transitions.
Lease renewal validates production binding rules, including new lease IDs.

Act grants and operations use the real Agent capability publication, SQLite
grant transaction, primary/router, approval and native-provider owners. Only
the audio controller is substituted in the core lane, including a deliberate
bad read-back on its second execution. Fault lanes additionally wrap the native
provider to pause result delivery for at most twelve seconds. They prove the
host denial/cancellation/crash behavior above, not actual system audio,
successful hardware cancellation or process termination of an external provider.
Visible Act administration UI and broader provider/lifecycle faults remain work.

This does not establish administrative Stop/history/
diagnostics, ScreenCaptureKit, SMAppService installation, TCC,
Secure Enclave, Face ID, Bonjour/LAN, or physical-device behavior.

This lane complements the authenticated Simulator/real-window journeys; it
does not replace their UI/media coverage or authorize testing the installed
app or physical iPhone. Debug address factories and the internal startup seam
are compiled out of Release. `scripts/validate.sh` runs source-isolation guards
and ordinary startup/XPC unit tests without registering this test job.

The software key is mode 0600 inside the UUID-scoped private state and is
deleted by cleanup. It is never printed, copied to evidence, or used as a
production identity. Certificate reload shares the production validation code;
the public custody path still requires its exact approved Keychain tag.

Earlier pre-output startup stalls and one handshake timeout remain open
reliability findings. The runner retains exact-job startup state and samples
only its disposable Agent if startup misses its unchanged deadline. Passing
repeats do not erase failed reports or close that finding.
