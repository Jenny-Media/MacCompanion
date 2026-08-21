# Client Act operation composition v0.1

Status: normative for the bundle-independent iOS Act owner and its presentation boundary.

## Product boundary

Act is a first-class path. A paired client can discover and run its granted
bounded capabilities without starting, viewing, or holding an Interactive
Control session. Opening Remote Control never becomes a prerequisite for Act,
and an Interactive Control grant never substitutes for a capability grant.

The client displays only descriptors from one completely assembled granted
catalog. It never invents buttons from a compiled provider list, exposes an
arbitrary command or JSON editor, or treats provider presence as a grant. A
catalog is usable only while its registry generation, grant revision, and
policy revision remain the exact authenticated-session fence from which it was
loaded.

## Parameter draft

The official client renders the complete closed `CapabilitySchemaV1` value
set: Boolean, bounded integer, bounded string, closed allowed-value string,
bounded homogeneous array, and closed object with required and optional
properties. A new draft uses deterministic, schema-valid defaults where
possible:

- Boolean is `false`.
- Integer is zero when zero is in range, otherwise the nearest bound.
- A closed string uses its first registered value; a free string is empty.
- Array is empty.
- Object contains every required property recursively and omits every optional
  property.

The user can explicitly include or remove optional properties and add or
remove bounded array items. Before `operation.invoke` is constructed, the
client validates the complete native restricted-JSON object against the exact
descriptor parameter schema. Invalid or incomplete drafts never cross the
command boundary. Field names are schema identifiers and may be formatted for
presentation, but that formatting never changes the wire key.

## Effect review

Before invocation, the client presents the host-owned bounded title and
summary, target Mac, desired parameter values, and every applicable effect
fact. At minimum, private or credential data access, reversible or irreversible
local changes, user disruption, external-service use, credential use,
destructive behavior, foreground-session need, locked-use availability, and
cancellation support remain distinguishable.

Any capability that is destructive, irreversible, credential-using,
external-service invoking, or user-disruptive requires an explicit client-side
review action immediately before invoke. This review is a product guardrail,
not authorization: the host still applies policy and may require the separate
fresh approval signature below.

## One-operation owner

One client operation owner is bound at construction to all of:

- the durable paired host/client/device identities and pinned host fingerprint;
- the authenticated primary connection ID and v0.1 protocol version;
- the authenticated authorization, grant, and policy revisions;
- one complete granted catalog with the same grant and policy revisions; and
- one descriptor selected from that catalog plus its exact parameter schema.

Its public states are `idle`, `awaitingInvokeReply`, `awaitingUserPresence`,
`awaitingApprovalReply`, `observing`, `awaitingStatusReply`,
`awaitingCancelReply`, `deliveryUnknown`, `terminal`, `remoteRejected`, and
`invalidated`. Exactly one command can be pending. Every response must have the
registered reply kind, exact pending correlation ID, and exact operation ID. A
mismatch invalidates the owner and publishes no result.

`begin` creates one caller-supplied durable operation ID and sends one
`operation.invoke`. Its initial reply is the closed set from
`message-schemas.md`:

- A status is schema-checked with the invoked descriptor. A nonterminal status
  enters `observing`; a terminal status enters `terminal`.
- An approval challenge enters `awaitingUserPresence` only after its operation
  ID, wall-clock lifetime, and correlation are checked.
- A protocol error is presented only through its stable code, retry class, and
  registered safe arguments. Arbitrary remote text is never shown.

While observing, the owner can send `operation.status.request` or
`operation.cancel`. Cancellation remains best effort; the returned status is
authoritative. A transport loss or response timeout after any state-changing
send does not claim success or failure. The UI presents an unknown delivery
state and may reconnect and query the same durable operation ID. It never
creates a replacement operation ID automatically.

## Fresh approval signing

The approval signer boundary holds only the opaque separately protected
approval-key reference. It cannot access the session key or private-key bytes.
Every signing attempt uses `approveOperation` user-presence policy and the
exact `operationApprovalSigningInput` from `operation-approval.md`.

The owner constructs that input from its pinned host fingerprint, durable
client ID, exact authenticated primary connection ID, and the received
approval ID, digest, challenge, issue/expiry times, and negotiated version. It
checks expiry both before requesting presence and after the asynchronous signer
returns. The signature must be exactly 64-byte P-256 `r || s` before an
`operation.approve` frame is constructed.

Connection replacement, app background invalidation, explicit cancellation,
task cancellation, a changed catalog/session fence, expiry, or any protocol
failure increments the owner generation and makes an outstanding signer result
late. A late signature is discarded and never sent. Approval material exists
only in process memory and is cleared on every terminal or invalidated path.

## Presentation

The Approved Actions catalog is reachable from the paired-Mac experience
without entering Remote Control. It distinguishes loading, empty grant,
available actions, user-presence approval, queued/running/cancel-requested,
success, denial, expiry, failure, cancellation, and outcome unknown. Successful
result bytes are shown only after descriptor-schema validation and are treated
as transient; Observe remains the authoritative state snapshot.

The disposable simulator harness may inject typed descriptors, parameters,
and closed outcomes, but it has no socket, credentials, private keys, or
signing authority and labels that limitation visibly.

## Authenticated command-channel owner

One client Act channel owner is constructed only after the primary session has
published its authenticated client, host, device, connection, grant, and policy
facts. It receives an injected sender that can enqueue an already framed
authenticated command on that exact primary connection. The sender cannot
create identity, change grants, or interpret replies.

The owner states are `idle`, `loadingCatalog`, `ready`, `operating`, and
`invalidated`. It owns at most one catalog request or one operation command at
a time. Catalog loading uses `CapabilityCatalogAssemblerV1`, but the channel
owner additionally owns every page request message ID and requires exact
response correlation. It sends the continuation request only after the prior
page passes generation, grant, policy, cursor, ordering, bounds, and correlation
checks. No partial catalog is published. A correlated bounded error publishes
no catalog.

After a complete catalog is published, `beginOperation` constructs the
one-operation owner above from the same immutable paired-host and authenticated
session values. Only a capability in that catalog can begin. Incoming Act
frames are the closed set `operation.approvalRequired`,
`operation.status.response`, and `error`; the channel delegates their exact
correlation and schema validation to that operation owner. A returned approval
frame is enqueued on the same injected sender before approval is described as
submitted.

A send failure after constructing any operation command is delivery-ambiguous:
the operation owner retains the same durable operation ID and enters
`deliveryUnknown`, even when the failed send was a status or cancellation
request. The client may reconnect and create a new channel owner that queries
that same operation ID; it never automatically begins a replacement effect.
A catalog send failure has no state-changing authority and invalidates that
catalog load.

Primary-connection replacement, application backgrounding, explicit
disconnect, authentication loss, or channel failure invalidates the channel,
discards its catalog, and invalidates the active operation generation. It must
therefore win over an asynchronous user-presence signature or catalog page.
The application-primary router in `client-primary-router.md` is the only
component allowed to route these reply kinds into this owner; the disposable
harness does not instantiate it.
