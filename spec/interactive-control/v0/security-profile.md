# Interactive Control security profile v0.1

Status: normative cryptographic construction. Closed messages are defined in `session-channel-messages.md`; host authority state remains a separate required layer.

This profile extends the primitive and ECDSA rules in `spec/capability-protocol/v0/crypto-profile.md`. Domain labels are exact ASCII, UUIDs use 16 RFC 4122 network-order bytes, `LP` is a four-byte big-endian length followed by bytes, and integers are unsigned big-endian. Approval signatures use ECDSA-P256-SHA256 over the complete input exactly once and raw 64-byte `r || s` encoding.

## Session-start challenge

`interactiveApprovalSigningInput` is:

```text
ASCII("MacCompanion/InteractiveApproval/v0.1") ||
LP(hostID.uuidBytes) ||
LP(hostFingerprint.32Bytes) ||
LP(clientID.uuidBytes) ||
LP(primaryConnectionID.16Bytes) ||
LP(requestID.uuidBytes) ||
LP(approvalID.uuidBytes) ||
LP(serverChallenge.32Bytes) ||
U64BE(authorizationEpoch) ||
U64BE(grantRevision) ||
U64BE(policyRevision) ||
LP(selectedDisplayID.uuidBytes) ||
U8(initialSurfaceCode) ||
U16BE(requestedEffects) ||
U64BE(issuedAtUnixMilliseconds) ||
U64BE(expiresAtUnixMilliseconds) ||
U16BE(selectedMajor) || U16BE(selectedMinor)
```

Initial surface codes are Desktop `1`, application `2`, window `3`, and focused region `4`. Effect bits are view `0`, pointer `1`, keyboard `2`, and text `3`. View is mandatory, no unknown bit is accepted, and text requires keyboard. Revisions are positive safe integers. The wall-time interval is positive and at most 60 seconds.

The immutable session consent profile selects exactly one paired key. The
legacy `freshUserPresence` profile uses the separate approval key after fresh
OS-backed user presence. The normal remote-desktop MVP uses `trustedDevice`:
its protected session/reconnect key signs the same complete challenge without
a biometric prompt. It requires the already recorded fixed Remote Control grant,
active device state, and all existing live-session admission checks. Pairing on
the Mac explicitly consents to reconnect without session confirmation. Existing
Control-enabled devices keep their keys and recorded grant; no key migration or
grant expansion occurs. Legacy monitor-only devices still need the one-time
local Control upgrade. The two profiles never fall back to the other key. They
are explicit product composition policies, not client-controlled wire fields;
both applications must use the same profile.

The host also records a boot-monotonic 60-second-or-shorter deadline; wall time is signed for cross-device explanation but never extends monotonic expiry.

Immediately before accepting the signature, the host verifies the profile-selected paired public key for that client, live primary connection ownership, host identity and pin, unused request and approval IDs, exact request effects/display/surface, current device/grant/policy revisions, current authorization epoch, protocol version, signature, and monotonic deadline. Success atomically consumes the approval and creates one starting session. Failure creates no session. Approval is not a bearer token and is not reusable after connection loss, epoch/revision change, timeout, or restart.

## One-time secondary-channel credential

After approval consumption, the host generates a uniformly random 32-byte credential and channel UUID for exactly one `input` (`1`) or `media` (`2`) role. It delivers the credential only over the authenticated primary connection and retains it only in boot-scoped memory. The unused lifetime is at most 30 monotonic seconds.

The channel handshake transcript is:

```text
ASCII("MacCompanion/InteractiveChannel/v0.1") ||
LP(channelID.uuidBytes) ||
U8(channelRole) ||
LP(hostID.uuidBytes) ||
LP(hostFingerprint.32Bytes) ||
LP(clientID.uuidBytes) ||
LP(primaryConnectionID.16Bytes) ||
LP(interactiveSessionID.uuidBytes) ||
U64BE(authorizationEpoch) ||
LP(clientNonce.32Bytes) ||
LP(hostNonce.32Bytes) ||
U16BE(selectedMajor) || U16BE(selectedMinor)
```

`channelTranscriptDigest = SHA256(channelTranscriptInput)`.

```text
clientProof = HMAC-SHA256(
  credential,
  ASCII("MacCompanion/InteractiveChannelProof/v0.1") || channelTranscriptDigest
)

serverProof = HMAC-SHA256(
  credential,
  ASCII("MacCompanion/InteractiveChannelAccept/v0.1") || channelTranscriptDigest
)
```

The TLS peer first matches the pinned host identity. The host issues its nonce only for the exact unused channel record and current primary connection/session/epoch. A valid client proof atomically consumes the credential for that one connection; only then does the host return `serverProof` and enable role framing. Invalid proof, second use, expiry, restart, primary-connection loss, session end, authorization change, role change, or channel-ID mismatch destroys the credential and closes the connection. Credentials never authenticate the primary capability channel and cannot cross input/media roles.

Neither proof is logged. Channel IDs may appear only in bounded diagnostics and are not authority after consumption. Implementations compare HMAC values without early-exit byte comparison and erase credential buffers on every terminal path where the platform permits.

## Golden vectors

`spec/fixtures/crypto/interactive-v0.1.json` contains conformance-only approval key material, exact approval/channel inputs, hashes, both HMAC proofs, an approval signature, and a trusted-device session-key signature over the same exact challenge input. Cross-key rejection is required. These public values must never ship as product credentials. Exact input/digest/HMAC parity and signature verification are required before enabling Interactive Control security code.
