# Network primary frame-pump evidence — 2026-08-20

Status: provisional no-network construction and injected-fault evidence under Xcode 27 beta. This is not a live listener, TLS handshake, trusted certificate, route, signed-identity, or release result.

`CompanionNetworkPlatform` contains a host-side adapter for one already accepted `NWConnection`. Its public constructor consumes a one-use verified-ready authority created only after the sealed listener owner starts and inspects that exact accepted object for negotiated TLS 1.3, no accepted early data, and the configured served-host SPKI fingerprint. Arbitrary connection-plus-binding construction and manual connection start remain module-internal. `CompanionClientNetworkPlatform` separately contains the client-side pump and a one-shot TLS-attempt context for one route, immutable saved pin, callback, and exact outbound connection reference. The context can retain a handoff only after its strict `SecTrust` pinned-leaf evaluator succeeds and the callback independently matches the returned SPKI to the pin.

The adapter:

- incrementally decodes the bounded length-prefixed application frames;
- serializes receive, session processing, and response send for bounded backpressure;
- gives the application session all authentication, replay, durable-principal, and semantic routing authority;
- closes the application session on transport, framing, protocol, or send failure; and
- owns a separate monotonic deadline task, so the 10-second authentication and 45-second authenticated-idle limits terminate a silent connection without waiting for another byte.

`CompanionAgentNetworkPlatform` now adds the product composition seam. It
consumes the exact verified-ready connection, obtains the only session the
startup-reconciled Agent authority can issue, constructs the pump from the same
one-shot connection, and attaches transport cancellation to that session before
returning. Reconnect and lifecycle close therefore cancel the socket as well as
closing semantic authority. Failed or stale construction cleans up only its
exact candidate and cannot close a newer current session. The Agent lifecycle
gate also denies new session creation while disabled, logged out, or recovering
from Agent loss.

A generation-bound listener handoff now owns the next asynchronous boundary.
It admits only the newest pending accepted connection, transfers verified
readiness into the fixed Agent binder, begins the exact bound pump, and retires
only matching accepted or primary terminal callbacks. A synchronous
termination latch prevents a pump that terminates inside activation from
replacing and cancelling a healthy older primary. Replacement or cancellation
while binding is suspended causes the eventual stale result to cancel itself;
it cannot publish or close a newer generation.

The host adapter preserves its production `NWConnection` wrapper behind an injected start/state/receive/send/cancel boundary. Tests drive the real `AuthenticatedPrimarySessionV0` through this boundary, including an unknown-client hello and opaque correlated challenge response; the fake transport never decides authentication or constructs semantic responses.

The client adapter additionally:

- replays the exact verified-ready evidence through `ClientPrimarySessionV0` before sending `auth.hello`;
- owns hello/challenge/proof/description framing while leaving correlation, replay, paired host/device checks, and key-backed signing to the client session;
- poisons later queued sends after the first send failure; and
- arms the authentication deadline before awaiting the first send, so a stalled write cannot bypass the ten-second limit.

The client Network target now also composes one planned route into the one-shot TLS context and frame pump. It bounds readiness, retains `.waiting` only until timeout, consumes the verified handoff for the exact ready connection, creates fresh handshake material, maps closed remote authentication errors to terminal denial, exposes authenticated command sending, and cancels the same connection on task cancellation. This composition is compile-checked and rejects invalid pins before creating a connection. Its readiness and authentication synchronization plus framed pump I/O now pass injected no-network faults; live socket behavior is not claimed.

The public validation script explicitly compile-checks this target:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1 \
bash scripts/validate.sh
```

Validation constructs one sealed host listener owner and one unstarted exact
Agent-bound connection, but never starts either and opens no outbound route.
The Agent composition test proves replacement closes the prior session,
transport attachment is lifecycle-owned, menu loss preserves the primary
session, Agent loss cancels the unstarted pump, stale cleanup preserves the
newer session, and lifecycle-unavailable state denies reopening. Thirteen host
Network-platform tests cover exact identity/pin/current-certificate binding
into TLS 1.3-only, no-resumption/no-early-data listener parameters; one-shot
unstarted-listener ownership; wrong pin, malformed pin, and expired leaf
rejection; exact accepted-connection object evaluation; TLS 1.2, early-data,
and missing-metadata rejection; listener and connection terminal teardown;
one-use verified-ready transfer without a second connection start; pump
start-once/nonterminal-state behavior; exact opaque challenge framing;
response-send failure; malformed framing; receive failure; and exactly-once
teardown across late state callbacks and local cancellation. Eighteen client
construction/fault tests exercise the exact pin/no-early-data handoff,
phase-neutral pump construction, bounded handshake-start inputs, all four
closed endpoint mappings, one-context/one-connection construction,
exact-reference handoff consumption, pending-verification rejection, strict
Security leaf evaluation, connection-state classification, recoverable waiting,
terminal failure, timeout, cancellation, first-result-wins authentication
completion, terminal remote-denial classification, late-success rejection,
pre-connection invalid-pin rejection, first-send failure, exact emitted
`auth.hello` framing, malformed framing, receive failure, framed remote denial,
and exactly-once teardown. Acceptance still requires stable Xcode 26.6, final
signed identities, real Keychain-backed listener custody, physical execution
of accepted-connection metadata extraction and socket handoff, and physical
LAN/private-route exchange.

Seven additional no-network Agent handoff tests cover newest-pending admission,
binding and activation failure cleanup, terminal-during-activation fencing,
active replacement with stale terminal delivery, idempotent pending/active
cancellation, and replacement or cancellation while Agent binding is
suspended. They construct but never start `NWConnection` objects.

The sealed outer Agent listener service now connects this handoff to the exact
`NetworkHostListenerOwnerV0`. Its public production initializer accepts only
that sealed owner plus the startup-reconciled Agent primary-session authority;
the injected listener/binder seam is internal test support. It owns listener
start-once state, one acceptance-time sample, terminal-before-report teardown,
idempotent cancellation, and a closed content-free accepted-start failure.
Five no-network service tests prove successful timestamp transfer, active
teardown on listener loss, pending teardown on local cancellation, fail-closed
startup with a late callback, and sanitized per-connection start failure.

The listener owner now publishes its real `.ready` transition exactly once, so
the service does not infer listening from a successful `start` call. A pure
diagnostic projection maps the service snapshot into only the existing closed
`LocalAgentNetworkState`, `routeUnavailable` warning, and a zero-or-one active
remote-session count. Two focused tests cover idle/starting/listening/local-stop
mapping, degraded listener loss, accepted-start warning, and the bounded active
count without addresses, peer facts, TLS detail, or error text.
