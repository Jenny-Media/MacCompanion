# Adaptive surface runtime binding

Date: 2026-08-23

## Result

The permanent Agent and menu-app products now bind the existing authenticated
primary surface protocol to concrete menu-owned Desktop, application, and
window capture transitions. Remote Control remains an independently authorized
Control surface: Observe and Act still operate without capture, and routing
still grants no authority.

The Agent asks the authenticated current menu generation for a bounded,
privacy-filtered target inventory. It receives only session-scoped opaque
tokens, application display names, generic window ordinals, and the existing
current-window Boolean. Bundle identifiers, process identifiers, native window
identifiers, window titles, physical display identifiers, and ScreenCaptureKit
objects remain inside the menu process.

## Two-phase transition ownership

The capture transition is explicitly split so the old and new authority cannot
overlap:

1. the menu runtime releases all held input;
2. the capture adapter stops old-source output and claims the exact retained
   ScreenCaptureKit source without publishing it;
3. the runtime commits the replacement execution lease, surface fence, and
   media-admission state;
4. the capture adapter activates only that prepared source and emits the
   discontinuity under the new fence; and
5. configuration plus a clean keyframe must arrive before the client can
   acknowledge and resume input.

One media publisher survives the source replacement, so sequence numbers
remain continuous. A mismatched, missing, duplicated, or failed preparation
enters the existing fail-closed cleanup path. An ambiguous Agent/menu result
uses an exact-session failure-convergence command; it cannot tear down another
session, and incomplete cleanup remains visibly latched for retry.

The replacement lease atomically rearms the menu expiry scheduler to its exact
new deadline. A stale callback for the previous lease is fenced and cannot
expire or keep alive the replacement. Agent renewal also adopts the exact
current surface lease rather than reverting to the initial Desktop fence.

## Platform geometry and privacy

`MacInteractiveSurfaceTargetOwnerV1` is the menu-only boundary that retains the
current descriptor, physical display, opaque inventory catalog, installed
lease, and at most one selected ScreenCaptureKit source. Target selection
consumes the inventory. Desktop is an explicit escape hatch and receives a
strictly advanced surface and coordinate revision.

Application capture remains limited to the approved display filter. Window
capture preserves the window's global Core Graphics point bounds and computes
its backing scale from the display containing the window center, not from the
initial Desktop display. The input adapter validates those retained bounds
against the descriptor before constructing absolute events. Display rotation
is preserved for Desktop/application capture and intentionally reset for the
window-local coordinate space.

## Local IPC contract

The indexed `local-xpc-interactive-lease-transport-v0.1.json` profile now
freezes nine single-flight commands for Desktop preparation, install, renewal,
revoke, target inventory, target resolution, surface transition,
acknowledgement, and exact-session failure convergence. Every payload is
strict canonical JSON within 4,096 bytes. Inventory replies are capped at eight
candidates so eight maximal 128-byte application names remain within that
bound.

The endpoint rechecks the exact authenticated listener run, menu generation,
and private endpoint token for every command. Unknown fields, wrong reply
kinds, timeout, cancellation after send, replacement, and malformed or
ambiguous results close the generation rather than returning an application
error that could be retried unsafely.

## Verification

- All 71 authoritative indexed JSON fixtures validate with exact canonical
  hashes.
- The complete `MacCompanionKit` catalog passes 1,467 Swift tests. New coverage
  includes all five surface-message round trips, the maximal inventory bound,
  exact endpoint generation/token forwarding, post-install compensation,
  stale-session cleanup rejection, retained window geometry, and replacement
  lease timer rearming.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash
  scripts/validate.sh` passes the complete repository gate: repository and
  dependency policy, permanent targets, privacy manifests, SBOM/signing and
  packaging evidence, package tests, macOS/iOS cross-builds, eight
  platform-authority probes, and the code-signing-disabled permanent app build.
- The focused Agent suite passes 225 tests; local-XPC and menu-platform suites
  compile and pass through the same full gate.

## Non-claims and next evidence

This is construction, protocol, and fault-injection evidence. It does not claim
a live signed app/window transition, real screen pixels, physical input,
physical-iPhone decode/render/input, signed two-process XPC, ordinary TCC
consent, lock/takeover behavior, measured latency, reconnect continuity, stable
Xcode 26.6 compatibility, notarization, or external-beta acceptance.

The next Control proof is user-authorized installation of the already signed
Debug app and explicit Agent enablement, followed by ordinary Screen Recording
and Accessibility grants. With those approvals, the signed two-process test
should exercise Desktop, application, window, Desktop escape-hatch, local Stop,
lease expiry, permission loss, display/window loss, and ambiguous connection
teardown. A physical iPhone then closes the end-to-end media/input and latency
gate. Persistent capture remains a separate managed-entitlement request and is
not required for the logged-in ordinary-consent MVP path.
