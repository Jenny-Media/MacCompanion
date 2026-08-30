# Host listener ingress composition v0.1

Status: normative bundle-independent composition for routing one verified-ready
host TLS connection into pairing or application-primary ownership. This profile
does not define final listener identity, interface policy, signed application
targets, or physical Network.framework evidence.

## First-frame classification

The sealed listener and accepted-connection authority first establish the exact
host TLS binding defined by `transport-security.md`. Only then may one ingress
classifier consume the verified-ready connection. The classifier reads exactly
one bounded length-prefixed frame without reading bytes belonging to a second
frame. It applies the normal strict JSON and kind parser and accepts only:

- `auth.hello`, classified as application-primary; or
- `pairing.begin`, classified as pairing.

Every other kind, malformed or truncated framing, invalid JSON, duplicate key,
unknown kind, remote close, receive failure, clock regression, or expiry closes
the exact connection. Classification has one monotonic deadline: the primary
authentication deadline measured from the listener-owned acceptance timestamp.
Traffic and wall-clock changes never extend it. The classifier is one-use and
returns an opaque classified connection containing the same TLS binding, same
socket owner, and exact first frame; callers cannot reconstruct that authority
from a kind and fingerprint.

Classification grants nothing. The selected role owner must strictly decode
and admit the preserved first frame again. `auth.hello` is admitted only by the
startup-reconciled application-primary authority. `pairing.begin` is admitted
only by the boot-scoped pairing authority and exact currently visible pairing
session. A kind match cannot bypass either semantic owner.

## Independent role ownership

The Stage 2 product owns at most eight active application-primary connections
and at most one active pairing connection. A classified pairing candidate never
closes, replaces, increments, or otherwise mutates the retained primary set. A
primary candidate never consumes or completes a pairing session. Listener
shutdown, Agent loss, logout, or disable closes every role; role-local failure
closes only the matching generation.

Only one unclassified TLS candidate is classified at a time; at most three
additional accepted candidates wait in a bounded FIFO. A later accepted
candidate cannot retire any active role merely by reaching TLS ready or
presenting a registered first kind. Publication occurs only after the matching
role factory has consumed the classified authority and activated its exact
pump. Every callback is fenced by a local generation token.

A later valid application-primary candidate joins the bounded retained set
according to `primary-session-composition.md`; it does not displace an existing
client. A second pairing candidate is rejected while an exact pairing
connection owns the visible boot-scoped session; it does not displace that
owner. These rules prevent an unauthenticated connection from interrupting a
Mac user's SAS decision or an authenticated client's Observe/Act connection.

## Pairing pump

The pairing pump preserves serialized receive/process/send backpressure. It
replays the classified `pairing.begin` through the host pairing wire owner,
then accepts only its correlated `pairing.prove`. After sending
`pairing.pendingApproval`, it retains the connection while awaiting the local
one-use outcome. A byte-independent monotonic task checks for durable completion
or exact expiry even when the peer sends nothing. Empty checks allocate no wire
message ID in the semantic replay window and never extend the deadline.

Only a durable approved outcome produces `pairing.complete`; decline and expiry
produce the registered terminal error. The terminal frame is sent once before
the pump closes. Remote close, malformed input, local publication failure,
send/receive failure, cancellation, or listener teardown cancels the exact host
pairing owner. No pairing byte pump may log frame content, SAS, key material,
device name, IDs, endpoints, or underlying error text.

## Acceptance boundary

Bundle-independent acceptance requires authoritative `auth.hello` and
`pairing.begin` first-frame vectors; fragmented prefix and payload; no second-
frame over-read; wrong-kind, malformed, truncated, silent-deadline, and clock-
regression closure; one-use classified authority; strict replay of the first
frame; pairing challenge/prove/pending ordering; silent server-initiated
completion and expiry; cancellation; and tests proving pairing and retained
primary generations cannot displace one another, while exact primary terminal
cleanup cannot affect a peer. Release acceptance additionally
requires live listener classification, signed key custody, authenticated local
review publication, physical QR/TLS exchange, and fault evidence on supported
macOS hardware.
