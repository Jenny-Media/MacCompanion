# Selected-Primary Control Session Evidence

Date: 2026-08-21

Environment: bundle-independent Swift tests, an injected authenticated primary
frame pump, and macOS/iOS package cross-compiles on Xcode 27 beta. This is
protocol, construction, application-state, and unsigned compile evidence. It
is not a permanent target, physical-device user-presence, live private route,
secondary-channel, captured-frame, posted-input, stable-toolchain, or release
claim.

## Selected-primary construction

Every authenticated route candidate now constructs a complete but inactive
`ClientInteractivePrimaryChannelV0` before its primary router activates. The
channel binds the durable host ID and fingerprint to the authenticated client,
device, primary connection, authorization epoch, grant revision, and policy
revision. The reconnect owner remains the only authority that can select the
candidate and make its handles or host/connection-tagged Control events visible.
Losing, stale, terminated-before-selection, and replaced candidates publish
nothing.

The production configured-route composition derives a distinct
`ClientCustodiedInteractiveApprovalSignerV0` from only the durable approval-key
reference. It can request custody signing only with the closed
`startInteractiveControl` presence reason. It has no session-key operation and
returns only the fixed-width signature required by the Interactive profile.

Opening the workspace's Remote Control entry remains navigation intent. The
separate typed `beginInteractiveControl(effects:)` application command sends
one Desktop-only request only through the selected Control owner. A valid host
challenge is fully checked before the signer requests fresh device presence.
Only a successfully enqueued proof publishes approval-submitted state. A
correlated closed denial becomes a typed retry presentation and can create a
fresh request authority without reconnecting; malformed, replayed, mismatched,
or late replies invalidate the primary router.

## Correlated continuation correction

The end-to-end flow found one inconsistency between the Interactive profile and
the generic primary router. `interactive.session.approve` is a continuation
that must correlate to `interactive.session.approvalRequired`, but the router
had required every outbound registered request to have a null correlation.
The normative router profile and implementation now preserve a single closed
exception for that exact kind. Its path owner still verifies the immediate
challenge binding before user presence, while every other lane request remains
null-correlated. The proof message ID, rather than its correlation, becomes the
pending key for the accepted response.

## Application and presentation state

The expected-host application owner now retains the selected Control channel
only while its exact connection is current. Its public immutable snapshot
contains only a sanitized state: inactive, request submitted, approval
submitted, accepted-but-preparing, or typed remote rejection. Accepted
role-channel credentials are deliberately absent from UI snapshots; the full
accepted value remains package-scoped for the next role-channel composition.

Disconnect and replacement clear every pending approval, accepted offer, and
Control presentation. Old connection events and terminations increment only a
content-free stale counter. The workspace projection explicitly labels an
accepted primary response as "secure screen and input channels are still
starting" and never calls it viewing or controlling.

## Verification

Three focused Control-channel tests drive the real primary router through
request, correlated challenge, proof, accepted session, denial, retry, and the
closed custody presence reason. The selected-candidate pump test sends a real
Control request through the application owner, proves pre-selection silence,
exact host/connection publication, disconnect invalidation, and stale Control
event rejection. A workspace projection test proves accepted is only a
channel-preparation state, a rejection uses a stable code, and disconnected
state overrides retained facts.

The hardened unsigned repository gate passes with 60 indexed protocol/product
fixtures, 730 current repository files plus 34 historical blob paths and 14
repository-material fixtures, four Swift package manifests and 12 dependency
policy fixtures, three privacy manifests with 12 fixtures and six
required-reason API source records, 10 source-SBOM fixtures, 16 release-evidence
fixtures, and 1,003 Swift tests. All macOS/iOS package cross-compiles and all
three no-prompt/no-network construction probes pass. Only the expected
read-only user SwiftPM cache warnings appear.

## Remaining gates

- Consume the accepted package-scoped role offers through exact pinned-TLS
  input and media socket owners and bind their termination to the selected
  primary generation.
- Compose the initial Desktop descriptor, clean-media fence,
  acknowledgement, decoder/render path, and input activation before any UI
  state can become viewing or controlling.
- Instantiate the workspace and Control session owner in the permanent iOS
  target after final identifiers and signing custody are available.
- Prove approval-key user presence, pinned live routes, media, input, lock
  fallback, backgrounding, and teardown on physical signed devices.
- Re-run on stable Xcode 26.6 and preserve signed release evidence separately.
