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
