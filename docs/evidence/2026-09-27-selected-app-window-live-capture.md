# Selected App and Window live capture checkpoint

## Change

The normal Mac backend owner now accepts an exact, current menu-owned App or
Window target and passes its private selection to the managed native host
factory. It rejects a missing, pending, replaced or mismatched target before
launch, and rechecks the retained target during backend health and input
admission. Desktop remains bound to its exact active Desktop selection.

The local native runtime snapshot now carries the acknowledged `surfaceKind`.
Receipt decoding still admits Desktop only. The backend owner compares that
kind to the menu's selected target on preparation and revalidation, so a later
App/Window admission change cannot treat a missing target as Desktop. This
local contract was added to the normative spec and indexed fixture first.

The first-party ScreenCaptureKit adapter now retains the background color
through the stream lifetime. A signed live test exposed an `EXC_BREAKPOINT` in
`SCStream` initialization: the SDK declares
`SCStreamConfiguration.backgroundColor` as `assign`, and the adapter had
released the color before stream initialization copied it. The adapter also
accepts bounded positive `ContentScale` values for native resampling and up to
5 ms of future display-time skew while retaining the 2 s age and ordering
checks. Boolean scale metadata remains invalid. The normative managed-host
contract and the sole indexed fixtures were updated before these behavioral
changes. No pairing, grant, signing or network format changed.

## Verification

- A disposable, signed Mac app used the installed Mac Companion app's exact
  designated requirement and existing Screen Recording attribution. Its
  preflight passed without asking for new permission. It created an owned red
  window, wrote a private one-operation selected-capture context, resolved a
  fresh ScreenCaptureKit filter, and received an actual red-center frame
  through the first-party adapter. The final Window report is
  `/private/tmp/maccompanion-selected-live-probe-20260927/report-v15.json`,
  SHA-256 `669c6b85e9ec7f62ac0908167e27afd530aa22b6155f18c435112750de0a110a`.
  The final App report is `report-v16.json`, SHA-256
  `874eb0dbb07370036e1977c24e9e4605efbf92593b255452492a28bbb6b3af8e`.
  Both report `contextCurrent`, `contextLoaded`, `preflight`, `receivedFrame`
  and `redCenter` true with `terminalCode` zero. The report stores only
  booleans and status; it contains no image, pixel values or input content.
- The disposable probe executable SHA-256 is
  `1b720a54546cd2a40fcf2448332cad8379451de595a30b27e9178628d63691d4`.
  Its designated requirement matches the installed development app. The
  installed app was not modified for this test.
- Twenty-three focused Swift backend/selected tests pass. Log:
  `/private/tmp/maccompanion-selected-owner-tests-20260927.log`, SHA-256
  `c783eb8cfd25374332d991e59c6ca182052fc19b5e7c9f1287b41c6cf0dadcd1`.
  Seventeen native lifecycle/sample cases, private-context rejection cases,
  and three Sunshine bridge cases pass. Log:
  `/private/tmp/maccompanion-selected-app-window-final-native-tests-20260927.log`,
  SHA-256 `2d0c944f9471c17096f3b63b10c82926878b0e62d6d3fc9128e8f360e2493be1`.
- After the snapshot-kind change, 18 focused backend tests pass (log
  `/private/tmp/maccompanion-selected-owner-kind-tests-20260927.log`, SHA-256
  `6ceec70b4560d45e94f1f2996f1b1854c92c01e808ca3c660287582f2103ca82`).
  Three focused snapshot tests pass, including four rotation cases and missing,
  App, Window, focused-region and unknown-kind rejection (log
  `/private/tmp/maccompanion-native-snapshot-kind-final-tests-20260927.log`,
  SHA-256 `c19e463deb768193bd8a552dfc67767614e1bd82195c6d6469e29210bf7be66e`).
- The pinned source-built Sunshine host compiles and links both first-party
  capture classes and ScreenCaptureKit. Binary SHA-256:
  `77dc3432fb0c14ce625fc6797770191cf3cc2143fdb717568176907dcb84e68c`.
  Provenance SHA-256:
  `6a3363f9b9c65a8b174d09910781c5ecc581b613578a1e0a4d67e4eea5af0361`.
  Its recorded selected-capture source hashes match the final Native/Host
  files, and `releaseAdmitted` remains false. Aggregate native source-input
  SHA-256: `310c1c736b70960bff44fdb6197f950ed81b54996a3677f3baa1b184c54386f6`.
- Required stable `bash scripts/validate.sh` passes after the snapshot-kind
  change with 115 indexed fixtures, package/lab/platform builds and native
  selected-capture checks. Log:
  `/private/tmp/maccompanion-selected-app-window-snapshot-final-validation-20260927.log`,
  SHA-256 `25780ef930320886db565233b48c5ea2e749602b448699a9b4d67376afc6e0af`.

## Acceptance boundary

The live frame test was one signed disposable Mac app, not a normal managed
Sunshine child or an iPhone playback session. The normal runtime snapshot and
client surface transition still admit native Desktop only. App/Window native
re-enrollment and current-generation input/presentation fencing must be
specified, implemented and tested before normal Simulator acceptance. Visible
area bitrate, current corresponding-source assembly, installed normal Mac GUI
and paired physical LAN acceptance remain open. The required stable repository
validation is recorded separately after this source checkpoint.
