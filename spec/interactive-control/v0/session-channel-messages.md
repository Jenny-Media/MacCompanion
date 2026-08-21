# Interactive Control session and channel messages v0.1

Status: normative closed JSON schemas. The authority and cryptographic rules in `security-profile.md` remain mandatory; decoding these messages never grants Control.

## Primary session-control flow

Session messages use the capability protocol v0.1 command envelope and its 65,536-byte strict-JSON bound.

1. `interactive.session.request` is an original request with null `correlationID`. Its body contains `initialSurface: "desktop"` and a sorted unique `effects` array. v0.1 always begins on Desktop; application/window/focus selection occurs only after the initial descriptor is acknowledged.
2. `interactive.session.approvalRequired` correlates to the request. Its body contains every field in `interactiveApprovalSigningInput`: host ID/fingerprint, client ID, primary connection ID, request and approval IDs, 32-byte challenge, authorization/grant/policy revisions, host-selected display ID, Desktop surface, effects, and issued/expiry wall times. The interval is at most 60 seconds. The client verifies correlation and all current identities before requesting user presence.
3. `interactive.session.approve` correlates to the approval-required message and contains only the approval ID and raw 64-byte P-256 approval signature.
4. `interactive.session.accepted` correlates to the approval proof and is sent only after atomic proof consumption and creation of one starting session. It contains the session ID, authorization epoch, session wall-time expiry, and distinct input/media offers.

After acceptance, the client may send one original
`interactive.session.end` containing only the exact session ID and
authorization epoch. The host admits it only for the authenticated device and
primary connection that own the current session. It clears remote admission
before awaiting idempotent runtime teardown, invalidates both role channels and
unused credentials, releases input, stops capture, purges queued media, and
blanks retained output. Only after that complete safety boundary may it return
the correlated `interactive.session.ended` containing the same session ID and
epoch plus a nonnegative safe-integer diagnostic wall end time. The client
closes its role owners as soon as the end request is enqueued, but it must not
claim host teardown success before the exact correlated reply. A mismatched,
stale, skipped, duplicate, or cross-connection end is a protocol failure and
never terminates another device's session.

Each offer contains a channel UUID, fixed role, independent random 32-byte credential, issuance time, and expiry no more than 30 seconds later and no later than session expiry. Input and media channel IDs and credentials must differ. Wall time is explanatory; host-monotonic deadlines are authoritative and can be shorter.

The host permits at most one approval-required/starting request and one active session. Request replay, correlation mismatch, a changed primary connection, grant/policy/epoch change, local suspension, approval timeout, or unavailable visible menu app produces no accepted session. Session creation and both credential authorities occur in one host-owned non-suspending transition.

The host primary-session owner synchronously orders an exactly-once teardown notification to its Interactive authority when authentication fails, the connection closes, or liveness expires. That notification invalidates every pending approval, active session, and unused role credential owned by the primary connection before the connection is considered fully released.

## Secondary-channel handshake

Each offered credential is used on a new pinned TLS 1.3 connection to the exact endpoint and port selected for its owning authenticated primary connection. A client must not re-resolve, re-race, infer, or substitute a route for either role channel. Before role framing, peers exchange the separate five-field handshake envelope: `version`, `messageID`, nullable `correlationID`, closed `kind`, and `body`. `interactive.channel.hello` is the only original message; every later message correlates to its immediate predecessor.

Every secondary-channel handshake message is framed by an unsigned four-byte big-endian length followed by exactly that many strict UTF-8 JSON bytes. The length must be in `1...4,096`. Receivers read the four-byte length and then exactly the declared body; they must not read beyond an accepted message into immediately following role traffic. A zero, oversized, truncated, malformed, or trailing-byte handshake frame closes the role channel and consumes no authority. After `interactive.channel.accepted`, input traffic uses the same four-byte big-endian length framing with a strict-JSON body bound of `1...65,536`; media traffic begins directly with the self-framing 96-byte record header in `media-channel.md` and has no outer length prefix.

1. `interactive.channel.hello`: channel ID/role, client ID, primary connection ID, Interactive Control session ID, authorization epoch, and 32-byte client nonce.
2. `interactive.channel.challenge`: same channel ID/role, host ID/fingerprint, and 32-byte host nonce.
3. `interactive.channel.prove`: channel ID and 32-byte `clientProof`.
4. `interactive.channel.accepted`: channel ID/role and 32-byte `serverProof`.

The hello and challenge reconstruct the exact transcript in `security-profile.md`. The client verifies the TLS pin, host ID/fingerprint, channel ID/role, correlation chain, and server proof. The host revalidates the live primary connection, client/session/epoch, role, unused monotonic deadline, and client proof immediately before atomic consumption. Any invalid or duplicate message destroys the credential and closes the connection. Input JSON or media records arriving before accepted state are protocol violations.

Canonical fixtures cover the full signing transcript inputs and exact session
end request/reply. Unknown keys, kinds, roles, malformed base64url,
noncanonical UUIDs, unsafe integers, missing correlation, or role/channel
mismatch fail closed before authority lookup.

After the application-primary session is authenticated, the first Desktop uses
the closed command-channel exchange in `initial-surface-activation.md`. Later
Adaptive Remote Surface selection and acknowledgement use
`surface-control-messages.md`. Host-monotonic descriptor lifetimes never cross
devices, and media-channel bytes alone never authorize input resumption.
