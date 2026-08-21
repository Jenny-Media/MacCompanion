# Client primary authentication v0.1

Status: normative bundle-independent client composition. This profile binds one iOS-side application-primary connection to the pinned-TLS and application-authentication contracts. It does not normatively define Network.framework construction, Security-framework trust extraction, private-key custody, UI, or a permanent Apple target.

## Ownership and phases

One client owner has exactly these phases:

```text
awaitingTCP
  -> awaitingPinnedTLS
  -> readyToAuthenticate
  -> awaitingChallenge
  -> awaitingDescription
  -> authenticated
  -> closed
```

Any failed transition, malformed message, replay, bad correlation, pin mismatch, paired-identity mismatch, signing failure, remote authentication error, or authentication deadline failure closes the owner. A closed owner cannot reopen. No authenticated session value is published before the final transition.

The owner holds one connection replay window spanning sent and received handshake message IDs. The socket adapter does not own correlation or decide that authentication succeeded.

## Pinned TLS gate

The owner creates the application-primary `PinnedTLSConnectionAuthority` from the 32-byte host fingerprint saved by pairing. It admits no `auth.hello` until the live adapter has supplied peer evidence proving:

- exactly TLS 1.3;
- no accepted early data;
- an accepted pinned-leaf trust policy; and
- an independently extracted SPKI whose SHA-256 fingerprint equals the saved fingerprint.

The live adapter remains responsible for obtaining trustworthy evidence from the actual connection. Routes and discovery metadata never alter the required fingerprint.

The disposable `CompanionClientNetworkPlatform` adapter creates one TLS-attempt context for exactly one closed route, one immutable pin, and one `NWConnection` reference. Its callback fixes TLS 1.3, disables resumption, rejects accepted early data, requires a synchronous evaluator to return the exact SPKI only after the complete pinned-leaf profile passes, and independently matches that SPKI to the saved pin. The concrete evaluator requires exactly one `SecTrust` leaf and passes its bounded DER through the pure strict inspector, which reconstructs the canonical profile, verifies the P-256 self-signature and exact current validity, and returns the canonical SPKI. The resulting handoff is one-shot and consumable only for the exact connection reference after ready, then replayed through the client owner before `auth.hello`. Construction tests prove these boundaries; live TLS callback ordering and wrong-key/proxy rejection still require physical evidence.

The release reconnect composition does not accept a preconstructed session
signer, nonce generator, message-ID generator, or pinned-leaf evaluator. It
accepts the client key-custody boundary, reads the exact opaque session-key
reference from the immutable durable paired-host record, constructs the
session-only custody signer, creates fresh 32-byte nonces and message IDs from
system randomness, and installs the strict Security.framework pinned-leaf
evaluator using the same runtime wall clock. The approval-key reference is
never exposed to reconnect signing. Raw signer/randomness/evaluator injection
and direct primary-session/route-attempt construction are package/test seams,
not release application APIs.

## Configured-route application product

The release iOS target does not assemble the durable host inventory, route
catalog, reconnect owner, application binding, and UIKit lifecycle bridge
independently. A Network-platform product composition reads one exact paired
host and one exact configured-route snapshot, constructs the reconnect
controller only through the session-key-bound runtime above, reconciles storage
before returning, and fixes initial scheduling to foreground false/network
unreachable. Its binding uses the same runtime monotonic clock and system UUID
round identifiers.

A Client-platform factory consumes that complete composition and constructs the
default Boolean-only coarse-reachability/UIKit application owner. It returns the
owned route lifecycle for settings edits and the single application owner for
start/stop. Pairing remains a separate sealed application owner so an unpaired
installation can scan and pair without selecting or constructing a reconnect
host. Missing/changed paired identity, missing/invalid route state, or product
construction failure returns no UIKit network product and opens no route.

The concrete route attempter starts exactly that one connection, treats setup/preparing/waiting as nonterminal only through the plan's bounded connection deadline, consumes the handoff only after ready, creates a fresh paired client session and handshake values, and transfers ownership to the serialized frame pump. `session.describe.response` completion authenticates identity and command authority. The dial attempt publishes a usable route with command-send and close authority only after the initial configured-route observation has been written, or immediately when that exact route requires no observation; it never waits for the non-authorizing acknowledgement. A failed initial write cannot win the route race. A closed remote authentication error produces terminal authentication denial; connection, timeout, framing, send, or other protocol failures remain transient route failure. Task cancellation cancels the same connection, and the dial-round executor closes a success that arrives after cancellation. Compile and no-network tests cover route synchronization plus injected frame send/receive/malformed/denial/teardown faults; live TLS callback and physical socket behavior remain release evidence.

## Application handshake

After the pin gate, the client sends one `auth.hello` containing its paired client ID and a freshly generated 32-byte nonce. It accepts only an `auth.challenge` correlated to that hello and repeats the saved host fingerprint exactly. The owner constructs the normative authentication signing input from the client ID, host-issued connection ID, both nonces, fingerprint, and selected version.

Private-key custody is injected. The signer receives only the exact signing input and must return the v0.1 fixed-width 64-byte P-256 `r || s` signature. It does not receive a socket, envelope, route, host presentation value, or authorization decision. The resulting `auth.proof` correlates to the challenge.

The client then accepts only `session.describe.response` correlated to that proof. Its `hostID` and `deviceID` must exactly match the durable record created by pairing. Only then may the owner:

- promote the pinned transport authority to ready;
- publish the authentication-issued connection ID for later bound approvals;
- publish current authorization, grant, policy, host-state, and feature facts; and
- admit ordinary command/event traffic allowed by the transport profile.

The description is current authenticated state, not a grant by itself. Capability availability still comes from the privacy-limited capability registry.

## Timing and errors

The client uses a nondecreasing monotonic clock. TLS plus application authentication must finish strictly before the exact 10-second deadline measured from TCP connection. A separate socket timer invokes the owner's deadline check even when no bytes arrive. Wall-clock fields remain diagnostic protocol values only.

A closed, valid `error` response is accepted only when correlated to the currently outstanding hello or proof. The client may use its stable code and retry class for policy, but it does not display unregistered server text. A malformed or wrongly correlated error is a terminal protocol failure.

## Acceptance boundary

Bundle-independent acceptance requires tests for the successful signature transcript, no pre-pin authentication, wrong TLS/SPKI evidence, challenge pin/correlation mismatch, replay across directions, exact deadline expiry without inbound bytes, remote denial, paired host/device mismatch, a no-network verified-ready pump construction boundary, and injected send/receive/disconnect/frame faults. Release acceptance additionally requires Keychain-backed signing, live trust extraction from the same connection, physical wrong-key/proxy rejection, reconnect integration, and signed-device exchange.
