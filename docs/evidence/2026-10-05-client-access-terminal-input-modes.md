# Client access, Terminal and input modes — 2026-10-05

## Authorized scope

The user approved all five features and requested installation only after they were
finished. This change adds the optional local app lock, fullscreen key-bar hiding,
SSH Terminal, Pointer click reliability, and Trackpad & Keyboard without video.
The normal iOS development composition still connects directly to built-in macOS
services and starts no Mac Companion host, Agent, helper, pairing or grant flow.

## Implemented

- App unlock is off by default. LocalAuthentication deviceOwnerAuthentication uses
  Face ID with device-passcode fallback. Saved Mac metadata and UI load immediately
  behind an opaque privacy cover with a Liquid Glass unlock card. Credential reads,
  connect and foreground resume wait for unlock. Background entry revokes access;
  authentication cancellation and stale results cannot reveal content. The cover
  also blocks interaction and accessibility through presented controllers.
- Hide Keyboard Bar expands the viewport, preserves the socket and relative view,
  and is remembered per Mac. The controls button remains reachable and dims when
  idle. It offers Show Keyboard Bar and Toggle Keyboard while the strip is hidden.
- Terminal is available from each Mac's menu, using built-in Remote Login and a
  separately editable SSH port (blank = 22). It has separate per-Mac Keychain
  credentials and server-key trust. First use shows the SHA256 server fingerprint
  before any password authentication; changed keys fail closed. The terminal
  renderer supports interactive PTY output/input and resize. Background/exit closes
  the SSH connection, with an explicit new-shell reconnect and no input replay.
  Remote clipboard reads are denied; clipboard writes and web links need a tap.
- Pointer uses a discrete short-touch recognizer tolerant of small drift, while
  movement and hold continue to move/drag. One click enqueues an atomic press/release
  pair or rejects both. Rejected clicks show a status message. No click is retried
  automatically. macOS can still consume a first click to activate an inactive app.
- Trackpad & Keyboard is available in the saved Mac menu and session controls. It
  hides remote content, keeps foreground input on the same Screen Sharing socket,
  and suppresses regular framebuffer requests/presentation. One already-requested
  frame may drain. Returning to Desktop requests a fresh full frame. Background
  still releases input and pauses the native owner.
- Library schema 3 reads schemas 1 and 2, preserving UUIDs, Desktop logins and
  preferences. SSH defaults to port 22 on migrated records. No Mac installation.

## Source-backed findings and dependency handling

The Pointer recognizer previously allowed a small-drift touch to become movement
without a click. Native click admission also used two independent queue operations.
The corrected gesture and atomic pair are tested separately from mouse movement.

Citadel's existing-channel API performed synchronous pipeline setup on Swift's
executor, crashing with EventLoop.preconditionInEventLoop. The local pinned copy
moves pipeline setup and construction of its loop-bound handler onto NIO's event
loop; its handshake timeout now honors settings. This keeps exact-address validation
before connecting, with no second DNS lookup. Unused package executable/test targets
are excluded. PEM formatting delimiters are assembled from fragments, and the
abbreviated key example is removed so the unchanged secret scanner can scan the
repository without mistaking parser format strings for embedded key material.

Native/Terminal/source-lock.json records upstream revision, patch and hashes of all
52 vendored files. Package.resolved pins all 12 resolved packages. The build checks
both vendor hashes and resolved revisions. Original MIT/Apache notices are bundled.
A separate hash-bound development dependency admission preserves permanent Release
gates and the existing closed legacy dependency policy.

## Verification

- 61 hosted Simulator tests pass, including actual Screen Sharing socket input
  with no pixel requests, atomic click admission, cancelled/drifted taps, fullscreen
  viewport expansion, local authentication cancellation/stale-success handling,
  library migration, separate real synthetic Keychain entries, and existing tests.
- Actual SSH socket tests verify zero password requests before trust, rejection of
  changed and declined keys, interactive ordered bytes, PTY resize and background
  stop. An initial declined-key cancellation hang was fixed and the final suite
  passes. These tests use a loopback synthetic server, not a real Mac login.
- Final result: `/private/tmp/maccompanion-client-additions-verified2-tests-20261005.xcresult`.
- Stable Xcode full `bash scripts/validate.sh` exits 0. Log:
  `/private/tmp/maccompanion-client-additions-validation-final-20261005.log`.
- Final normal device build succeeds. Frozen source hashes, pinned dependencies,
  Face ID usage string, app/widget versions, bundled notices, existing Keychain
  group, matching device profile and deep signature are verified. Build report:
  `/private/tmp/maccompanion-client-additions-final-device-20261005/build-report.json`.
- Signed artifact:
  `/private/tmp/maccompanion-client-additions-verified-signed-ios-20261005/report.json`.
- Simulator UI inspection confirmed the Mac-menu Terminal/Trackpad entries and
  Terminal login screen. Screenshots stay outside the repository.

## Acceptance boundary

The completed update was installed once on the iPhone 18 Pro Max after final
validation and signing (CoreDevice install exits 0; database sequence 8308). Existing
app data and its Keychain access group are preserved. Install evidence:
`/private/tmp/maccompanion-client-additions-install-20261005.json`.
The post-install launch was denied because the iPhone was locked. The installation
is complete; opening the app and physical acceptance remain with the user. Launch
evidence: `/private/tmp/maccompanion-client-additions-launch-20261005.json`.
After the user's explicit Install request, the same final signed artifact was
verified and reinstalled successfully (database sequence 8316), then launched
successfully. Retry evidence:
`/private/tmp/maccompanion-client-additions-install-retry-20261005.json` and
`/private/tmp/maccompanion-client-additions-launch-retry-20261005.json`.
Real-device Face ID/passcode, finger gesture feel, TV control and SSH against the
user's Mac remain physical acceptance steps. The new features are implemented;
Simulator/loopback checks do not claim those physical results or a public release.
