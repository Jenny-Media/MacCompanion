# Native client frame continuity (2026-09-28)

The source-built Sunshine host logged repeated requests for an IDR keyframe
during earlier passing Desktop, App, and Window Simulator sessions. Those
journeys checked the first visible frame and continuing host media production,
but did not check that later picture samples still reached the iOS display
layer. The host errors alone did not establish a client freeze.

The Moonlight owner now atomically counts complete picture samples accepted by
the local display layer. In Debug builds, its driver records fixed, content-free
progress or stall codes every five seconds. The paired normal-app Simulator
runner has a one-minute Control hold that checks host media and input every ten
seconds, then requires at least eight client progress checkpoints and no stall
checkpoint after progress begins. No pixels, host names, pairing material, or
typed input enter this diagnostic.

## Verified Simulator results

The one-minute paired normal iOS app journey passed with one native presentation,
six rising host media checks, fresh admitted input, 20 client frame-progress
checkpoints and zero stall checkpoints. The corresponding Sunshine log contained
four IDR-request errors, so those errors did not coincide with a stopped client
frame queue in this run. Stop, paired-key cleanup, host cleanup and restoration
of the original Simulator app and data passed. Private report:
`/private/tmp/maccompanion-frame-progress-one-minute-20260928/report.json`,
SHA-256 `e055eb9b12a94eb1f3e4dcb35ea4ff4ee57c94a2245fba1cd0bfb44d4c499dd7`.

A separate current-source selected Window journey passed pairing, three native
presentations, keyboard, pointer, Copy and Shift+Tab, Stop/restart and cleanup.
Its client log contained five frame-progress checkpoints and no stalls. One
host session logged 24 IDR-request errors while the client recorded later
frame progress. This is short-session evidence, not a sustained Window stream
measurement. Private report:
`/private/tmp/maccompanion-frame-progress-window-20260928/report.json`,
SHA-256 `99f4ff574e5015bb21bc064db16c35bcd65f04608ceac2d31d8a63842766f371`.

Both journeys used source input SHA-256
`a86b2ce1e9cf51ecbb033e861ed8db73cbe1b623954a830528ed7c33c568b4ac`
and the source-built Simulator Moonlight engine SHA-256
`2dcbc90c3ac1eff325d59f675054c2fad21fe276e8d7bb0170f58d29b3a103e2`.
The normal Simulator executable SHA-256 was
`53d7cf8534ed10d47e83aac77a645bfdd7f33d997dd00d86c6199347e88b34a7`.
The embedded Moonlight lifecycle tests passed. The required
`bash scripts/validate.sh` passed with 116 indexed fixtures; private log:
`/private/tmp/maccompanion-validate-20260928-frame-progress.log`,
SHA-256 `0f02fd0217133115c949663d5c58b000c0c63f38b9a6de4c5fb5c52cf74574ab`.

## Development iPhone update and limits

The matching `iphoneos` engine and normal app built from the same source input.
Xcode signed the app with the existing Apple Development profile, which includes
the paired iPhone and matches the app identifier. The signed executable SHA-256
is `5b3a5fd1c3764f498f63288f5496b3f960e1b70238bd0772871259e4747131ef`.
The in-place installation succeeded, and the device inventory lists Mac
Companion version 0.1.0, build 1. Private signing log:
`/private/tmp/maccompanion-frame-progress-ios-signed-20260928.log`,
SHA-256 `316829d0f14490e9c5ede8f4fa0ff858d4ae8fc18eacada871bfaee689225e4e`.
Private inventory receipt:
`/private/tmp/maccompanion-frame-progress-device-inventory-20260928.txt`,
SHA-256 `d2be0172bb2c650a5939138a9807e1b46700a1fc76dd92576afdfb94623f3096`.
No app uninstall or data clear occurred.

The frame count proves successful local picture enqueue, not displayed pixel
changes, latency, bandwidth, or image quality. The Simulator uses disposable
Mac consent and a synthetic final system-input sink. The installed Mac app was
not changed by this client diagnostic. iOS denied a launch earlier in this turn
because the phone was locked; physical playback and real Mac input remain open.
