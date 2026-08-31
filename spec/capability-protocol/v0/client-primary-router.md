# Client Primary Command Router v0.1

Status: normative bundle-independent client composition profile.

## Scope

One router owns application-command request/reply correlation after one client
primary connection has completed pinned TLS and application authentication. It
does not authenticate, choose a network route, decode a path's body, hold a
private key, infer a grant, or create Interactive Control channel authority.

The router binds one immutable authenticated client, host, device, and
connection ID. A replacement primary connection constructs a new router and
invalidates the old one. Foreground loss, explicit disconnect, authentication
loss, connection termination, or application shutdown also invalidates it.
An invalidated router is terminal and cannot be rebound.

## Parallel route selection

Every authenticated route attempt may construct and authenticate its own
complete router and installed Observe/Act lane owners before reporting ready to
the reconnect owner. Until the reconnect owner accepts that exact route as its
current primary, the route is an inactive candidate: it must not publish lane
events or expose lane handles to the product.

Only the reconnect owner may select a candidate. It does so after its state
machine has accepted the candidate's exact round and endpoint. A late, stale,
cancelled, losing, or otherwise rejected candidate is closed without receiving
publication authority. Selection is single-assignment for one candidate and
must expose the authenticated session and that candidate's Observe and Act
owners as one product update. The selection and termination handoffs must be
bounded, synchronous event delivery; a product consumer moves any actor or UI
work behind its own queue and must not stall the reconnect owner.

Every publication after selection is tagged with the immutable host ID and
connection ID from that candidate's authenticated session. A product consumer
must fence retained state and late callbacks by both values; endpoint text is
never a connection identity. Termination is emitted at most once and only for
a candidate that was previously selected, using the same host and connection
IDs. A candidate that terminates before selection remains unpublished and can
never be selected later.

When the product intentionally replaces a current primary composition, it
must invalidate the old primary before publishing handles from the replacement.
This requirement does not let an inactive candidate invalidate or publish over
the current primary.

## Application state projection

One application-global state owner consumes selection, lane publication, and
termination handoffs for one expected paired host. It accepts lane events only
when both their host ID and connection ID equal the currently selected session.
Late events and termination from an older connection cannot clear, replace, or
republish the current connection.

Selecting a new connection clears every prior connection-bound status, audit
page, catalog, operation, approval prompt, and remote error before exposing the
new handles. Terminating the current connection clears all command handles and
Act authority. It may retain the last validated status and bounded audit page,
but they are explicitly unreachable and can never be relabelled as live on a
later connection. A later selection begins waiting for that connection's own
validated status rather than reusing retained status from its predecessor.

Every application snapshot has a strictly increasing owner-local revision.
Asynchronous UI consumers must reject a snapshot whose revision is not greater
than the last applied revision. State delivery is latest-one bounded; it is not
an audit log and does not replace the privacy-limited self-audit product.

## Generic envelope admission

Before routing, the router parses the bounded closed envelope metadata:
version, message ID, correlation ID, command channel, registered kind,
diagnostic send time, and object-shaped body. This generic parse does not
replace the receiving path's exact body decoder.

Every outgoing request is registered before its authenticated bytes are
enqueued. Original requests have a null correlation ID. The one closed
continuation exception is `interactive.session.approve`: it must correlate to
the exact admitted `interactive.session.approvalRequired` message, as required
by the Interactive Control profile, and its path owner validates that immediate
challenge binding before asking for user presence. No other lane request may
carry a correlation ID. The connection has at most 32 pending requests. Each
registration records its exact request kind, product lane, and an exclusive
30-second monotonic response deadline. Message IDs are unique among pending
requests.

Every incoming reply must:

1. have a non-null correlation ID;
2. have a message ID not already present in the connection's 4,096-entry
   receive replay window;
3. correlate to one pending request before its exclusive deadline;
4. use exactly a response kind registered for that request kind; and
5. enter only the receiver registered for the request's original product lane.

An `error` is routed by correlation, never guessed from its body or current UI
screen. Unknown correlation, duplicate reply message ID, wrong reply kind,
deadline expiry, a missing receiver, malformed generic metadata, or a receiver
decode failure invalidates the whole router and all lane receivers.

## Product lanes

The closed outbound mapping is:

- Observe: `status.snapshot.request` and `audit.list.request`.
- Act: `capability.registry.request`, `operation.invoke`,
  `operation.approve`, `operation.status.request`, and `operation.cancel`.
- Control: `interactive.session.request`, `interactive.session.approve`,
  `interactive.session.end`, `interactive.surface.initial.request`,
  `interactive.surface.initial.ack`,
  `interactive.surface.targets.request`, `interactive.surface.select`, and
  `interactive.surface.ack`.

The exact reply sets remain those in `message-schemas.md` and the Interactive
Control profiles. A kind from one lane cannot be sent through another lane's
sender even if a receiver would otherwise accept its bytes. Route-observation
acknowledgements and authentication frames remain owned by the primary pump and
session and never enter this router.

Each installed lane receiver is single-assignment for the connection. The
router becomes ready only after at least one receiver is installed. A receiver
can issue requests only through its lane-bound sender; it cannot select a lane
per call.

## Send failure and replacement

If enqueueing an outgoing request fails, the router removes only that unsent or
delivery-ambiguous pending registration and reports the failure to the lane
owner. It does not invent a response. This ordering lets the Act owner retain
the durable operation ID and enter `deliveryUnknown` before the primary
connection's terminal callback invalidates the router. Observe does not publish
a fabricated snapshot, and Control follows its own fail-closed teardown rules.

If invalidation races a send or reply, invalidation wins: no receiver event is
published after the router generation changes. Invalidation clears every
pending request and receive-replay entry and invokes every installed receiver's
idempotent invalidation hook exactly once.

## Act adapter

The Act receiver delegates routed bytes to `ClientActChannelV1` and publishes
only its typed events. Catalog continuations and operation commands return
through the router's Act-bound sender, so their request IDs and reply lane are
registered before transport enqueue. The adapter's invalidation hook
invalidates the Act channel, discarding partial catalog state and late approval
signatures.

## Control session adapter

Each authenticated candidate constructs one inactive Control session-command
owner from the exact paired-host record and authenticated-session publication.
The binding includes the paired host ID and fingerprint, client ID, primary
connection ID, authorization epoch, grant revision, and policy revision. The
owner is installed on the Control lane before the primary router activates,
but neither the owner nor any of its events is application-visible until the
reconnect owner selects that exact candidate as primary.

Opening the Remote Control presentation is only navigation intent. It does not
send a request, obtain user presence, create a session, or activate input. A
separate explicit application command chooses a closed effect set and sends
one Desktop-only `interactive.session.request` through the selected Control
owner. The request-submitted state is connection-scoped and is published only
after transport enqueue succeeds.

The Control receiver delegates challenge and acceptance validation to the
normative Interactive client authority. A valid approval challenge may expose
only the approval-key adapter for the closed
`startInteractiveControl` presence reason. The adapter signs only after fresh
OS-backed user presence, sends `interactive.session.approve` through the same
Control lane, and publishes approval-submitted state only after that enqueue
succeeds. Local user-presence cancellation, protected-key unavailability, or a
local signing failure becomes a typed local Control result and closes only that
request authority; it MUST NOT invalidate the authenticated primary or disable
Observe and Act. A correlated closed protocol error becomes a typed Control
result and closes only that request authority; malformed, replayed, mismatched,
late, or otherwise invalid peer replies fail the primary router closed.

An accepted publication contains the bounded role-channel offers, but it is
not evidence that media or input is active. The application may transition to
an active viewing or controlling presentation only after both secondary
channels authenticate and the initial Desktop descriptor, clean media fence,
and acknowledgement complete under the Interactive Control profiles.

Stopping an accepted session is a separate original Control-lane command. The
client closes local media/input role ownership immediately after the exact
`interactive.session.end` bytes are enqueued, enters `ending`, and accepts only
the correlated `interactive.session.ended` or closed error reply. It publishes
`ended` only after validating the exact session ID, authorization epoch, and
correlation. Primary loss still clears local authority but is not relabelled as
a successful remote teardown acknowledgement.

Every Control publication is tagged with the selected host ID and primary
connection ID. Candidate loss, primary replacement, disconnect, application
background teardown, or router invalidation closes the session-command owner,
clears accepted offers from application state, and suppresses late approval or
acceptance publication. A replacement primary never reuses a pending request,
approval, accepted session, or role credential from its predecessor.

A post-authentication Network.framework `waiting` state is not itself a
candidate loss. The client stops admitting new primary commands immediately
and gives that exact `NWConnection` at most 15 seconds to return to `ready`.
Independently authenticated media and input role connections remain owned by
their own exact transport state; primary `waiting` alone MUST NOT retire them.
Recovery keeps the same authenticated primary/router and does not replay a
command or Control event. Expiry, a send/receive failure, or another terminal
primary state invalidates it normally and exact primary termination then
retires the Control roles.

On iOS, application background teardown begins only from the actual
`didEnterBackground` lifecycle boundary. Temporary `inactive` transitions such
as Face ID, Touch ID, the device passcode sheet, Control Center, or other system
UI remain foreground scheduling state and MUST NOT invalidate the primary that
owns the in-flight approval challenge.

An actual `didEnterBackground` transition starts a single fenced grace of at
most 10 seconds. Returning through `willEnterForeground` or `didBecomeActive`
before that exact deadline cancels the pending background transition, and a
stale deadline MUST NOT close the restored primary. If the application remains
backgrounded, it publishes foreground loss at the deadline and closes the
route normally. The bounded grace does not extend the four-hour maximum
Control lifetime, authorize or restart Control, replay input, or weaken the
host's 15-second foreground-loss termination bound.
