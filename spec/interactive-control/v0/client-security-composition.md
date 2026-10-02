# Interactive Control client security composition v0.1

Status: normative for the bundle-independent client authority. Concrete Keychain, LocalAuthentication, TLS, socket, and application-lifecycle adapters remain platform work.

## Session approval

The client starts only from an authenticated primary binding containing the paired host ID and fingerprint, client ID, primary connection ID, authorization epoch, grant revision, and policy revision. It sends one Desktop-only `interactive.session.request`, admits each message ID once, and accepts only an approval challenge correlated to that request.

Before exposing the approval key, the client verifies that every primary-binding field is exact, that the challenge request ID is the original request ID, and that the host has neither changed nor broadened the requested effects. An injected platform signer must obtain fresh OS-backed user presence for this approval and return the fixed-width raw P-256 signature over the profile signing input. `interactive.session.approve` correlates to the exact approval-challenge message.

The client accepts a session only when `interactive.session.accepted` correlates to its approval proof and carries the same current authorization epoch. An error, replay, correlation mismatch, binding mismatch, signature failure, or deadline failure closes the authority and publishes no accepted session. The local approval wait is independently bounded to 60 monotonic seconds from challenge receipt; the host challenge expiry remains authoritative and may reject earlier.

## Role channels

The client creates independent input and media authorities from the accepted role-specific offers. Each authority:

1. binds the offered role, channel ID, credential, interactive-session ID, client ID, primary connection ID, authorization epoch, host ID, and host fingerprint;
2. completes TLS 1.3 with the paired host fingerprint and the exact intended channel role before sending authentication bytes;
3. correlates the challenge to its hello and verifies the exact role, channel, host ID, and host fingerprint;
4. derives the transcript digest and returns the role credential's client HMAC proof;
5. admits role traffic only after a correlated acceptance contains the exact server HMAC proof.

The unused-channel deadline is independently bounded to 30 monotonic seconds from TCP connection. The host offer expiry remains authoritative and may reject earlier. Credentials and transcript material are cleared when the channel becomes ready or closes. Any pin, role, binding, replay, correlation, proof, phase, or deadline failure closes both the role authority and its pinned-TLS admission authority; media or input traffic is never admitted on a partially authenticated channel.

Both role channels connect only to the endpoint and port that produced the owning authenticated primary connection. They may authenticate concurrently, but the client publishes neither live viewing nor live input until both are ready and the initial Desktop clean-media acknowledgement has completed. Failure, timeout, or loss of either role channel closes the other and requires a new Interactive Control session; reconnecting a role from an old accepted offer is forbidden. Primary replacement or loss synchronously closes both role channels before the old selection is released.

The initial screen owner publishes its pending acknowledgement state before
enqueueing the authenticated acknowledgement, because sending may suspend while
an exact correlated host reply arrives. Completion of the send cannot overwrite
that committed reply or resurrect a closed/replaced owner. Concurrent renderer
callbacks do not enqueue a second acknowledgement while the first is pending.
The local product likewise enters awaiting-acknowledgement before suspending on
that send. Only an exact clean-frame receipt starts this transition, and only
the committed host reply enables input. Send failure or invalidation stays
terminal. These local scheduling rules are recorded by the indexed
`client-initial-acknowledgement-ordering-v0.1.json` fixture; wire and signature
inputs remain unchanged.

Submitting authenticated Stop fences new input at the primary authority before
its send can suspend. The local product enters ending, blanks its renderer and
disables its input sender without prematurely closing established role sockets.
An incomplete role handshake is cancelled and cannot publish a late activation.
Its
media consumer continues strict validation under the existing exact session,
epoch and surface fences, then discards complete records without decoding,
rendering, acknowledgement or input authority. This bounded drain lasts only
until the correlated ended reply, end rejection, primary request timeout or
primary loss. Those terminal paths close both roles. The host's existing Stop
releases held input; ending does not send a late reset after the Stop request.
An ending session cannot resume, replace a surface, or reuse a role offer.
Malformed data or role loss still closes both roles immediately.

## Failed product retirement

Before constructing a live product, the client may capture a retirement action
for the exact accepted session and its owning primary channel. A terminal
product failure first disables local input, then submits the existing
`interactive.session.end` through that captured channel. The channel must still
be valid and hold the same accepted session ID and authorization epoch. A stale
action cannot use the currently selected channel to stop a replacement session.
An already pending end is not submitted again. Failure to submit does not claim
remote completion; existing primary loss and host expiry remain terminal gates.
Local navigation alone does not invoke this action. Observe and Act grants are
unchanged. No new wire message or approval/signature input is introduced.

The live failure screen uses terminal recovery text and removes keyboard and
surface controls. It cannot display the last active workspace detail as a claim
that viewing or input is still live. These rules are recorded in the indexed
`client-failed-product-retirement-v0.1.json` fixture.
