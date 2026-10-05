# Follow Cursor in zoomed Trackpad mode

## Implementation

The standalone iOS viewer now follows iPhone-originated mouse movement and held
dragging in zoomed Trackpad mode. A 12% viewport margin, capped at 64 points per
axis, triggers only the pan needed to keep the cursor within that margin. Scroll
offsets stay within the selected display crop and zoom remains unchanged. The
current canvas bounds include the reduced area above a docked keyboard.

Fit and Pointer mode do not follow. Manual canvas pan/pinch suspends following
until the next trackpad gesture. Active viewport navigation/deceleration,
background, recovery and presented settings suppress automatic movement. Server
cursor updates alone cannot pan the view, avoiding camera movement from delayed
notifications or Mac-side mouse input.

Held dragging previously measured touch positions inside the scrollable canvas.
Automatic panning changes that coordinate origin and could feed movement back
into the next mouse event. Trackpad held-drag positions now use the fixed cursor
overlay, retaining incremental deltas independent of viewport translation.

Follow Cursor defaults on, is saved per Mac UUID in existing local preferences,
and can be disabled in Session Controls > Input & Quick Actions. Existing Macs
without a saved preference default on; removing a Mac clears its preference.
The native viewer loads it initially and applies settings changes immediately.

The feature reuses the current desktop image and adjusts the native scroll offset
as pointer gestures arrive. There is no timer/display-link polling, additional
framebuffer allocation, pointer command, network request, reconnect or Mac helper
for following. These source and event-count properties do not establish measured
physical energy/frame-time overhead.

The specification and eight geometry cases in the existing indexed direct-client
fixture were updated first. `scripts/verify_vnc_viewport.py` reads those cases
through the sole manifest and verifies the production geometry helper.

## Verification

Toolchain: `/Applications/Xcode.app`, Xcode 27.0.

- **44 hosted tests passed, 0 failed, 0 skipped**:
  `/private/tmp/maccompanion-follow-cursor-verified-tests-20261005.xcresult`.
- Actual UIKit movement keeps the cursor visible, leaves zoom unchanged, preserves
  incremental mouse coordinates after scrolling, and emits exactly the original
  pointer events with no connection start.
- A held-drag regression verifies that an unchanged finger after automatic pan
  does not move the mouse again and that release sends a balanced button-up.
- Manual pan/pinch suspension, next-gesture resumption, opt-out, Pointer/Fit mode,
  background/recovery, selected-display bounds and keyboard-open following pass.
- Per-Mac preference isolation, default migration and removal reset pass. A
  rendered Simulator settings attachment shows the Follow Cursor toggle off for
  an opted-out synthetic Mac, with its explanation readable. Attachments stay
  under `/private/tmp`, not in the repository.
- All 133 indexed fixtures and eight Follow Cursor geometry vectors pass.
- The normal iPhone app builds, all 480 source input hashes match, and its
  existing device profile, Keychain group, ActivityKit extension and deep
  signatures verify. Signed binary SHA256:
  `cc3351f6727b18af0ce47b237debb5174fe4233c38e89202ce9107d9b748314c`.
- The update installs on iPhone 18 Pro Max (database sequence 8204), preserving
  app data:
  `/private/tmp/maccompanion-follow-cursor-signed-ios-20261005/Mac Companion.app`.
- `devicectl` launch succeeds. Required `bash scripts/validate.sh` exits 0 on
  the stable Xcode lane:
  `/private/tmp/maccompanion-follow-cursor-validation-20261005.log`.

## Physical confirmation — 2026-10-05

After installation and the requested edge-movement/dragging check, the user
reports that it works well. This passes the basic physical Follow Cursor
behavior/feel check on the installed iPhone 18 Pro Max update. The reply does not
provide separate results for every keyboard/dragging corner case or a sustained
run. Measured energy/frame-time overhead remains unverified.

No real pixel/input content or credential is captured. No commit or publication
is made.
