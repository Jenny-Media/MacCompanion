# Managed selected capture spawn context

## Change

The menu can construct a private, non-Codable App/Window capture projection
from its committed ScreenCaptureKit target. It verifies the exact native
authority, public key, scope, geometry and current process/window/bounds/scale
before writing one canonical `selected-capture.json` into the operation's
private directory. The managed process owner clears inherited selection paths
and passes only that operation's path to Sunshine. Desktop still uses its
existing path when no approved selection is supplied.

The child opens each directory component without following symlinks, requires
an owner-only directory and single-link regular record, and checks the exact
managed profile, operation, display, mode, expiry and closed record shape. It
rechecks the process launch instance, selected window or application bounds,
display and scale before resolving a new ScreenCaptureKit filter and on each
accepted frame. It preflights screen capture permission without requesting it.
An invalid selected context fails capture; it never falls back to Desktop.
No physical process/window identifier enters Agent IPC or a network message.

The normative contract and sole indexed fixture were updated first in
`spec/capability-protocol/v0/managed-native-host.md`,
`spec/fixtures/native-selected-capture-context-v0.1.json` and
`spec/fixtures/manifest.json`. No pairing, signature or grant format changed.

## Verification

- The focused Swift fixture test matches the menu's encoded record byte for
  byte. Private log:
  `/private/tmp/maccompanion-selected-context-swift-tests-20260927.log`,
  SHA-256 `403b68ad0f2209b403681fac7bd3e007c089b86e7ad1e096e13d2a25da2817b9`.
- Fifteen adapter lifecycle/sample cases, the private context's valid and
  rejected record/file cases, and three Sunshine bridge conditions pass. The
  native tests use synthetic data and request no capture permission. The
  private context also rejects a fake process after successfully loading its
  otherwise valid record.
- The pinned Sunshine source, submodules, artifacts and combined patches
  verify. Managed patch SHA-256:
  `7e96f028e88c8c87d6996931831f4dad67f65f93ec31ec02b6ada1b319fdbd9f`.
- A disposable source-built host at
  `/private/tmp/maccompanion-selected-context-host-20260927-v1` configures,
  compiles and links both first-party ARC classes and ScreenCaptureKit. Its
  binary SHA-256 is
  `6673f1bacd5c81ed5cabb2242797dfdae502bc9262a816d45e48d9cfef5f22e0`;
  provenance SHA-256 is
  `75172faf051d4e8085eb7a1683f946674df274177fe7d1ec298cbbb27194a8c6`.
  `releaseAdmitted` is false. CMake initially could not resolve GitHub for
  Boost/JSON. Reusing the previously downloaded, pinned archives completed
  this offline build; the Boost archive matches its locked SHA-256.
- Required stable `bash scripts/validate.sh` passes with 115 indexed fixtures,
  package/lab/platform builds and native context tests. Private log:
  `/private/tmp/maccompanion-selected-context-final-validation-20260927.log`,
  SHA-256 `4021c07a4b86f789a648e82c434c20e34fdd553f088a908b9b8f57116d87bb1d`.
  The first sandboxed attempt could not evaluate the SwiftPM lab manifest;
  rerunning with normal Xcode cache access passed. Aggregate native source
  input SHA-256:
  `e1ce7db8f77da61143bad794560f8644d351d427ff2238ffa7c8fdd74b759965`.

## Next acceptance

The normal native backend owner and authenticated runtime/client admission are
still Desktop-only. This checkpoint does not show selected App/Window pixels
or a new Simulator session. Connect the retained selection to the normal
backend under the existing grant, obtain fresh selected-frame evidence with a
permitted Mac capture process, then update the normative admission fixtures
before opening App/Window playback and input. Rebuild the pinned normal host
and client and repeat the normal Simulator journey. Viewport bitrate, current
corresponding-source assembly, installed Mac GUI/TCC and paired physical LAN
acceptance remain separate pending work.
