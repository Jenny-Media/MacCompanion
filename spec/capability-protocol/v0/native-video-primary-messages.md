# Authenticated native video primary messages v0.1

Status: normative candidate message construction and optional Control dispatch.
No engine dependency, native input grant, or permanent process identity is admitted.

All records use the existing version 0.1 command envelope. Original requests
have null correlationID; each response correlates to its exact request messageID.
They are permitted only on the already authenticated application primary's
Control lane. Observe and Act cannot send them. Existing replay rules apply.
Unknown body/fence keys reject. All base64 strings are canonical padded base64.
A valid wire DER shape is not X.509 validation; native certificate validation
and possession follow the enrollment signing profile.

The fence has the same closed shape and safe positive integer bounds as the
existing media negotiation fence: interactiveSessionID, authorizationEpoch,
negotiationID, peerGeneration, surfaceID, surfaceRevision, coordinateSpaceRevision.
Native peerGeneration has its own increasing connection-local counter. It cannot
create authority. Every operation must refer to the current acknowledged Desktop,
App, or Window, original approved Control deadline, and immutable encoded
geometry. No arbitrary
host/address, upstream pairing, input, or audio option is accepted.

Native client deadline projection uses the existing Control maximum duration
(`InteractiveSessionStateMachine.maximumDurationMilliseconds`, four hours).
Measure the acceptance lifetime from its authenticated envelope timestamp to
its expiry. Reject expired or longer-than-Control lifetimes and arithmetic
overflow. Project once onto the client monotonic clock using the smaller of that
lifetime and the positive wall-clock time remaining; clock skew cannot create
a new session maximum. Native enrollment must not impose a separate shorter session maximum
or extend the accepted original deadline. The surface wire descriptor's relative
validity bounds freshness at admission, as defined by `surface-control-messages.md`;
it does not become a ten-second lifetime for an acknowledged active surface.
After acknowledgement, require the exact live session/epoch/surface/revision
fences and original Control deadline. Replacement, Stop, role loss or revocation
still retires native enrollment. Proof deadlines remain independent bounds on
signing/activation; signing fields and golden vectors are unchanged.
The client admits a fresh native enrollment after an acknowledged App or Window
replacement under the same exact current-surface and deadline checks used for
Desktop. It denies Focused Region. The surface kind is obtained from the
acknowledged descriptor and is not a new remote enrollment-request field.

## Closed records

- `interactive.native.enroll.request`: fence, clientCertificateDERBase64
  (decoded length 1…4096). Reply: challenge or existing error.
- `interactive.native.enroll.challenge`: fence, controlGeneration (UUID),
  encodedWidth (320…8192), encodedHeight (240…8192),
  hostCertificateDERBase64 (decoded length 1…4096),
  hostChallengeBase64 (decoded length 32), signingInputBase64 (1…1024),
  issuedAtUnixMilliseconds and expiresAtUnixMilliseconds (positive JSON-safe
  unsigned integers, strictly increasing, at most 15 seconds apart).
  These fields must reconstruct the exact indexed enrollment signing bytes
  using the local authenticated primary identity/revisions and expected session
  and geometry. The host's generation is obtained from current runtime authority.
  The client must not sign the proposed bytes without reconstruction and local
  certificate validation. No host monotonic-clock value is transmitted.
- `interactive.native.enroll.proof`: fence, challengeMessageID, signatureBase64
  (decoded length exactly 64, existing P-256 session signature profile).
  Reply: ready or error. The challenge message ID, fence and original primary
  must match the retained single-use challenge. Every invalid proof consumes
  the attempt; retry needs explicit new enrollment after complete retirement.
- `interactive.native.ready`: fence, challengeMessageID, portBase (1030…65499).
  This identifies only the host-selected native port base. The client uses the
  verified primary peer route and exact challenge host certificate pin. It is
  not first-frame presentation, an input acknowledgement, or a launch command.
- `interactive.native.cancel`: fence. Reply: cancelled or error. May cancel an
  operation while challenge preparation or proof/activation is pending. It
  matches the exact original primary/session/fence and cannot stop another
  generation or client. Cancellation is idempotent for the last retired fence.
- `interactive.native.cancelled`: fence. Returned only after backend drain.

## Ownership and failure

The dispatcher reserves each transition before suspension and checks the exact
current active primary/session and durable Control grant before and after bridge
work. The enrolled session key comes from the same durable admission snapshot;
absence or mismatch rejects. The runtime factory must obtain approved surface
geometry, display, generation and original deadline from the current runtime
owner; request geometry/keys/deadlines cannot supply these facts. The coordinator's
reader revalidates runtime and durable authority throughout its lifetime.
The Agent composition constructs that reader from its reconciled store. Platform
services supply only the acknowledged runtime snapshot and an inert backend
factory. The runtime display token and visible-menu generation must match
admission on both sides of the read. The visible activity receipt revision and
authenticated menu publication revision must each be positive and remain current
within their own counter. They are independent: showing/clearing Control advances
activity, and changing the selected display advances publication. They must not
be ordered against each other. The activity receipt must remain bound to the
exact current installed lease, session and acknowledged surface.
The complete durable admission and runtime snapshot must still remain unchanged
around construction and on later authority reads; a zero revision, wrong
generation or stale lease/session/surface binding is rejected. Backend construction must not create
credentials or listeners, and admission is checked again after construction.

A bridge owns one pending factory task, one verifier/coordinator, and one drain.
Stop, primary close, local session termination, and surface selection retire it.
Cancellation fences first, joins pending construction and backend drain, and
suppresses late challenge/ready results. No replacement starts until drain ends.
A stale operation's compensation must retire only that operation; it cannot close
a later replacement. Parallel proofs fail without canceling the reserved proof.
New generation counters never roll back within a primary connection.

The client reserves its waiter before transport send, accepts only correlated
closed replies, and checks the original Control/surface before committing them.
Each wait is bounded. Cancellation/timeout fences pending replies, sends exact
native cancel if primary is still available, and drains the native owner. Late
closed replies may be decoded and discarded but cannot revive the renderer.
Session End and primary invalidation retire waiters before awaiting transport or
cleanup. Surface selection cancels the native operation before changing capture.

Each local client enrollment owner retains a unique opaque reservation identity.
Its cancellation and post-join compensation may retire only the primary slot
reserved by that identity. A former owner cannot cancel a replacement, including
one on the same Control surface. The reservation is local state and is not a
wire field, signing input, or additional grant.
A caller joining an already running cancellation publishes completion of that
same local reservation before returning. A completed cancellation cannot leave
the replacement slot marked busy while another joiner finishes returning.

For a native App/Window/Desktop replacement, the client first fences local
keyboard and pointer input, cancels pending native preparation, and drains the
current Moonlight renderer, TLS identity and enrollment. It then uses the
existing authenticated surface selection, including input reset, prepared
capture, replacement clean frame and acknowledgement. The client keeps input
locally disabled after that acknowledgement. A fresh native preparer enrolls
under the replacement descriptor and the same Control grant and original
session deadline; the host creates a new per-operation capture context and
native generation. Only that new renderer's correlated native presentation
receipt can restore input. A failed selection or missing replacement preparer
closes the local product and cannot revive the old native operation. Focused
region remains unavailable for native selection. No new primary message,
pairing step, approval or signature is introduced.

The indexed wire fixtures refer to the existing coordinator crypto vector. Their
public non-certificate bytes exercise wire shape and fake backends only. The real
certificate validator must reject those bytes. The existing enrollment signature
is unchanged; no new application authentication or approval signature is added.

## Native presentation acknowledgement

`interactive.native.present.request` is a closed Control-primary request with
fence, challengeMessageID, nativeGeneration (positive JSON-safe integer),
encodedWidth (320…8192) and encodedHeight (240…8192). It reports a frame already
presented by the exact live native client owner. Connected/decoded callbacks alone
cannot send it. The fence and challenge must match the active enrolled operation.
Only one native renderer generation may be acknowledged per enrollment; replacement
requires retirement and new enrollment. Concurrent transitions cannot overlap.

`interactive.native.present.receipt` correlates to that exact request and contains
fence, challengeMessageID, nativeGeneration, encodedWidth, encodedHeight,
capturePixelWidth, capturePixelHeight (1…32768), logicalWidthPoints and
logicalHeightPoints (positive UInt32), and inputAdmitted (Boolean). The host obtains the logical size from the
acknowledged runtime snapshot and the capture pixels from fresh actual backend
evidence for its own operation. No client supplied capture/logical geometry,
physical display ID or host monotonic timestamp is transmitted.

The coordinator checks current durable/runtime authority, exact backend activity,
operation/dimensions and sample freshness before returning evidence, rechecking
authority and activity across suspension. Cancellation, geometry/authority loss
or retirement prevents a late receipt. Pending/stale capture cannot produce a
receipt. Bridge and dispatcher preserve exact primary, challenge, session, fence,
registered key and transition reservation around every asynchronous operation.

This receipt confirms the correlated host observation. Only inputAdmitted true
confirms installation of the independently revalidated runtime posting permit.
The client input gate additionally requires the current foreground renderer owner
to consume that exact receipt and geometry; displaying a frame alone is insufficient.
Existing session authentication, enrollment signature bytes and cryptographic
vectors are unchanged. Both records are in the sole fixture manifest.

### Presentation input admission

The closed presentation receipt additionally requires inputAdmitted (Boolean).
False is an observation only. True means the exact current backend installed a
local posting primitive into the already admitted Control runtime. It does not
create a new grant, extend either deadline or authorize other sessions/surfaces.
The coordinator joins durable authority before and after local installation and
revalidates current backend activity and fresh sample before returning. Failure or
cancellation retires the backend and revokes its posting primitive. The client
must not enable input from a false, missing, stale or mismatched receipt.
