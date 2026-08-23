# Active-dashboard Agent build lifetime

Date: 2026-08-23

Status: permanent-target construction, focused tests, and unsigned app build
pass on Xcode 27 beta. No app, Agent, ServiceManagement role, local-XPC
session, network listener, Application Support record, or updater was started.

## Outcome

`MacAuthenticatedAgentBuildLifetimeV0` is a one-connection, fail-closed holder
for the running Agent build authenticated by the reciprocal local-XPC hello.
Its mutation methods are package-only. Production app and updater code can
construct and read the value but cannot publish a claimed build or revive a
retired lifetime.

`MacLocalXPCDashboardProductV1` now publishes the build before it advances from
starting to authenticated or sends menu readiness. A second authentication
event is an order violation that retires the existing build and fails the
connection closed. Message-order failure, buffer overflow, transport
invalidation, explicit finish, startup failure, and product retirement all
funnel through the same terminal retirement path. Status snapshots never
manufacture or replace build evidence.

The permanent containing app constructs one lifetime and passes that exact
object to both the dashboard composition and
`MacCompanionUpdateAgentReactivationCompositionV0`. The latter now owns two
different build readers over one shared receipt store:

- startup repair uses the bounded one-shot authenticated probe before the
  dashboard starts; and
- runtime Agent stop uses only the already-authenticated active-dashboard
  lifetime and cannot open a competing probe.

The composition can construct a candidate-bound `MacUpdateAgentStopOwnerV0`
with the containing app's canonical source build and the active lifetime. The
factory itself has no side effect and is not called by the current Sparkle
adapter.

## Verification

Six focused tests cover initial absence, one exact publication, explicit
retirement, duplicate-publication retirement, end-to-end dashboard publication
and invalidation, duplicate dashboard authentication, synchronous retirement
while receiver cleanup is suspended, and the runtime platform reading only the
active lifetime. The permanent unsigned `MacCompanion` scheme build passes and
compiles the shared lifetime through the app composition.

The complete repository gate passes 73 authoritative fixtures, 35 update-
policy fixtures, 3 privacy manifests, 12 privacy fixtures, 16 required-reason
source records, 1,152 repository files and 1,969 historical blob paths, every
supply-chain, privacy, SBOM, signing, packaging, release-evidence, and
permanent-target validator, 1,579 MacCompanionKit tests, 8 platform-probe
tests, and every supported cross-platform compile on Xcode 27 beta.

One preceding full run reported an unrelated transient `.ioFailure` in
`remoteIntentStoreInsertsReplacesAndReopens`. That test immediately passed in
isolation and the unchanged complete gate then passed; no baseline storage code
was modified for this checkpoint.

## Deliberate non-claims

No live hello or Agent build was observed. The Agent-stop owner factory was not
invoked, no receipt was written, and no registration state changed. This
checkpoint does not bind the runtime coordinator's network-admission close,
bounded-work drain, foreground/Control observer, recovery effects, or Sparkle
handoff. The user driver still returns `.skip`, and no download or installation
path is enabled.
