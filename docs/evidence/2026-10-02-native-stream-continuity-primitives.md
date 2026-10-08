# Native stream continuity primitives, 2026-10-02

## Scope and current state

This checkpoint implements the capture and client primitives for retaining one
native connection during a view change. It does **not** enable connection reuse
in the normal apps. The installed Mac and iPhone apps are unchanged by this
checkpoint, and the normal selection path still closes native preparation and
video before creating the replacement.

Device Hub is a separate application shipped inside Xcode. Its window rows must
remain associated with its opaque application token, rather than Xcode's name.
The preceding window-chooser checkpoint already uses those token associations.

## Implemented

- One `CompanionSelectedCapture` updates its existing SCStream's content filter
  and configuration. The encoded canvas is retained; source dimensions and
  centered aspect-fit placement change together. Samples are dropped while
  either update is pending and across the timestamp cutover. The cutover covers
  the existing 100 ms scheduled-sample allowance, preventing future-timestamped
  old samples from being attributed to the replacement.
- Filter/configuration failure revokes delivery and joins platform stop. Stop
  during either update waits for the pending update; late completion and an
  unsolicited platform stop cannot restart delivery.
- A bounded H.264/HEVC prefix-SEI codec binds a frame to the surface UUID and
  both revisions. It rejects incomplete, duplicate, conflicting and unsafe
  markers. Observation is independent of presentation and input authority.
- The Moonlight adapter has a local pause/resume gate retaining its sockets.
  It validates the complete picture epoch before submitting parameter sets,
  drops old/unmarked pictures during replacement and requires an independent
  picture for the replacement. Queued first-frame callbacks carry a local
  generation fence.
- The UIKit owner retains its driver/view, fences old callbacks and input,
  obtains new logical geometry and requires a fresh presentation receipt. An
  ephemeral UIKit snapshot covers the decoder flush; no snapshot is persisted.
  Revocation, invalid replacement geometry, background and Stop still drain.

The normative continuity document and its authoritative fixture were added to
the existing fixture manifest before the implementation. Enrollment signature,
pairing and approval semantics and their golden vectors are unchanged. Neither
Observe nor Act gains any Control authority.

## Verified

- Stable Xcode at `/Applications/Xcode.app/Contents/Developer`.
- `bash scripts/validate.sh` with the existing non-sandboxed SwiftPM lane passes:
  119 indexed fixtures, package tests and platform builds.
- Native selected capture verification passes: 19 existing lifecycle/sample
  cases, three indexed placement cases and 14 indexed continuity cases. The
  existing private-context safety tests also pass. These use synthetic samples,
  without capturing the desktop or posting input.
- The epoch codec passes the indexed H.264/HEVC vector and rejection cases.
- The dedicated Simulator's native engine/adapter lane passes all 22 tests:
  five Objective-C engine tests, three launch tests and 14 UIKit owner tests.
  Retained-owner tests prove one driver start and zero driver stops across the
  synthetic replacement, followed by exactly one Stop drain. They also verify
  stale callbacks, revocation and incompatible canvas handling.
- Five shared native lifecycle tests pass, including nine indexed continuity
  scenarios. A fresh frame cannot enable input without its separate receipt.

Private logs and artifacts:

- `/private/tmp/maccompanion-native-stream-continuity-validate-20261002.log`
- `/private/tmp/maccompanion-native-continuity-lifecycle-20261002.log`
- `/private/tmp/maccompanion-native-stream-continuity-20261002/`

These tests do not establish physical acceptance, an actual video connection
surviving a switch, performance improvement or a production release.

## Remaining integration

1. Retain the menu-owned native host through an authenticated surface change,
   revoke the previous input authorization, and transfer ownership only after a
   fresh existing enrollment proof for the new acknowledged surface. Preserve
   the exact original primary, registered key, Control generation and deadline;
   Stop, revocation and failure must retire retained and pending resources.
2. Retain the connection's encoded canvas in the trusted target projection.
   Add the owned-child control/context update path for Desktop, App and Window,
   and associate each epoch with its actual captured sample through the encoder
   queue. The current host does not produce the new epoch marker.
3. Reuse the launch adapter's client TLS identity and enrolled host certificate,
   replace its surface-bound enrollment safely, and omit a second native
   `/launch` when the existing owned connection is retained.
4. Connect the normal view selector to those host/preparer operations and the
   retained UIKit owner. Unsupported peers and real connection failures keep
   the existing bounded recovery path.
5. Run paired normal-app video tests covering repeated display/window changes
   and window resize, recording host PID and connection identity. Then build
   and install the verified pair for physical iPhone acceptance. Verify that
   the snapshot handoff actually avoids visible flashing on the phone.

The remaining work is implementation and acceptance, rather than a missing user
permission. The new primitives are deliberately not sufficient to bypass the
existing full surface/enrollment admission checks.
