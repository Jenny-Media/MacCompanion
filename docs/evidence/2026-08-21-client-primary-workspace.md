# Client Primary Application Workspace Evidence

Date: 2026-08-21

Environment: bundle-independent Swift tests, injected authenticated primary
frame I/O, and an iOS 17 Simulator package cross-compile on Xcode 27 beta. This
is application-state, projection, compile, and repository-policy evidence. It
is not a permanent target, live private route, signed identity, physical
device, approval-key presence, stable-toolchain, or release claim.

## Application state boundary

`NetworkClientPrimaryApplicationStateV0` is fixed to one expected durable host.
It consumes only selected-primary product handoffs and accepts Observe or Act
events only when both host ID and connection ID equal its current authenticated
session. A late event or termination from an old connection increments a
content-free diagnostic count and cannot change the current snapshot.

Every accepted selection, lane event, or current termination publishes one
immutable snapshot with a strictly increasing owner-local revision. Delivery
uses a single-consumer `AsyncStream` with latest-one buffering; it is current UI
state, not an event log. The UI model independently rejects a snapshot whose
revision is not greater than the last applied revision.

Disconnect clears the selected session, both typed channel handles, the granted
catalog, operation state, approval prompt, and Act errors. It may retain the
last validated status and latest bounded self-audit page, but projection forces
them to unreachable. Selecting a replacement clears even that retained Observe
state and begins waiting for the replacement connection's own validated status.
Old connection status can never become live on the replacement.

The owner exposes typed status, audit, catalog, and operation commands. It does
not expose raw authenticated bytes. The channel invalidation fence protects a
command captured immediately before replacement, and any immediate operation
event is republished only if its captured connection remains current.

Act remote errors now carry an explicit catalog-versus-operation request kind.
A catalog failure clears the catalog without inventing an operation failure; an
operation failure enters only the operation presentation. Observe independently
tracks status-versus-audit errors. UI projections render stable codes and closed
retry guidance, never provider text or safe-argument payloads.

## First-party workspace

`ClientPrimaryWorkspaceModelV0` consumes the single state stream on the main
actor and produces a value-only `ClientPrimaryWorkspaceProjectionV0`. Its
stable `ObservableObject` implementation avoids depending on Swift macro
plugins. An initial attempt to use the Observation macro was rejected after the
Xcode 27 beta plugin server failed; the shipping construction therefore remains
compatible with the recorded non-beta language baseline.

`ClientPrimaryWorkspaceViewV0` presents three peer entries:

- Mac Status for current or explicitly unreachable Observe information;
- Approved Actions for the authenticated granted catalog; and
- Remote Control as a separate intent whose callback owns no session grant.

The view and model contain no raw socket, route, pairing identity, signing key,
grant mutation, capture, input-posting, or Control-channel authority.

## Verification

The injected authenticated-pump test now drives catalog reload and status
refresh through the application owner. It proves initial command denial,
selected connection publication, one real granted catalog, one correlated
status response, exact host/connection tags, stale-event rejection, idempotent
termination, retained-unreachable status, Act clearing, replacement clearing,
old-termination rejection, catalog-error scoping, and latest-one revision
delivery. A separate two-route test still proves that only the exact winner is
selected.

Four UI projection/model tests prove connected waiting state, disconnected
status that can never be live, disconnected Act suppression, latest closed
Observe/Act issue selection, stable diagnostic copy, and rejection of an
out-of-order asynchronous snapshot. A dedicated Act-channel test proves that a
catalog error remains catalog-scoped and creates no operation state.

The hardened unsigned repository gate passes with 60 indexed protocol/product
fixtures, 727 current repository files plus 34 historical blob paths and 14
repository-material fixtures, four Swift package manifests and 12 dependency
policy fixtures, three privacy manifests with 12 fixtures and six
required-reason API source records, 10 source-SBOM fixtures, 16 release-evidence
fixtures, and 999 Swift tests. All macOS/iOS package cross-compiles and all
three no-prompt/no-network construction probes pass. Only the expected
read-only user SwiftPM cache warnings appear.

## Remaining gates

- Instantiate the workspace model and view in the permanent iOS target after
  final identifiers and signing custody are available.
- The selected-primary Control approval lane is now composed in
  `2026-08-21-client-primary-control-session.md`; secondary input/media channel
  activation and initial clean-media acknowledgement remain separate gates.
- Prove Observe/Act replacement, backgrounding, locked-session behavior,
  approval-key presence, and complete commands over physical pinned routes.
- Re-run on stable Xcode 26.6 and preserve signed release evidence separately.
