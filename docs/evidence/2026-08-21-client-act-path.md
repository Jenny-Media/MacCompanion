# Independent Client Act Path Evidence

Date: 2026-08-21

Environment: bundle-independent Swift packages plus an unsigned disposable
iPhone 17 Pro Max Simulator target on iOS 27.0 with Xcode 27 beta. This is
construction, state-machine, cross-compile, and accessibility evidence. It is
not signed-product, stable-toolchain, physical-device, live-network, Keychain,
or Core Audio mutation evidence.

## Boundary

`spec/capability-protocol/v0/client-operation.md` now makes Act a first-class
client path. The official client may show only a complete granted catalog
bound to the authenticated session's exact grant and policy revisions. It
cannot invent provider buttons, expose an arbitrary JSON or command editor, or
require an Interactive Control session.

`ClientCapabilityParameterDraftV1` renders the complete closed capability
schema family as native restricted JSON: Boolean, bounded integer, bounded or
closed-value string, bounded homogeneous array, and closed object with required
and optional properties. It creates deterministic schema-valid defaults,
supports explicit optional/array edits, rolls back a rejected edit, and
revalidates the complete object before invoke.

`ClientOperationSessionV1` owns one durable operation on one authenticated
primary connection. Construction binds the durable client/host/device
identities, pinned host fingerprint, 16-byte connection ID, authenticated
grant/policy fence, one complete catalog, and one granted descriptor. It owns
exact invoke/approval/status/cancel correlation and operation-ID equality,
validates parameters before send and results before publication, preserves
delivery-unknown separately, and queries the same durable operation ID rather
than automatically retrying with a new effect.

The approval adapter holds only an opaque separately protected approval-key
reference. It always requests the `approveOperation` user-presence policy and
signs the normative host/client/connection/challenge/digest/expiry/version
input. The operation owner checks expiry before and after the asynchronous
signer. Connection/app invalidation advances its generation, so a signature
that returns after invalidation is discarded and cannot become a wire frame.

`ClientActChannelV1` now composes the catalog loader and one-operation owner for
one already-authenticated primary connection. Its injected sender accepts only
already framed authenticated command bytes; it has no identity, grant, or reply
interpretation authority. The channel owns exact correlation for every catalog
page, sends a continuation only after the prior page passes every fence, and
atomically publishes only the complete catalog. It routes only the closed Act
reply set into the operation owner. `NetworkClientPrimaryFramePumpV0` conforms
to this sender boundary without acquiring any Act authority.

An operation-command send failure moves the retained operation into
`deliveryUnknown`; a newly authenticated channel can query the same caller-kept
operation ID without constructing an invoke. A catalog send failure invalidates
the unpublished load. Connection/app invalidation discards the catalog and
active operation generation and wins over a suspended user-presence signer, so
its late signature is never enqueued.

## iOS presentation

`CompanionClientUI` now supplies:

- an Approved Actions catalog sourced only from the granted catalog;
- a recursive schema-driven parameter form with no raw JSON surface;
- complete effect-fact disclosure and explicit review for destructive,
  irreversible, credential-using, external-service, or disruptive effects;
- distinct user-presence, policy, queued, running, cancellation, success,
  denial, expiry, failure, delivery-unknown, and outcome-unknown states; and
- transient schema-verified result rows with an explicit reminder that Observe
  remains authoritative.

The catalog is independent of the Remote Control entry. The expanded
`Experiments/ClientUIHarness` visibly labels that its Act outcome is typed and
synthetic and that it owns no socket, credential, or signer. Its real
accessibility flow navigates Approved Actions, edits the Boolean mute parameter,
runs the typed action, observes a validated `Muted, Yes` result, and asserts
that no Remote Control entry is present in the Act flow.

## Focused verification

Nine new Swift tests prove:

- closed default construction, optional/array edits, bounds, and rollback;
- exact catalog/session fence rejection and pre-send parameter validation;
- exact operation ID and correlation fencing;
- exact normative approval signing bytes;
- descriptor-schema result validation;
- invalidation while user presence is suspended discarding the late signature;
- ambiguous delivery querying the same durable operation ID;
- granted-only catalog ordering and complete effect projection; and
- distinct delivery-unknown, outcome-unknown, success, and bounded remote-error
  presentation.

Six additional channel tests prove:

- exact response correlation across a two-page catalog and no partial
  publication;
- catalog invalidation on a mismatched correlation or failed continuation send;
- invoke, approval, status, and cancellation routing through one sender;
- approval publication only after its frame has been enqueued;
- ambiguous invoke recovery through a status request for the same operation ID
  with no replacement invoke; and
- connection invalidation while approval signing is suspended discarding the
  late signature before it reaches the sender.

The iOS `CompanionClientUI` package cross-compile passed. The complete
disposable harness then executed four UI tests with zero failures. The test run
used control-coordinate interaction for the iOS 27 beta switch after ordinary
accessibility `tap()` synthesized an event on the row without toggling the
control; the test explicitly waits for the switch accessibility value to become
`1` before invoking.

The final hardened unsigned repository gate then passed with:

- 60 indexed authoritative JSON fixtures;
- 705 current repository files, 34 historical blob paths, and 14 adversarial
  repository-material fixtures;
- 4 package manifests and 12 dependency-policy fixtures;
- 3 privacy manifests, 12 privacy fixtures, and 6 required-reason API records;
- 10 source-SBOM and 16 release-evidence fixtures;
- 969 Swift tests, including 76 `CompanionClient`, 22 `CompanionClientUI`, and
  174 `CompanionAgent` tests;
- the macOS and iOS package cross-compiles; and
- all three construction-only no-prompt/no-network probes.

Only the expected read-only user SwiftPM cache warnings appeared.

## Remaining gates

- Instantiate the authenticated primary-router bridge from the configured-route
  application product and future permanent target. The bridge and real Network
  pump now route a correlated catalog page through the Act channel under test,
  while the disposable harness deliberately has no command-send authority.
- Execute the user-presence signer through final signed Keychain/Secure Enclave
  identities on a physical iPhone.
- Perform an authenticated physical iPhone-to-Mac operation exchange and
  signed clean-Mac Core Audio support/mutation/read-back checks.
- Re-run on stable Xcode 26.6 and preserve signed release evidence separately.
