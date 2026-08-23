# Interactive runtime composition boundary

Date: 2026-08-22

## Result

The first transport-independent Agent/menu runtime composition is now present.
It connects the previously frozen lease messages to the existing serialized
menu runtime without constructing screen capture, input posting, or a live
permanent-target Control session.

On the menu side, `MacInteractiveLeaseRuntimeAdapterV1` forwards install,
renewal, revoke, and Agent-loss invalidation into exactly one
`InteractiveMenuRuntimeOwnerV0`. If that owner reports or encounters incomplete
cleanup, the adapter latches `safetyRecoveryRequired` and rejects every later
lease operation. The dashboard product and application expose explicit
construction seams for this adapter; ordinary permanent construction remains
Control-inert until concrete platform owners are supplied.

On the Agent side, `AgentInteractiveRuntimeOwnerV1` is the final install
boundary required by `InteractiveSessionRuntimeOwningV0`. It:

- re-reads the durable device/grant plus visible-menu admission before Desktop
  preparation;
- obtains a bounded initial Desktop descriptor through a platform-neutral,
  opaque-display seam;
- re-reads the exact admission after that suspension and rejects any change;
- binds the verified bootstrap, approved effect set, selected display, first
  descriptor, command ID, and lease ID through
  `InteractiveInitialRuntimeCommandAuthorityV1`;
- transfers channel credentials into active ownership only after the exact
  menu generation/revision install receipt is accepted; and
- renews only the exact current lease after another final admission read; and
- serializes termination behind installation or renewal, sends one exact
  revoke, validates all four cleanup facts, and invalidates unused channel
  credentials.

Any failed install, renewal, or mismatched receipt immediately attempts an
exact compensating revoke. A proved four-effect cleanup returns the owner to
idle; ambiguity or incomplete cleanup latches `safetyRecoveryRequired`. A
product-layer type adapter gives that owner only the three local-XPC lease
lifecycle operations; the server, presentation surfaces, peer handles, and
status authority do not escape.

## Verification

- Three menu-adapter tests prove exact forwarding, runtime-reported recovery
  latching, and one-shot latching after ambiguous connection-loss cleanup.
- Three Agent-owner tests prove double admission revalidation, no send after a
  changed final admission, exact install/renew/terminate correlation, and
  compensating revocation after a mismatched menu-generation receipt.
- Focused dashboard/application/product tests passed after the new injection
  seams.
- The complete MacCompanionKit Swift Testing catalog passed all 1,406 tests
  with the supported SwiftPM/compiler sandbox-disable flags under Xcode 27
  beta.

## Non-claims and next work

The permanent app still selects its inert no-runtime constructor. No screen is
enumerated, no capture session is created, no input event is posted, and no
network listener or local-XPC session was started by these tests.

Before Control can be enabled, the menu must publish an exact revisioned
visible-display admission and retain the opaque UUID-to-`CGDirectDisplayID`
mapping, prepare the first Desktop descriptor/capture source, and construct the
indicator, capture, input-release, frame-blanking, input-posting, and bounded
media-queue adapters. The Agent owner also needs automatic generation-fenced
renewal scheduling and secondary input/media channel handoff before a session
can remain live.
