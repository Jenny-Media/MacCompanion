# WebRTC media adapter boundary v0.1

Status: normative boundary for a candidate media adapter. The closed v0.1
signaling messages below are admitted only on the authenticated primary
command channel. They do not replace the credentialed `media` role in
`session-channel-messages.md` and `media-records.md`; a release composition
needs separate dependency and runtime admission before WebRTC becomes the
active media path. The disposable probe's file exchange has no product authority.

## Ownership

One adapter lease is created only after `interactive.session.accepted` on the
authenticated application-primary connection. Its immutable binding consists
of host ID, the exact pinned 32-byte host SPKI fingerprint, client ID, the
server-issued 16-byte primary connection ID, Interactive session ID,
authorization epoch, and a locally minted Control generation. The primary
owner and Interactive authority supply these values; SDP, ICE, a peer callback,
or a persisted resume flag cannot supply or modify them. Observe and Act
continue on their own grants. A media lease cannot create or resume Control,
input, or a role credential.

The Agent owns authenticated primary ingress, while the menu app owns
ScreenCaptureKit capture under its own Screen Recording attribution. A Mac
WebRTC sender must remain bound to that menu-owned capture lifetime. If the
Agent forwards offer/answer commands to the menu app, the forwarding path must
use the existing authenticated, generation-bound local authority and must
revalidate the same active session and lease on both sides. The Agent's
optional negotiation interface alone does not create a capture peer or grant
the Agent screen access.

The candidate local forwarding profile uses three closed Agent-to-menu XPC
commands: `runtime.interactive.webrtc.offer`,
`runtime.interactive.webrtc.answer`, and
`runtime.interactive.webrtc.close`. They share the existing one-command-in-flight
generation gate and `applyInteractiveSurface` authorization; no menu-to-Agent
listener is added. Each command is canonical JSON no larger than 4,096 bytes.
The offer command contains `commandID` and the authenticated-primary fence;
its correlated receipt contains the bounded SDP and DTLS fingerprint. The
answer command contains `commandID` and the exact validated answer body; its
success reply is payload-free. Close contains `commandID` and the exact Control
session ID; its success reply is payload-free. Any SDP that fits the remote
48,000-byte bound but exceeds the local XPC bound fails closed before disclosure.
The menu rechecks the exact current lease, session, epoch, surface, and
revisions before and after every WebRTC suspension. Agent generation loss or
Control revocation closes the peer and capture stream. Neither local command
can create a Control lease, resume input, or carry pixels. The authoritative
local transport cases are indexed by `spec/fixtures/manifest.json`.

The lease carries the accepted Control session's original host-monotonic
deadline. A replacement peer keeps that deadline and all binding fields.
Every admission, send, receive, and callback rechecks the exact live primary,
session, epoch, Control generation, current grant/policy state, and deadline
with the authoritative owner. Revocation, primary loss, expiry, or Stop first
closes admission and clears presentation, then disposes the peer. Stop is
terminal for that lease even while an offer, answer, or ICE operation awaits.
A later Control session requires a new approval and a new lease.

## Closed candidate signaling contract

Only the authenticated primary command channel may carry a bounded offer,
answer, or ICE candidate. It must not expose a listener or use the paired-device
file relay. The host authenticates the sender through its existing primary
owner; the client verifies the pinned host identity through that connection.
Each message must include the exact Interactive session ID, authorization
epoch, peer generation, negotiation ID, unique message ID, and required
correlation. Host ID, pinned fingerprint, client ID, and primary connection ID
come from the authenticated primary owner and must not be asserted by a
signaling body. SDP and ICE bytes remain untrusted negotiation data, with strict
size, count, and lifetime limits before parsing. A WebRTC DTLS fingerprint in
SDP must be bound to the accepted authenticated offer/answer transcript;
matching the TLS host pin alone does not authenticate an arbitrary DTLS peer. No
application-authentication, pairing, approval, or operation signature is
introduced by this adapter.

The first candidate uses complete-gathering SDP, with ICE candidates inside
that SDP. This avoids a host-origin signaling event and a separate candidate
queue. The client sends an original `interactive.media.offer.request`; the
authenticated host returns a correlated `interactive.media.offer` carrying its
complete local SDP. The client sends an original `interactive.media.answer`
that names the exact offer message ID; the host returns correlated
`interactive.media.ready` only after its current peer accepts that answer.
All four use the existing command envelope and carry a closed `fence` object:
`interactiveSessionID`, `authorizationEpoch`, `negotiationID`,
`peerGeneration`, `surfaceID`, `surfaceRevision`, and
`coordinateSpaceRevision`. The client mints a fresh negotiation UUID and a
strictly increasing peer generation for each attempt; the host accepts only
a greater generation for the active Control session. The offer request body
contains only `fence`. Offer bodies add `sdp` and `dtlsFingerprintHex`.
Answer bodies add those fields and `offerMessageID`, which must equal the
exact offer envelope ID. Ready bodies carry `fence` and `offerMessageID`.
The host response correlation points to the immediate client request.
Every exchange must finish before the primary command deadline and original
Control expiry. An ICE restart or foreground return starts a new peer
generation through the same two exchanges, with the old peer fenced first.
Either side rejects an SDP with no ICE candidates or a malformed or
unsupported DTLS fingerprint. Each SDP is at most 48,000 UTF-8 bytes and the
ordinary 65,536-byte command-frame bound still applies. The SDP bytes are not
logged, persisted, audited, or included in user-facing errors.

An SDP uses CRLF-terminated ASCII lines, begins with `v=0`, contains at least
one `a=candidate:` line, and contains one or more identical
`a=fingerprint:sha-256` lines. The fingerprint is 32 colon-separated uppercase
hex bytes and must equal the body's lowercase 64-character
`dtlsFingerprintHex`. Unsupported or conflicting fingerprint lines fail closed.
The WebRTC adapter must independently observe complete ICE gathering before
disclosing local SDP; the optional `a=end-of-candidates` line is not proof of
that runtime state.
The authenticated primary transports these exact SDP bytes; the peer's DTLS
fingerprint is accepted only from that validated SDP. The candidate origin
address and candidate set do not grant Control or expand the authenticated
primary's ownership.

An offer starts a fresh peer generation. Exactly one answer can satisfy that
generation's offer. ICE candidates are admitted only for that exact live
generation after its corresponding offer; duplicates, uncorrelated answers,
stale candidates, and callbacks from an old peer are discarded. Generation
numbers never wrap or reuse within a lease. Background return may replace the
peer after revalidation while the same Control session remains live, but may
not create a session or extend its deadline. Replacement first blanks the old
video and releases local input; input can resume only through the existing
Control and surface acknowledgement gates.

The media adapter accepts only frames from the current peer after the exact
session, epoch, generation, and acknowledged surface ID plus surface and
coordinate-space revisions are revalidated. A surface change blanks the old
output immediately; old-surface frames cannot populate the replacement. A frame-free
interval may clear video and show waiting, but does not itself diagnose route
loss or authorize renegotiation. First offered, answered, and presented-frame
times are measured separately; rendered appearance requires manual acceptance.
`interactive.media.ready` proves only that the host accepted the answer. It is
not a rendered-frame receipt and cannot satisfy the existing clean-frame
acknowledgement or resume input. Before activating WebRTC in the normal apps,
define and fixture an exact current-peer/current-surface rendered-frame proof,
then bind it to the host's Control acknowledgement gate.
For a development video preview that does not replace the v0.1 media role,
the normal iPhone app may overlay a decoded WebRTC stream only while all
WebRTC-origin input and surface-changing actions stay disabled. Its current
H.264 role continues to own the existing Control acknowledgement; WebRTC
`ready` never promotes that role. A failed or closed peer removes and blanks
the overlay. This preview is not evidence that WebRTC has replaced the video
engine or that its rendered-frame proof is complete.

The authoritative transition cases in
`spec/fixtures/valid/interactive-webrtc-media-lease.json` cover replacement,
duplicate/stale signaling, background return, Stop racing negotiation, expiry,
revocation, and old-peer callbacks. These cases define local lease behavior;
they are not WebRTC wire-message fixtures. Offer, answer, and ready wire
fixtures are separately indexed in `spec/fixtures/manifest.json`. No new
application-authentication or approval signature is defined here.
