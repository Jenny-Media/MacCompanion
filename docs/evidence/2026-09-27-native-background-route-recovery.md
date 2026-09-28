# Native background retirement and reconnect recovery

## Changes

The native lifecycle specification and indexed fixture now require immediate
background retirement. The normal UIKit owner observes the platform background
event synchronously, disables input, clears geometry and hides the surface before
asynchronous engine drainage. Returning to the foreground cannot revive that
renderer generation. A fresh explicit Control session is required.

Reconnect testing exposed an old media publication left waiting in the Mac local
XPC rendezvous. Its timeout could invalidate the menu connection after the old
interactive role pair had already ended, preventing a new Control request.
The normative local IPC contract and indexed fixture were updated first. The
role pump now reserves and joins exact-pair media retirement before cancelling
its sockets. The Mac route discharges that pair's pending publication and consumer,
disposes late records for known retired fences, and preserves replacement pairs.
Unknown mismatches remain errors. Retired history is bounded to 32 fences and
cleared on authenticated menu generation invalidation. Wire shapes, independent
grants, authentication and cryptographic vectors remain unchanged.

The Simulator journey now tests four native sessions, background input denial,
route loss and fresh-primary recovery. Its Observe check uses the verified
response receipt timestamps and primary identity: a fresh valid response can
contain an unchanged host status revision. The native test allowance is 360
seconds; the final journey completed in 234.025 seconds.

## Verified evidence

Stable Xcode 27.0 full `bash scripts/validate.sh` completed successfully with
109 indexed fixtures, golden vectors, package, platform and policy checks.
Seven focused pump/binding/route regressions pass, including concurrent
cancellation joining media retirement and replacement-pair isolation. Both SDK
candidates build; sixteen Simulator component tests pass, including immediate
background revocation and refusal to resurrect a displayed generation.

Native candidate source SHA-256:
`9f5eb56076054042a92ea68ffb9bc2a4d90706b697775685a49efc0f9a2da751`.
The six-framework inventory was refreshed after the final journey and matches
both SDK products. It retains release admission false.

Final live evidence root:
`/private/tmp/maccompanion-agent-xpc-evidence.a7w9zf5n`.
The report records one passing test, zero failures, four native decoded sessions,
native input admission, pointer/keyboard verification, background/route-loss
verification and verified cleanup. Combined source/helper/harness SHA-256:
`ec9b892ae1139375b6f70eca9e618b9d790dba8c2cf195103408eadf8e8e981d`.
Native probe support SHA-256:
`7caed6de87a16953af1341fae750c6b28d408723978be76889b00bcab24cabef`.

Each session verifies pointer delivery, direct iOS keyboard typing, visible
keyboard dismissal, Shift+Tab and Copy through the existing controls. Background
retirement refuses subsequent input; Stop leaves no queued input. Observe remains
available on the same primary across background/Stop and on a fresh primary after
route return. Pairing remains retained. All four sessions measure 5120×2134 capture
pixels, 2560×1067 logical points and 1920×800 encoded video.

Private logs:

- `/private/tmp/maccompanion-native-recovery-validation.log`
- `/private/tmp/maccompanion-native-recovery-handoff-validation.log`
- `/private/tmp/maccompanion-media-retirement-tests.log`
- `/private/tmp/maccompanion-native-recovery-iphoneos.log`
- `/private/tmp/maccompanion-native-recovery-simulator-sdk.log`
- `/private/tmp/maccompanion-native-recovery-live-simulator-verified.log`
- `/private/tmp/maccompanion-agent-xpc-evidence.a7w9zf5n/signed-simulator-report.json`

Generated compiler caches were reclaimed only after terminal process cleanup;
products, logs, inventories and result bundles were preserved.

## Scope and next work

This uses normal UIKit/session owners through real pairing, primary TLS and signed
local XPC with an experimental native adapter and isolated managed Sunshine.
The final host input sink counts authorized delivery; it does not post actual
system events. Loopback Simulator evidence does not prove installed normal apps,
physical iPhone behavior or TCC attribution. Permanent compositions remain disabled.

Packaging is next. The refreshed host inventory identifies six Homebrew dylib
links: three ICU libraries, miniupnpc, libcrypto and libssl. An installed host must
carry admitted dependencies and resolve them within its package. The iOS engine
still uses a checksum-pinned prebuilt OpenSSL framework; source-built OpenSSL and
transitive source/license provenance remain necessary. Then complete managed
process/signature/capture/TCC admission, normal-app composition, exact signed
installation and physical acceptance. Native focused App/Window capture and
visible-area bitrate remain pending.
