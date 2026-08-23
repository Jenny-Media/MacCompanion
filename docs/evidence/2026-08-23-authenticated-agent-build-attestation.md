# Authenticated Agent build attestation

Date: 2026-08-23

Status: protocol construction and focused tests pass on Xcode 27 beta. No live
Agent, ServiceManagement role, Application Support store, dashboard, or updater
was started.

## Outcome

The reciprocal signed-peer local-XPC hello now returns the Agent process's
canonical numeric `CFBundleVersion`. The acknowledgement has one closed schema:
`kind` as `XPC_TYPE_STRING`, protocol `version` as `XPC_TYPE_INT64`, and
`agentBuild` as `XPC_TYPE_UINT64`. The C parser rejects missing and extra keys
and scalar-type substitution before Swift can publish
`authenticatedAgent(build:)`.

`MacLocalXPCServerV1` reads the build from the Agent process bundle during
construction and refuses listener activation when it is absent or lacks one
canonical decimal representation. It sends that build only after the listener
has applied the exact Jenny Media menu-app peer requirement and accepted the
closed hello. Registration state, an on-disk embedded helper, and a
caller-supplied claim are therefore not substituted for the running process.

`MacLocalXPCAgentBuildProbeV0` is a separate bounded startup-only observer. It
constructs the ordinary Agent-authenticating client, accepts only the first
authenticated build, rejects invalidation and any out-of-order traffic, races a
three-second default timeout, and always cancels the session. Its API documents
that it must run before the dashboard because the Agent owns one current
authenticated menu lifetime.

## Verification

The exact-message C self-test now admits the closed acknowledgement and rejects
a signed-integer build and an additional field. The local-XPC suite adds a
missing-build listener test plus canonical bundle-build parsing. Four probe tests cover exact success/first-result
fencing, start failure, invalidation, unexpected traffic, timeout, invalid
timeout, and session cancellation. The focused local-XPC suite passes 95 tests
on Xcode 27 beta.

The complete repository gate passes 73 authoritative fixtures, 35
update-policy fixtures, 3 privacy manifests, 12 privacy fixtures, 16 required-
reason source records, 1,145 repository files and 1,945 historical blob paths,
every supply-chain, signing, packaging, release-evidence, and permanent-target
validator, 1,566 MacCompanionKit tests, 8 platform-probe tests, and every
supported cross-platform compile on Xcode 27 beta.

## Deliberate non-claims

The app does not yet construct the durable reactivation store, run startup
repair, retain the dashboard lifetime's observed build, unregister or register
the Agent, or enable Sparkle installation. The startup probe is not invoked by
any permanent target. Runtime wiring must use the active dashboard observation
rather than a competing probe. Final signed two-version evidence remains open.
