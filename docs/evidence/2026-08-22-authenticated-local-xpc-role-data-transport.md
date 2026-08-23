# Authenticated local-XPC Interactive role-data checkpoint

Date: 2026-08-22

## Result

The exact authenticated-and-ready menu generation now owns two additional
closed local-XPC lanes without broadening its lease or presentation authority:
Agent-to-menu `runtime.interactive.input.apply` and menu-to-Agent
`runtime.interactive.media.publish`. Input uses strict canonical
`InteractiveInputEnvelope` JSON capped at 65,536 bytes. Media carries one exact
96-byte `MediaRecordHeader` plus at most 8 MiB of payload, including valid
payload-free discontinuity/end records. Both use payload-free exact
acknowledgements; malformed, open, overlapping, timed-out, cancelled, stale, or
unauthorized traffic invalidates the entire authenticated generation.

Input, media, and lease traffic have independent single-flight gates. The menu
runtime reconstructs the full host/device/display/lease/surface command fence
from its currently active lease inside the serialized runtime actor before it
posts input; the XPC envelope cannot manufacture the omitted authority fields.
The Agent side uses a zero-buffer rendezvous between the menu publication and
the exact authenticated network media role, so the menu media acknowledgement
is withheld until that role-data pump takes ownership of the complete record.

Production composition injects one stable media handler into the Agent XPC
server, binds it to the exact authenticated menu generation and its private
input endpoint, then exposes it to the generation-fenced role-data pump. Menu
loss cancels the pump and both suspended rendezvous directions before the
Interactive runtime binding is retired. The permanent menu application passes
the same serialized runtime adapter as both lease and input handler.

## Verification

- The authoritative fixture manifest indexes the canonical local-XPC
  role-data contract, and fixture validation passes all 70 indexed fixtures.
- The C exact-dictionary self-test covers input, nonempty media, payload-free
  media, open-dictionary rejection, and wrong media-header length.
- Focused tests cover generation-fenced independent transaction gates, exact
  media rendezvous backpressure, session/epoch binding, input forwarding,
  stale-generation rejection, and full-fence reconstruction inside the menu
  runtime owner.
- The repository-wide gate passes 1,453 MacCompanionKit Swift tests, all
  macOS/iOS cross-builds, eight platform-probe tests, 1,059 repository files,
  and the native-appearance boundary across 343 Swift sources under Xcode 27
  beta. `git diff --check` also passes.

## Non-claims and next work

This checkpoint provides transport and production authority binding, not a
ScreenCaptureKit capture session, VideoToolbox encoder, queue-to-XPC media
drain, Core Graphics input poster, or physical signed Control session. The
permanent runtime remains safe-unavailable for those concrete effects. Those
effects, their permission UX, and their signed same-LAN evidence are the next
Control slice. Surface-transition local-XPC remains closed.
