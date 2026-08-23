# Permanent Agent Interactive material binding

Date: 2026-08-23

## Gap closed

The permanent Agent already replaced its construction-only visible-admission
and runtime authorities with exact authenticated-menu-generation bindings. Its
top-level input still used `AgentInteractivePlatformServicesV1.inertUnavailable()`,
however, and the product intentionally retained that input's material source
when applying those replacements. As a result, an otherwise admitted Control
request could not create an approval challenge, session identifier, or
one-time input/media channel credentials.

The permanent application preparation now uses
`AgentInteractivePlatformServicesV1.deferredMenuBinding(materials:)` with the
existing `SecurityInteractiveSessionMaterialGeneratorV0`. The generator uses
only Security.framework's system cryptographic random source and is invoked
only when the authenticated host dispatcher requests approval or bootstrap
materials. Construction generates no random value and starts no service.

The later product-root binding continues to replace only visible admission,
runtime ownership, and surface control. It therefore retains the exact
production material generator without giving the application target raw
material access or allowing a second authority root.

## Preserved gates

This change does not:

- make visible admission succeed before the authenticated menu generation
  publishes its exact current revision and display token;
- install, renew, revoke, or otherwise activate an Interactive runtime;
- start local XPC, the network listener, pairing, ScreenCaptureKit,
  VideoToolbox, media transfer, or Core Graphics posting during construction;
- generate credentials before an admitted approval/bootstrap operation;
- retain generated channel credentials outside the existing Agent session and
  role-ingress owners; or
- claim signed, physical, persistent-capture, latency, lock, or input evidence.

The permanent-preparation test now proves visible admission remains closed
while the material source returns a 32-byte challenge, distinct session/input/
media identifiers, and distinct 32-byte channel credentials. Existing
HostPlatform generator tests continue to cover UUID profile bits and random
material shape.

## Next proof

The next Control proof is no longer source material generation. It is the
signed two-process transaction: authenticated menu readiness and visible
admission, Control approval, exact runtime install, paired secondary-role
handshakes, first clean Desktop frame, and a consented input event. Stable
Xcode/signing custody and physical devices remain required for that proof.
