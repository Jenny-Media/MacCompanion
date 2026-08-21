# v0.1 Closed Message Registry

This file is normative. Every body is a closed JSON object, every listed field is required, and no other `kind` is valid in v0.1. Binary fields use the encodings in `crypto-profile.md`.

## Common scalar aliases

- `uuid`: lowercase canonical UUID text.
- `b64url16`, `b64url32`, `b64url64`, `b64url65`: unpadded base64url decoding to exactly 16, 32, 64, or 65 bytes.
- `fingerprint`: exactly 64 lowercase hexadecimal characters decoding to 32 bytes.
- `safeUInt`: JSON integer `0...9_007_199_254_740_991`.
- `timeMilliseconds`: JSON integer `0...9_007_199_254_740_991`.
- `version`: closed object `{ "major": safeUInt, "minor": safeUInt }`, each field additionally limited to `0...65_535`.

## Registry

| Kind | Channel | Direction before/after authentication |
| --- | --- | --- |
| `auth.hello` | command | client to host, after pinned TLS |
| `auth.challenge` | command | host to client |
| `auth.proof` | command | client to host |
| `session.describe.response` | command | host to authenticated client |
| `route.observation` | command | authenticated client to host |
| `route.observation.ack` | command | host to authenticated client |
| `pairing.begin` | command | unpaired client to host, after QR-pinned TLS |
| `pairing.challenge` | command | host to unpaired client |
| `pairing.prove` | command | unpaired client to host |
| `pairing.pendingApproval` | command | host to unpaired client |
| `pairing.complete` | command | host to newly paired client |
| `status.snapshot.request` | command | authenticated client to host |
| `status.snapshot.response` | command | host to authenticated client |
| `capability.registry.request` | command | authenticated client to host |
| `capability.registry.response` | command | host to authenticated client |
| `audit.list.request` | command | authenticated client to host |
| `audit.list.response` | command | host to authenticated client |
| `operation.invoke` | command | authenticated client to host |
| `operation.approvalRequired` | command | host to authenticated client |
| `operation.approve` | command | authenticated client to host |
| `operation.status.request` | command | authenticated client to host |
| `operation.status.response` | command | host to authenticated client |
| `operation.cancel` | command | authenticated client to host |
| `keepalive.ping` | command | either peer after authentication |
| `keepalive.pong` | command | peer replying to ping |
| `error` | command | either peer |

The `events` channel is reserved by the envelope but has no registered v0.1 kind. Sending a message on it is `protocol.unknownKind` until a later negotiated minor version defines a closed event schema.

## Pairing QR payload

The QR text is ASCII `maccompanion://pair/v0.1/<payload>`, where `<payload>` is unpadded base64url of the RFC 8785 canonical JSON bytes for this closed object. The complete QR text is at most 2,953 ASCII bytes; an encoder rejects a candidate set that would exceed that limit.

```text
version: exactly { "major": 0, "minor": 1 }
pairingID: uuid
oneTimeSecret: b64url32
expiresAtUnixMilliseconds: timeMilliseconds
hostFingerprint: fingerprint
endpoints: array of 1...8 endpoint objects
```

An endpoint object is closed and contains:

```text
kind: "bonjour" | "ipv4" | "ipv6" | "dns"
value: ASCII string 1...253 bytes with no whitespace, control, slash, query, or fragment character
port: integer 1...65_535
```

The only v0.1 DNS-SD service type is `_maccompanion._tcp` in `local.`. A `bonjour` value is exactly `<instance>._maccompanion._tcp.local.`, where `<instance>` is a lowercase ASCII DNS label of 1–63 bytes, begins and ends with an alphanumeric byte, and otherwise contains only alphanumeric bytes or hyphen. Product UI may display a friendly Mac name, but that name is not placed in discovery metadata.

An `ipv4` or `ipv6` value must equal the lowercase canonical text produced by `inet_ntop` for its parsed address; ports and IPv6 zone identifiers are not embedded in `value`. A `dns` value is a lowercase, non-rooted sequence of 1–63 byte ASCII A-labels with the same alphanumeric/hyphen rule and a total length of at most 253 bytes. Endpoint order expresses preference but never trust. The decoder rejects noncanonical JSON/base64url, duplicate candidates, an expired QR, or an oversized QR before opening a route; it never logs the payload and pins `hostFingerprint` before sending `pairing.begin`.

## Authentication bodies

### `auth.hello`

```text
clientID: uuid
clientNonce: b64url32
minimumVersion: version
maximumVersion: version
```

`correlationID` is null.

### `auth.challenge`

```text
connectionID: b64url16
serverNonce: b64url32
selectedVersion: version
hostFingerprint: fingerprint
```

`correlationID` equals the `auth.hello` message ID. The selected version must fall inside the offered range and the fingerprint must equal the pinned TLS certificate fingerprint observed by both peers.

### `auth.proof`

```text
signature: b64url64
```

`correlationID` equals the `auth.challenge` message ID. The signature input is defined in `crypto-profile.md`.

### `session.describe.response`

```text
hostID: uuid
deviceID: uuid
deviceState: "activeMonitorOnly" | "activeGranted"
authorizationEpoch: safeUInt, minimum 1
grantRevision: safeUInt, minimum 1
policyRevision: safeUInt, minimum 1
hostState: hostState
features: sorted unique feature array, maximum 32
serverTimeUnixMilliseconds: timeMilliseconds
```

Each feature is registered ASCII of 1–96 bytes. v0.1 registers
`audit.readSelf`, `interactive.control.v0.1`, and `status.snapshot`. This array is
not the message-kind registry and does not grant an operation; audit access
still requires the durable `audit.readSelf` grant, while operation availability
requires authenticated capability-registry and durable-grant state.
`correlationID` equals the `auth.proof` message ID.

### `route.observation`

```text
connectionID: b64url16
configuredRouteID: b64url16
routeClass: "privateDNS" | "privateNetwork"
observationSequence: safeUInt, minimum 1
```

`correlationID` is null. This is a non-authorizing authenticated heartbeat.

### `route.observation.ack`

```text
connectionID: b64url16
configuredRouteID: b64url16
routeClass: "privateDNS" | "privateNetwork"
observationSequence: safeUInt, minimum 1
validForMilliseconds: exactly 30_000
```

`correlationID` equals the accepted `route.observation` message ID. The exact
admission, replacement, freshness, and privacy rules are defined in
`authenticated-route-observation.md`.

## Pairing bodies

### `pairing.begin`

```text
pairingID: uuid
clientID: uuid
sessionPublicKey: b64url65
approvalPublicKey: b64url65
clientNonce: b64url32
```

`correlationID` is null. This message contains no secret or secret proof.

### `pairing.challenge`

```text
hostNonce: b64url32
selectedVersion: version, exactly 0.1
hostFingerprint: fingerprint
```

`correlationID` equals the `pairing.begin` message ID. The fingerprint must match the QR and pinned TLS certificate.

### `pairing.prove`

```text
secretProof: b64url32
signature: b64url64
```

`correlationID` equals the `pairing.challenge` message ID. Constructions are defined in `crypto-profile.md`.

### `pairing.pendingApproval`

```text
transcriptDigest: b64url32
authenticationString: string matching exactly [0-9A-F]{3}-[0-9A-F]{3}
expiresAtUnixMilliseconds: timeMilliseconds
```

`correlationID` equals the `pairing.prove` message ID. This message is informational; it grants no authority.

### `pairing.complete`

```text
hostID: uuid
deviceID: uuid
deviceState: exactly "activeMonitorOnly"
authorizationEpoch: exactly 1
grantRevision: exactly 1
policyRevision: safeUInt, minimum 1
hostFingerprint: fingerprint
```

`correlationID` equals the `pairing.prove` message ID. It is emitted only after atomic durable commit. A failed or timed-out local approval returns `error` and consumes or expires the pairing session according to the recorded reason.

## Status bodies

### `status.snapshot.request`

The body is exactly `{}`. `correlationID` is null.

### `status.snapshot.response`

```text
hostID: uuid
resourceID: exactly "host.status"
generation: uuid
revision: safeUInt
observedAtUnixMilliseconds: timeMilliseconds
validForMilliseconds: integer 1...60_000
hostState: hostState
system: systemOverview
```

`correlationID` equals the request message ID.

`hostState` is one of `userSessionActive`, `userSessionLocked`, `otherConsoleUserActive`, `serviceStoppingForLogout`, or `hostPreparingForSleep`.

`systemOverview` is closed:

```text
osName: exactly "macOS"
osVersion: UTF-8 string 1...32 bytes
osBuild: UTF-8 string 1...32 bytes
uptimeSeconds: safeUInt
cpuUtilizationBasisPoints: integer 0...10_000
memoryTotalBytes: safeUInt, minimum 1
memoryUsedBytes: safeUInt, at most memoryTotalBytes
storageTotalBytes: safeUInt, minimum 1
storageAvailableBytes: safeUInt, at most storageTotalBytes
powerSource: "ac" | "battery" | "unknown"
batteryLevelPercent: null | integer 0...100
```

## Capability discovery bodies

### `capability.registry.request`

```text
expectedRegistryGeneration: null | uuid
expectedGrantRevision: null | safeUInt, minimum 1
afterCapabilityID: null | registered capability identifier
```

All three fields are null for a first page or all three are nonnull for a
continuation. `correlationID` is null.

### `capability.registry.response`

```text
registryGeneration: uuid
grantRevision: safeUInt, minimum 1
policyRevision: safeUInt, minimum 1
capabilities: sorted unique array, maximum 4
nextAfterCapabilityID: null | capability identifier
```

The response contains only capabilities that are both currently registered and
durably granted to the authenticated device. `nextAfterCapabilityID`, when
nonnull, equals the last descriptor's capability ID. Each descriptor is at
most 12,000 encoded bytes and is closed:

```text
capabilityID: registered identifier, maximum 96 ASCII bytes
schemaVersion: integer 1...4_294_967_295
englishTitle: presentation string 1...128 UTF-8 bytes
englishSummary: presentation string 1...512 UTF-8 bytes
parameterSchema: closed schema object
resultSchema: closed schema object
effects: closed effectFacts object
```

Provider identity and execution revisions are intentionally omitted. Both
schemas have an object root. The schema union is exact:

```text
{ "type": "boolean" }
{ "type": "integer", "minimum": safeInt, "maximum": safeInt }
{ "type": "string", "maximumUTF8Bytes": integer 1...4096,
  "allowedValues": null | unique string array of 1...32 items }
{ "type": "array", "maximumItems": integer 1...128, "item": schema }
{ "type": "object", "properties": array of 0...32 property objects }
property := { "name": identifier 1...64 bytes, "required": bool,
              "schema": schema }
```

`effectFacts` contains every field below:

```text
dataAccess: "none" | "publicData" | "privateData" | "credentials"
changesLocalState: "none" | "reversible" | "irreversible"
mayDisruptUser: bool
invokesExternalService: bool
usesCredentials: bool
destructive: bool
requiresForegroundSession: bool
allowedWhileLocked: bool
cancellation: "notApplicable" | "bestEffort"
```

`requiresForegroundSession` and `allowedWhileLocked` cannot both be true.
`correlationID` equals the request message ID. Cursor and privacy semantics are
normative in `capability-discovery.md`.

## Self-audit bodies

Both messages use the authenticated command channel. The host derives the
requesting device from the authenticated principal and separately verifies its
durable `audit.readSelf` grant. No message body selects a device.

### `audit.list.request`

```text
beforeSequence: null | safeUInt, minimum 1
limit: integer 1...100
```

`beforeSequence` is an exclusive newest-first cursor. It is null for the first
page. `correlationID` is null.

### `audit.list.response`

```text
events: newest-first unique event array, maximum 100
nextBeforeSequence: null | safeUInt, minimum 1
oldestVisibleSequence: null | safeUInt, minimum 1
newestVisibleSequence: null | safeUInt, minimum 1
gaps: closed gap object
```

The visible bounds are both null or both nonnull. A nonnull next cursor equals
the final returned event sequence and means an older visible row exists. Empty
pages never imply complete history; clients inspect `gaps`.

Each event is closed and contains all fields below. Nullable fields are present
as JSON null rather than omitted:

```text
sequence: safeUInt, minimum 1
eventID: uuid
observedAtUnixMilliseconds: timeMilliseconds
scope: "selfDevice" | "host"
actor: "localUser" | "agent" | "menuApp" | "diagnosticCLI" |
       "pairedDevice" | "system"
code: one registered audit event code
correlationID: null | uuid
operationID: null | uuid
interactiveSessionID: null | uuid
capabilityID: null | registered capability identifier
policyRevision: null | safeUInt, minimum 1
authorizationEpoch: null | safeUInt, minimum 1
grantRevision: null | safeUInt, minimum 1
routeClass: null | "localDiscovery" | "directPrivateAddress" |
            "privateHostname"
surfaceKind: null | "desktop" | "application" | "window" |
             "focusedRegion"
outcome: null | "allowed" | "denied" | "succeeded" | "failed" |
         "cancelled" | "outcomeUnknown" | "expired" | "unavailable"
```

`host` scope permits only `host.availabilityChanged`,
`host.securityStateChanged`, or `audit.storageDegraded`, an `agent` or `system`
actor, and forbids correlation, operation, session, capability, device
revision, route, and surface fields. There is no subject-device field in either
scope.

The gap object is:

```text
prunedThroughSequence: null | safeUInt, minimum 1
droppedEventCount: safeUInt
```

Both values are already scoped to the authenticated requesting device plus
privacy-safe host rows. Exact storage, compaction, rate, and gap semantics are
normative in `spec/audit/v0/README.md`.

## Operation bodies

All operation messages use the authenticated command channel. The host applies
the admission, approval, digest, execution-claim, and result rules in
`operation-binding.md`, `operation-approval.md`, and `provider-execution.md`;
decoding a message never grants or executes authority by itself.

### `operation.invoke`

```text
operationID: uuid
capabilityID: registered ASCII identifier, 1...96 bytes
parameters: closed JSON object conforming to the registered capability parameter schema
```

`correlationID` is null. `parameters` is represented as native JSON, not a JSON
string or base64 wrapper. It uses the restricted canonical JSON value set in
`canonical-json.md`: null, boolean, safe integer, string, bounded array, or
bounded object; floating-point values are invalid. The root must be an object.
The host parses and validates it before policy evaluation, canonicalizes it for
the operation digest, and applies durable operation-ID idempotency. The initial
reply is one of `operation.approvalRequired`, `operation.status.response`, or
`error`, correlated to this message.

### `operation.approvalRequired`

```text
operationID: uuid
approvalID: uuid
operationDigest: b64url32
serverChallenge: b64url32
issuedAtUnixMilliseconds: timeMilliseconds, minimum 1
expiresAtUnixMilliseconds: timeMilliseconds, greater than issued time and at most 60_000 later
```

`correlationID` equals the `operation.invoke` message ID. The digest and
challenge are exactly those used by `operation-approval.md`. Reissuing the same
pending operation binding on the same authenticated primary connection returns
the same approval authority; it does not extend its lifetime.

### `operation.approve`

```text
approvalID: uuid
signature: b64url64
```

`correlationID` is null. The signature is the fixed-width P-256 approval-key
signature defined by `operation-approval.md`. The approval ID is one-shot; every
completion attempt consumes the in-memory authority whether verification or
the final durable admission succeeds. The reply is
`operation.status.response` or `error`, correlated to this message.

### `operation.status.request`

```text
operationID: uuid
```

`correlationID` is null. It observes only the authenticated device's durable
operation. The reply is `operation.status.response` or `error`, correlated to
this message.

### `operation.status.response`

```text
operationID: uuid
state: "pendingPolicy" | "denied" | "awaitingApproval" | "expired" | "queued" | "running" | "cancelRequested" | "succeeded" | "failed" | "cancelled" | "outcomeUnknown"
terminalCode: null | registered ASCII identifier, 1...96 bytes
result: null | closed JSON object conforming to the registered result schema
```

Every field is present, including both nullable fields. `terminalCode` is null
for every nonterminal state and may be populated only for a terminal state.
`result` may be non-null only for `succeeded`; it uses native restricted JSON
and its root must be an object. v0.1 does not durably retain successful result
bytes, so a later status replay normally has `result: null`; Observe is the
authoritative way to resnapshot desired state. This response may correlate to
`operation.invoke`, `operation.approve`, `operation.status.request`, or
`operation.cancel`.

### `operation.cancel`

```text
operationID: uuid
```

`correlationID` is null. Cancellation is idempotent and follows
`provider-execution.md`: queued work can become `cancelled`; running work first
becomes `cancelRequested`, and the provider hook remains best effort. The reply
is `operation.status.response` or `error`, correlated to this message.

## Keepalive bodies

### `keepalive.ping`

```text
pingID: uuid
```

`correlationID` is null. A keepalive never renews approval, presence, grants, or operation deadlines.

### `keepalive.pong`

```text
pingID: uuid
```

The `pingID` matches the request body and `correlationID` equals the ping message ID.

## Error body

```text
code: registered ASCII error code, 1...96 bytes
retry: "never" | "afterUserAction" | "afterReconnect" | "afterApproval" | "backoff"
safeArguments: map with 0...16 entries
```

`safeArguments` keys are registered ASCII of 1–64 bytes. Values are only null, boolean, safe integer, or UTF-8 string of at most 256 bytes. Arrays, objects, floating-point values, and unregistered keys are rejected. `correlationID` is the triggering message ID when known and null only for a connection-level framing failure that can still be represented safely.

Registered argument keys are closed per error:

| Error | Permitted `safeArguments` |
| --- | --- |
| `protocol.invalidFrame` | `reasonCode` string enum |
| `protocol.unsupportedVersion` | `supportedMajor`, `supportedMinor` safe integers |
| `protocol.unknownKind` | `kind` registered ASCII string |
| `protocol.duplicateMessage` | none |
| `protocol.boundsExceeded` | `field` registered ASCII string, `limit` safe integer |
| `protocol.operationIDConflict` | `operationID` uuid string |
| `auth.unknownDevice` | none |
| `auth.invalidProof` | none |
| `auth.deviceSuspended` | none |
| `auth.deviceRevoked` | none |
| `auth.staleEpoch` | none |
| `pairing.expired` | none |
| `pairing.invalidProof` | none |
| `pairing.alreadyConsumed` | none |
| `policy.denied` | `capabilityID` registered ASCII string |
| `policy.approvalRequired` | `capabilityID` registered ASCII string |
| `operation.authorizationRevoked` | `operationID` uuid string |
| `operation.hostRestarted` | `operationID` uuid string |
| `operation.outcomeUnknown` | `operationID` uuid string |
| `operation.notFound` | `operationID` uuid string |
| `operation.approvalNotFound` | none |
| `provider.unavailable` | none |
| `storage.securityUnavailable` | `recovery` string enum |
| `rateLimit.exceeded` | `retryAfterMilliseconds` safe integer |

`reasonCode` is one of `duplicateKey`, `invalidBody`,
`invalidCorrelation`, `invalidJSON`, `invalidScalar`, or `unknownField`.
`recovery` is `localRepair` or `reenableService`. Arbitrary provider/server
text is never substituted.
