# Authenticated focus-candidate local XPC

Date: 2026-08-23

## Outcome

The authenticated Agent-to-menu Interactive runtime family now has a tenth
closed operation for one focus snapshot. The command binds the current session,
authorization epoch, surface identifier, surface revision, and coordinate-space
revision. Its canonical reply echoes that complete fence and carries only a
closed target recommendation, optional `SurfaceFocus`, input-paused proof,
closed reason, and validity duration.

The operation uses the existing exact XPC dictionary grammar, current
authenticated-and-ready menu generation, private endpoint token, shared
cross-family single-flight gate, bounded payload, deadline, and generation-wide
fail-closed behavior. It cannot carry an AX object, PID, bundle identifier,
window identifier, title, label, value, selection, or other application
content.

## Menu runtime safety

The menu-owned surface target now retains the exact global input bounds for the
active Desktop, Application, or Window surface. It generates a stable opaque
focus token and monotonic revision only from changes to the already reduced
category, rectangle, editable, and secure tuple. Transition input bounds remain
menu-private and follow the same prepared-source commit.

If the active surface is already a Focused Region and the sanitized focus
changes or disappears, the menu runtime releases all posted input before
returning `inputPaused: true`. Its admission state remains focus-paused: old
video may continue, but new input is rejected. The subsequent client selection
uses the ordinary release/prepare/activate/discontinuity/configuration/clean-
frame/acknowledgement path without releasing input a second time. A failed or
ambiguous snapshot fences the authenticated generation and converges through
the existing teardown path.

## Verification

- Canonical IPC tests round-trip the exact focus command/reply and reject a
  broadened target kind plus mismatched correlation.
- The local-XPC C grammar covers all ten exact request/acknowledgement pairs.
- The shared gate, opaque endpoint, and Agent product route prove exact
  generation, private-token, fence, and candidate materialization behavior.
- A runtime test enters a real Focused Region transition, pauses on a focus
  change, rejects input, replays the pause without a second release, and feeds
  the ordinary next transition.
- The repository-wide gate passes 73 indexed fixtures, all 1,488 discovered
  Swift tests, macOS/iOS cross-builds, unsigned permanent application builds,
  and eight platform authority probes on Xcode 27 beta.

This checkpoint does not yet run a live Agent polling/subscription owner, emit
the prepared event from the permanent network product, build a focused-region
ScreenCaptureKit crop, or apply Smart Zoom automatically on iOS. It makes no
signed-device, TCC, latency, or lock-screen claim.
