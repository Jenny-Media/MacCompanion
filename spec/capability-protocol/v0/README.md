# Mac Companion Capability Protocol v0.1

Current normal VNC development composition: [standalone Screen Sharing client](direct-screen-sharing.md).
The paired application protocol below is retained for compatibility and remains
normative when that historical profile is used.

Status: Stage 0 executable mini-RFC. This file is normative for the bundle-independent trust-kernel slice. Later changes require fixture-first review and an explicit compatibility decision.

## 1. Scope

v0.1 defines:

- TLS transport and application framing
- Closed JSON envelopes and bounded decoding
- Session description and one current status snapshot
- Device authorization and operation state machines
- Exact durable operation binding and execution-claim fencing in `operation-binding.md`
- Restricted RFC 8785 canonical parameters and closed schema validation in `canonical-json.md`
- Provider-neutral low-risk admission, execution claim, and safe result boundary in `provider-execution.md`
- One-shot operation user-presence signatures in `operation-approval.md`
- Closed invoke, approval, status, result, and cancellation messages in `message-schemas.md`
- Authenticated pre-ingress command composition in `operation-command-orchestration.md`
- Single-owner TLS/application-authentication/status/Act routing in `primary-session-composition.md`
- Role-safe shared-listener first-frame routing and pairing pump composition in
  `host-listener-ingress.md`
- Client-side pinned-TLS/application-authentication publication in `client-primary-authentication.md`
- Connection-bound, non-authorizing configured-route observation in
  `authenticated-route-observation.md`
- Client-side QR-secret/transcript/SAS/final-identity composition in `client-pairing.md`
- Client-side scan/accept/pin/SAS/durable-publication presentation in `client-pairing-presentation.md`
- Client-side private-key custody and atomic paired-host publication in `client-identity-publication.md`
- Exact-host saved Mac selection and local removal in `client-mac-library.md`
- Local device grant review and Interactive Control warning presentation in `local-authority-presentation.md`
- Privacy-limited paged granted-capability discovery in `capability-discovery.md`
- Independent schema-driven client Act orchestration and presentation in
  `client-operation.md`
- Connection-scoped Observe/Act/Control reply correlation and routing in
  `client-primary-router.md`
- Conservative host-status and privacy-limited self-audit client orchestration
  in `client-observe.md`
- Privacy-limited `audit.readSelf` pagination with explicit retention/drop gaps
  in `message-schemas.md` and `spec/audit/v0/README.md`
- Atomic immutable registry/provider publication and replacement in
  `registry-publication.md`
- One bounded desired-state macOS provider candidate in `native-audio-mute-provider.md`
- Paired VNC desktop transport in `vnc-desktop-tunnel.md`
- Authorization-epoch fencing
- Pairing transcript construction
- Replay and timeout profiles
- Stable v0 error codes

It does not define Interactive Control media/input framing, additional native
provider implementations, TCC behavior, or Apple bundle identity. The
executable SQLite schema and provider-neutral authority are separate profiles
consumed by this trust kernel; platform layers cannot weaken it. The client Act
approval and presentation boundary is defined in `client-operation.md`.

## 2. Transport and framing

- The transport is TCP protected by TLS 1.3 through Network.framework.
- TLS 0-RTT is disabled. Authentication and state-changing messages are never accepted as early data.
- The client pins the Mac Companion host-identity certificate fingerprint established during pairing. A route, DNS name, Bonjour record, VPN, or tailnet identity never replaces this pin.
- Each application frame is `length || payload`, where `length` is one unsigned 32-bit big-endian integer and `payload` is one UTF-8 JSON object.
- `length` must be `1...65_536`. Zero, a larger value, truncated payload, trailing bytes inside a frame, invalid UTF-8, duplicate JSON keys, and a non-object root are fatal protocol errors.
- One TLS connection multiplexes logical `command` and `events` channels through the envelope `channel` field. At most 32 command requests may be awaiting replies. Event messages carry a body-level monotonically increasing sequence.
- Interactive Control uses separately authenticated channels after capability authorization and is outside this framing profile.

The exact SPKI pin and connection-role admission boundary are defined in [`transport-security.md`](transport-security.md); key custody, same-key renewal, and explicit identity-loss recovery are defined in [`host-identity-lifecycle.md`](host-identity-lifecycle.md). Security/Network.framework constructors are compile-tested, while final signed custody, live callback ordering, and physical route behavior remain platform gates.

## 3. Envelope

Every payload is a closed object with exactly these fields:

| Field | Type | Rule |
| --- | --- | --- |
| `version` | object | Exactly `{ "major": 0, "minor": 1 }` for this profile |
| `messageID` | string | Lowercase canonical UUID, unique in the connection replay window |
| `correlationID` | string or null | Request `messageID` for a reply/error; null for an original request/event |
| `channel` | string enum | `command` or `events` |
| `kind` | string | ASCII, 1–96 bytes, registered by this specification |
| `sentAtUnixMilliseconds` | integer | Non-negative signed 64-bit diagnostic time; never the sole replay or expiry authority |
| `body` | object | Closed schema selected by `kind` in `message-schemas.md` |

Unknown envelope fields, missing fields, duplicate keys, unknown `kind`, and a major-version mismatch are rejected. Every listed envelope field is required, including nullable `correlationID`. A client may accept a higher minor version only after negotiation and only for kinds and optional fields explicitly advertised by both peers. v0.1 defines no optional unknown-field behavior. The closed v0.1 kind registry and every body schema are normative in `message-schemas.md`.

## 4. Decoder bounds

Before allocating untrusted collections, implementations enforce:

| Bound | v0.1 value |
| --- | --- |
| Framed JSON payload | 65,536 bytes |
| JSON nesting | 12 container levels; envelope root is level 1 and every contained object or array adds 1 |
| Members per object | 64 |
| Items per array | 128 |
| General UTF-8 string | 4,096 bytes |
| Display name | 128 bytes |
| Identifier or enum | 96 ASCII bytes |
| Error safe arguments | 16 members, strings at most 256 bytes |
| In-flight command requests | 32 per connection |

All JSON integers must be within the interoperable safe-integer range `-9_007_199_254_740_991...9_007_199_254_740_991` in addition to their field-specific bounds. Non-finite numbers and floating-point values are not used by the v0.1 trust kernel. Durable counters must fail closed before exceeding the positive safe-integer maximum; v0.1 does not encode larger values as JSON numbers.

## 5. Connection timing and replay

- TCP connect timeout: 10 seconds.
- TLS plus application-authentication timeout: 10 seconds after TCP connection.
- Ordinary command response timeout: 30 seconds unless the operation returns a durable operation reference.
- Keepalive is sent after 15 seconds without traffic; connection liveness expires after 45 seconds without authenticated traffic.
- A connection retains the last 4,096 received `messageID` values. A duplicate is rejected as `protocol.duplicateMessage`; this window is connection-scoped and intentionally not durable.
- Every state-changing request additionally carries a durable operation ID or single-use challenge ID. Connection message IDs never provide durable idempotency.
- Pairing sessions expire after 5 minutes or 5 failed proofs and are atomically single-use.
- Approval challenges expire after 60 seconds, are atomically single-use, and are invalid after an epoch, grant, policy, provider-generation, execution-revision, authenticated-session, or protocol change.
- Durable operation IDs and their terminal binding are retained for 30 days, subject to a per-device maximum of 10,000 records. Hitting the quota rejects new operations rather than evicting a live or nonterminal record.
- Within one boot, security deadlines use a monotonic clock captured alongside diagnostic wall time. A restart invalidates boot-scoped challenges and authenticated sessions.

Foreground reconnect treats the QR or saved endpoint order as preference, never identity. A dial round starts candidate 0 immediately and each of the remaining at 250-millisecond intervals, up to the eight-candidate schema limit. Every attempt independently applies the 10-second TCP and 10-second TLS/application-authentication deadlines and the same required host fingerprint. The first candidate to complete fingerprint verification and application authentication wins; all other attempts are cancelled. A route that connects but fails the pin is not successful and cannot influence authorization.

After a round is exhausted, retry uses base delays of 0.5, 1, 2, 4, 8, 15, and 30 seconds, capped at 30 seconds, with independently injected 0.8–1.2 jitter. Foreground entry, restored network reachability, or a changed candidate set resets the failed-round counter and permits an immediate round. The iOS application reconciles foreground truth at both `willEnterForeground` and `didBecomeActive`, because release composition may start after the earlier notification. Actual application background entry or network loss cancels pending dials and closes the foreground connection. A temporary UIKit `inactive` state caused by LocalAuthentication or other system UI is still foreground for this policy and MUST NOT close the connection carrying its approval challenge. Explicit Disconnect never auto-reconnects until explicit Resume. A user-selected Reconnect may rebuild the network owner only from the same protected paired-host and configured-route stores; it cannot add, repair, or replace trust or grants. Suspension, revocation, stale credentials, or another terminal authentication denial waits for user action rather than retrying as a route failure.

The bundle-independent dial-round executor passes the round's same immutable 32-byte fingerprint to every route attempt. An adapter may report success only after pin verification and application authentication on that connection. The executor cancels remaining attempts after the first authenticated winner or terminal authentication denial, closes every authenticated result that arrives after cancellation, and closes and rejects an authenticated result whose endpoint does not exactly match its planned attempt. Adapter-result mismatch is fail-closed and is never converted into a transient route retry.

One bundle-independent reconnect owner applies external foreground, network, candidate-replacement, disconnect, and resume events to that state machine and owns the exact active round and authenticated route. It closes the route whenever policy emits `closeConnection`, cancels only the active round whenever policy emits `cancelPendingDials`, maps exhaustion to the state machine's bounded backoff, and maps authentication denial or an invalid adapter result to `requiresUserAction`. Invalid runtime time or jitter input also fails closed rather than leaving a dialing phase with no owner.

Status freshness is independent of socket state. At receipt, the client subtracts both the host-reported age (`response.sentAt - snapshot.observedAt`) and the full measured request round trip from `validForMilliseconds`, anchoring the conservative remainder to its monotonic clock. The observation becomes stale at the exact resulting deadline even if connected. Connection loss labels any retained observation `unreachable` with its original observation time; it never relabels the value live or infers sleep.

## 6. Application authentication

Host and client identity keys use P-256 signing keys through CryptoKit/Security. The host certificate presents the host identity public key; its fingerprint is SHA-256 over the certificate's DER SubjectPublicKeyInfo. `crypto-profile.md` defines every byte encoding, signature input, and proof construction; prose in this section is a sequence summary only.

After pinned TLS completes:

1. Client sends `auth.hello` with client ID, 32 random client-nonce bytes, and supported protocol range.
2. Host sends `auth.challenge` with 32 random server-nonce bytes, a random connection ID, selected version, and observed host-certificate fingerprint.
3. Client signs the exact `authSigningInput` from `crypto-profile.md` with its session identity key and sends `auth.proof`.
4. Host verifies the stored client key and current device state/epoch, then replies with `session.describe.response` on success.

A terminating TLS proxy cannot produce the pinned host certificate; a transparent byte relay does not gain Mac Companion identity or authorization.

## 7. Pairing transcript

The local Mac creates a random pairing ID, 32-byte one-time secret, 5-minute expiry, endpoint candidates, selected protocol, and host fingerprint. The QR encodes those fields with base64url bytes and is never logged.

The phone first pins the QR fingerprint, then sends `pairing.begin` with the pairing ID, client ID, both public keys, and its 32-byte nonce but no secret proof. The host validates only session existence, expiry, attempt quota, and field bounds before returning `pairing.challenge` with its 32-byte nonce and selected version. Only then can both sides build the exact transcript from `crypto-profile.md`. The phone sends `pairing.prove` containing both the HMAC secret proof and the session-key transcript signature. After verifying both, the host sends `pairing.pendingApproval` with the transcript-derived authentication string. Both devices display that string, and local approval binds the client name, client ID, public-key fingerprints, and transcript digest.

The remote wire carries no client-supplied device name. During the verified SAS
review, the Mac user chooses a local display name. The local decision binds
that name, client ID, both public-key fingerprints, and transcript digest. The
agent atomically consumes the pairing session and stores the locally chosen
name, device keys, initial authorization, grant revision 1, policy revision,
authorization epoch 1, and minimal audit event. The remote-desktop MVP uses
the locally disclosed `remoteDesktop` pairing profile: the Mac's approval
explicitly allows screen viewing, pointer, keyboard, and eligible text input.
That single transaction stores `activeGranted` and exactly
`maccompanion.interactive.control`; it grants no Act-provider capabilities.
The legacy `monitorOnly` profile remains readable and testable and stores
`activeMonitorOnly` with no grants. Existing records are never expanded by
an update or reconnect. A legacy device needs one explicit local Control
upgrade, using the existing reviewed expansion contract.

`pairing.complete` carries the actual committed initial state, either
`activeGranted` or `activeMonitorOnly`, with epoch and grant revision 1.
Exact-key pairing recovery may reproduce either unchanged initial record;
for `activeGranted` it also requires exactly the fixed Control grant. It
cannot recover changed, suspended, or revoked authority. The transcript,
HMAC, session-key signature, SAS and recovery signature encodings remain
unchanged and use the existing golden cryptographic vectors. A durable
pairing grant does not itself create a live session: current session
approval, visibility, OS permissions, revocation and input fences still apply.

## 8. Device authorization state machine

The normative states are:

- `unpaired`
- `pairingPending`
- `activeMonitorOnly`
- `activeGranted`
- `suspended`
- `revoked`

Legal transitions are exactly those in `docs/protocol-outline.md` under **Device authorization lifecycle**. Every grant change, suspend, resume, or revoke increments the authorization epoch; every grant-set change or reviewed resume also increments the grant revision. Re-pairing creates a new client/device ID; `revoked` never returns to an active state.

`Suspend device` closes all device transports and subscriptions, ends Interactive Control, invalidates approvals/channels, and prevents queued work from claiming execution. `Revoke` does the same and permanently removes grants after its durable transaction. A failed durable revoke activates the emergency global deny latch specified by the architecture.

## 9. Operation state machine

The normative states are:

- `pendingPolicy`, `denied`, `awaitingApproval`, `expired`, `queued`, `running`
- `cancelRequested`, `succeeded`, `failed`, `cancelled`, `outcomeUnknown`

Legal transitions are exactly those in `docs/protocol-outline.md` under **Operation state machine**. Terminal states are `denied`, `expired`, `succeeded`, `failed`, `cancelled`, and `outcomeUnknown`.

Policy is checked on receipt, durable admission, and execution claim. A queued operation whose recorded authorization epoch, grant revision, policy revision, provider generation/execution revision, or required host state differs at execution claim transitions to `failed` with `operation.authorizationRevoked` before provider code is called.

The closed command flow is fixture-backed. `operation.invoke` carries one durable
operation ID, registered capability ID, and native restricted-JSON parameter
object. It receives either a durable status, a one-shot
`operation.approvalRequired`, or an error. `operation.approve` carries only the
approval ID and fixed-width approval signature. `operation.status.request`
re-observes durable state, while `operation.cancel` requests the legal
cancellation transitions. Every successful command reply uses the same closed
`operation.status.response`; live result data is allowed only with
`succeeded` and is not promised on replay. Exact fields and correlation rules
are normative in `message-schemas.md`.

The official client owns this flow through the independent, fence-bound state
machine in `client-operation.md`. It validates schema-driven parameters before
invoke, discards late user-presence signatures, and can query the same durable
operation ID after an ambiguous delivery; it does not require or infer an
Interactive Control session.

## 10. `session.describe.response`

`body` is a closed object. Every listed field is required:

| Field | Type | Rule |
| --- | --- | --- |
| `hostID` | UUID string | Stable host identity |
| `deviceID` | UUID string | Authenticated device |
| `deviceState` | enum | `activeMonitorOnly` or `activeGranted`; suspended/revoked devices cannot authenticate |
| `authorizationEpoch` | safe non-negative integer | Current device fence |
| `grantRevision` | safe non-negative integer | Current device grant revision |
| `policyRevision` | safe non-negative integer | Current host policy revision |
| `hostState` | enum | Defined in section 12 |
| `features` | array | Sorted unique registered feature strings, maximum 32 |
| `serverTimeUnixMilliseconds` | int64 | Diagnostic wall time |

The response envelope has `channel: "command"`, `kind: "session.describe.response"`, and correlates to `auth.proof`.

## 11. `status.snapshot.response`

`body` is a closed object. Every listed field is required:

| Field | Type | Rule |
| --- | --- | --- |
| `hostID` | UUID string | Must match authenticated session |
| `resourceID` | string enum | Exactly `host.status` |
| `generation` | UUID string | Changes whenever the status revision sequence is reset |
| `revision` | safe non-negative integer | Strictly increases within `generation` |
| `observedAtUnixMilliseconds` | int64 | Non-negative observation wall time |
| `validForMilliseconds` | uint32 | `1...60_000` |
| `hostState` | enum | Defined in section 12 |
| `system` | object | Closed system overview below |

`system` is closed and every listed field is required:

| Field | Type | Rule |
| --- | --- | --- |
| `osName` | string | 1–32 bytes; v0 value `macOS` |
| `osVersion` | string | 1–32 bytes |
| `osBuild` | string | 1–32 bytes |
| `uptimeSeconds` | safe non-negative integer | Observation, not an expiry clock |
| `cpuUtilizationBasisPoints` | uint16 | `0...10_000` |
| `memoryTotalBytes` | safe non-negative integer | Greater than zero |
| `memoryUsedBytes` | safe non-negative integer | At most total |
| `storageTotalBytes` | safe non-negative integer | Greater than zero; system data volume aggregate only |
| `storageAvailableBytes` | safe non-negative integer | At most total |
| `powerSource` | enum | `ac`, `battery`, or `unknown` |
| `batteryLevelPercent` | uint8 or null | `0...100`; null when unavailable/not applicable |

No process, app, window, public-IP, screenshot, username, filesystem path, volume name, or third-party data appears in this response.

## 12. Host states

Wire host states are:

- `userSessionActive`
- `userSessionLocked`
- `otherConsoleUserActive`
- `serviceStoppingForLogout`
- `hostPreparingForSleep`

`unreachable` is client-derived and is never sent by the host. Exact same-UID,
on-console, completed-login Quartz facts map to `userSessionActive` for the
logged-in MVP. When those Quartz facts are unavailable to the background Agent,
an exact same-UID primary logged-in console identity from SystemConfiguration
provides the fallback; any contradiction, switched user, missing fallback, or
explicit incomplete login maps to `otherConsoleUserActive`. Public APIs do not
distinguish screen lock, so v0.1 does not claim a separate
`userSessionLocked` signal.

## 13. Stable v0 errors

Errors use `kind: "error"` and a closed body `{ code, retry, safeArguments }`; all three fields are required. `retry` is one of `never`, `afterUserAction`, `afterReconnect`, `afterApproval`, or `backoff`. `safeArguments` is a closed map with at most 16 registered ASCII keys of 1–64 bytes. Values are only a boolean, null, a safe integer, or a UTF-8 string of at most 256 bytes; arrays and nested objects are forbidden.

Initial codes:

- `protocol.invalidFrame`
- `protocol.unsupportedVersion`
- `protocol.unknownKind`
- `protocol.duplicateMessage`
- `protocol.boundsExceeded`
- `protocol.operationIDConflict`
- `auth.unknownDevice`
- `auth.invalidProof`
- `auth.deviceSuspended`
- `auth.deviceRevoked`
- `auth.staleEpoch`
- `pairing.expired`
- `pairing.invalidProof`
- `pairing.alreadyConsumed`
- `policy.denied`
- `policy.approvalRequired`
- `operation.authorizationRevoked`
- `operation.hostRestarted`
- `operation.outcomeUnknown`
- `operation.notFound`
- `operation.approvalNotFound`
- `provider.unavailable`
- `capability.registryChanged`
- `storage.securityUnavailable`
- `rateLimit.exceeded`

`safeArguments` never contains raw provider text, paths, secrets, app/window names, input, screen data, or network addresses.

## 14. Canonicalization

General operation parameter digests use the restricted RFC 8785 JSON Canonicalization Scheme in `canonical-json.md` over a closed, schema-validated JSON value. The exact request and authorization binding is specified by `operation-binding.md`. Pairing and application-authentication proofs use the explicit constructions in `crypto-profile.md` and do not depend on JSON member order. Passing canonicalization is necessary but not sufficient for Act admission: registry identity, grants, policy, approval when required, durable admission, and execution claim must all also succeed.

## 15. Authoritative fixtures

`spec/fixtures/manifest.json` is the only fixture index. Valid fixtures must decode, validate, re-encode, and canonicalize to the declared result. Invalid fixtures must fail with the declared stable error. Tests may load these files directly but may not copy them into a second mutable fixture corpus.
