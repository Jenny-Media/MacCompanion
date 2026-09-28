# Normal app Window/Desktop transition soak (2026-09-28)

The normal paired iPhone Simulator flow exposed a Control exit on the third
surface inventory request. A display catalog refresh was pending at the same
time. The interactive primary reply receiver checked for any pending display
request before checking the reply's correlation ID, so it tried to decode the
surface inventory as a display catalog. The authenticated primary router then
closed the connection. A focused overlapping-request test reproduced the
failure before the fix and passed after the receiver matched the exact display
request ID. The client-primary-router specification now states this rule, and
the sole fixture index includes a display catalog response.

The first long Simulator run passed 14 replacements before temporary disk
exhaustion and the disposable Mac target's five-minute lifetime made its late
failure inconclusive. A retry with disk space failed early during selected
Window re-enrollment; the host recorded a local backend health failure, but
its retained logs did not establish a specific cause. The disposable target
now stays alive beyond the test's 900-second timeout and is still terminated
by runner cleanup. A Debug-only, content-free host diagnostic records whether
Control or selected-target freshness caused a retirement.

The subsequent exact-source paired Simulator run passed all 20 alternating
selected Window/Desktop transitions in one Control session and a second Control
session, with 22 native video presentations. Every transition required fresh
keyboard readiness and a host input event after presentation. The UI test also
executed keyboard, modifier and shortcut delivery. TLS/pairing proof, real
target inventory, selected Window admission, client key cleanup, host cleanup,
workspace restart and restoration of the original Simulator app/data passed.
Private report:
`/private/tmp/maccompanion-soak-long-target-run-20260928/report.json`,
SHA-256 `3b9e5b17215b68d50510918c57e6111a56ef25e2f35cd5df7461f661adeb6da0`.

The run uses disposable Mac consent and a synthetic final input sink. It is
normal iPhone Simulator app evidence, not a physical iPhone or installed Mac
GUI test. The installed Mac development app remains the previous signed build.

The corresponding normal iOS source and native engine were rebuilt for
`iphoneos`. Xcode's existing Apple Development configuration produced a
device build, and `devicectl` installed it on the paired iPhone 18 Pro Max
without clearing app data. The device's app inventory shows
`media.jenny.maccompanion.ios`, version `0.1.0` build `1`. The signed executable
has SHA-256 `58ef2f1893be9c5091c2597976ba051ec55ca9ce1a2e261eec480557bdf4cd7d`.
Private signed-build log:
`/private/tmp/maccompanion-window-soak-device-ios-signed-20260928.log`,
SHA-256 `4148a0eae29e7fa81404c25fa9a071016ec3bc19f46593640890410d1186570f`.
Local strict `codesign` verification returned `CSSMERR_TP_NOT_TRUSTED`, while
Xcode's signing build and the physical install succeeded. A launch attempt was
denied by iOS because the device was locked. Physical playback, real LAN/input
and viewport bitrate remain separate acceptance gates.
