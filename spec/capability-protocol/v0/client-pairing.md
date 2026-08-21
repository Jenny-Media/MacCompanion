# Client pairing composition v0.1

Status: normative bundle-independent client composition. This profile binds a validated pairing QR, pinned TLS connection, client-held keys, transcript proof, SAS, and final host response. It does not define QR camera UI, sockets, private-key custody, durable client storage, local Mac approval UI, or permanent Apple targets.

## Inputs and phases

Construction takes the already strict-decoded QR payload, a new stable client ID, two valid P-256 public keys, and an injected session-key signer. One client owner has these phases:

```text
awaitingTCP
  -> awaitingPinnedTLS
  -> readyToBegin
  -> awaitingChallenge
  -> awaitingPendingApproval
  -> awaitingCompletion
  -> paired
  -> closed
```

Any invalid transition, malformed message, replay, bad correlation, pin mismatch, transcript/SAS/expiry mismatch, signing failure, remote pairing error, or deadline failure closes the owner and publishes no paired host. A closed owner cannot reopen.

The owner extracts and retains only the QR facts required by pairing: pairing ID, one-time secret, host fingerprint, expiry, and bounded endpoint candidates. The route candidates remain untrusted routing hints. One replay window spans both sent and received message IDs.

## Pin and transcript gates

No `pairing.begin` is admitted until the pairing-role transport authority accepts live evidence for exactly TLS 1.3, no early data, accepted pinned-leaf policy, and an independently extracted SPKI matching the QR fingerprint.

`pairing.begin` carries the QR pairing ID, stable client ID, session and approval public keys, and a fresh 32-byte client nonce. The client accepts only a correlated `pairing.challenge` whose host fingerprint repeats the QR fingerprint. It constructs the exact normative transcript from:

- pairing ID and QR host fingerprint;
- client ID and both P-256 public keys;
- client and host nonces; and
- selected protocol version.

The client computes the transcript digest, HMAC secret proof, and SAS from that transcript. The injected session-key signer receives only `pairingSignatureInput(transcriptDigest)` and must return the fixed-width 64-byte P-256 `r || s` signature. `pairing.prove` correlates to the challenge.

## SAS and completion

The client requires `pairing.pendingApproval` to correlate to the proof and exactly repeat its transcript digest, derived authentication string, and QR expiry. Only then may UI show the six-hex-digit SAS for human comparison with the Mac. Acceptance of this message grants nothing. Once it is verified, the client clears its one-time secret and nonce.

The client remains pending until a `pairing.complete` correlated to the same proof arrives. The body must repeat the QR host fingerprint and the wire schema must prove the initial state is exactly monitor-only with authorization epoch and grant revision equal to one. Only then may the owner publish the host ID, device ID, fingerprint, routes, and initial revisions for one atomic client-side durable commit. A client storage failure must publish no usable paired record and must not silently regenerate either private key.

## Local naming and approval

The remote pairing messages intentionally contain no client/device display
name. After proof verification, the Agent derives SHA-256 fingerprints of both
validated 65-byte client public keys and publishes a secret-free local review
containing a new review ID, pairing/client IDs, both key fingerprints, the
transcript digest, derived authentication string, current policy revision, and
pairing expiry. The
review is available only to the authenticated visible menu app and is excluded
from diagnostics, audit detail, logs, crash reports, and the CLI.

The local user compares the authentication string and, to approve, chooses a
`DeviceDisplayName`; no remotely supplied name may prefill or replace that
choice. Approve/decline binds the exact review, pairing/client IDs, both key
fingerprints, transcript digest, decision, and decision time. Approval also
binds the locally chosen name; decline carries no name.
Approval atomically consumes the pairing session and stores the name in the
same transaction as the device keys, Monitor Only authorization, initial
revisions, and minimal security event. Decline consumes the session without
creating a device or name. A stale, expired, mismatched, absent-UI, or replayed
decision fails closed.

## Timing

At connection start the QR must still be unexpired. The client converts the lesser of remaining QR wall lifetime and five minutes into a monotonic deadline; subsequent wall-clock changes cannot extend it. A separate socket timer invokes the deadline check at the exact boundary even if the peer is silent. The host independently owns its boot-scoped monotonic lifetime and five-proof limit.

## Application-owner composition

One application-global pairing owner connects explicit preview acceptance to
identity preparation, one exact connection, the pairing authority,
presentation, and durable publication. Its immutable connection request carries
the pairing ID, QR host fingerprint, bounded QR routes, and QR wall expiry. The
same returned connection object owns TCP, TLS evidence, every framed send and
receive, and close. Every post-TCP send and receive receives the single
monotonic deadline published by `ClientPairingSessionV0`; the adapter must use a
byte-independent timer and may not extend that value after traffic. Initial
connection establishment is separately bounded by the QR wall expiry.

The owner publishes only the closed presentation progression. Provider errors
are mapped to invalid/expired code, connection failure, identity-verification
failure, host rejection, client-storage failure, or unknown; raw transport,
custody, and persistence text never enters presentation. Attempt revisions
fence every asynchronous return. Cancellation before durable commit closes the
exact connection and session, discards the unpublished prepared identity, and
resets presentation. Once the atomic record commit begins, cancellation is
deferred because pre-commit and post-commit state cannot be distinguished;
publication converges to paired or storage failure, while process death is
handled by prepared-identity restart reconciliation.

The release iOS target does not construct this owner from an arbitrary
connection factory, pairing clock, randomness source, or pinned-leaf evaluator.
The public Network-platform product factory constructs the exact immutable-pin
route-racing connection factory with the strict single-leaf Security.framework
evaluator, supplies system wall/monotonic time, and leaves the application
owner on system random bytes and UUIDs. It accepts only the stable client ID,
client key custody, atomic paired-host persistence, platform queues, and a
presentation callback. Generic connections, clocks, randomness, route
attempters, and trust evaluators remain package/test seams.

## Host wire-owner composition

One bundle-independent Agent owner is created only from the exact verified
host TLS binding and the Agent's boot-scoped pairing, local-decision, policy,
and host-identity authorities. It accepts exactly `pairing.begin` followed by a
correlated `pairing.prove`. Incoming and outgoing message IDs share one bounded
replay window; wall and monotonic clocks cannot regress; every transition is
bounded by the pairing authority's original boot-scoped monotonic deadline.

After proof succeeds, the owner registers the complete secret-free local
review and requires an injected trusted-local publisher to acknowledge that
exact review before returning `pairing.pendingApproval`. Publication failure,
connection loss, cancellation, phase/correlation mismatch, or a concurrent
transition cancels the local review and consumes the pairing authority. The
wire owner never accepts a locally asserted review, name, decision, host ID,
fingerprint, or policy revision.

The publisher also owns exact review withdrawal. Every terminal host-wire
path withdraws the review ID before clearing transient state. If the
authenticated local delivery boundary reports that the registered review is
no longer available, the owner returns a terminal closed pairing error on its
next byte-independent completion check; it does not keep a reviewless remote
connection alive until the original deadline. The connection-scoped delivery,
Mac presentation, exact retry, and endpoint-loss rules are normative in
`../../local-ipc/v0/README.md`.

Completion is server-initiated. The owner consumes the decision handler's
one-use outcome and emits `pairing.complete`, correlated to the original
`pairing.prove`, only from the exact durably committed `CompletedPairing` plus
its constructor-bound host ID and TLS fingerprint. Decline or expiry emits a
closed registered pairing error correlated to the proof and closes the owner.
If no outcome exists, polling mutates no replay or completion state. A delayed
poll may still deliver an already-durable approval; it may not resurrect an
uncommitted expired review.

v0.1 does not claim cross-connection completion recovery. If the durable Mac
commit succeeds but the completion frame is lost, the Mac may retain one
locally visible Monitor Only device while the phone remains unpaired. The
service grants no Act or Control authority, does not silently merge a later
pairing, and requires the Mac user to remove that orphaned device before a
fresh pairing. A later minor version may add a fixture-backed exact-key
completion-resume flow; it must not infer success from a reused QR or client
ID alone.

The live socket boundary is defined by `host-listener-ingress.md`. In
particular, a `pairing.begin` first frame selects the pairing role but grants
nothing, and a pairing candidate cannot replace an active authenticated
application-primary connection.

## Acceptance boundary

Bundle-independent acceptance requires proof/signature verification, SAS and final monitor-only convergence, no pre-pin bytes, challenge pin mismatch, transcript/SAS/expiry mismatch, completion correlation/fingerprint mismatch, remote denial, exact connection/deadline propagation, cancellation fencing, atomic device/name commit convergence, silent exact-deadline tests, immutable-pin route racing, fragmented and malformed framing, late-winner cleanup, inert network-factory construction, strict local review/decision payloads, stale/mismatched/replayed local-decision rejection, trusted-local review publication before pending, server-initiated durable completion, decline/expiry error closure, and disconnect/publication-race cancellation. Release acceptance additionally requires QR capture/presentation, Keychain-backed keys, atomic client record persistence, live pinned transport, authenticated local approval IPC/UI, restart recovery, and physical-device exchange.
