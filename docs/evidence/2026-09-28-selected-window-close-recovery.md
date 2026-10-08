# Selected Window close recovery in the normal iOS app (2026-09-28)

The disposable normal-app Simulator journey now closes its own AppKit test
window after the signed Mac menu has admitted the selected Window's native
presentation. This exercises a selected target disappearing during a real
paired Control session, without capturing user content or changing a release
target.

The final run passed one UI test. The normal iOS app paired over the live
authenticated path, opened Desktop Control, selected the disposable Window,
and received two native presentation admissions. When that window closed,
the Mac local backend failed closed and invalidated its XPC endpoint; the
managed Sunshine process terminated. The iOS app showed **Stop Failed Session**
in its paired workspace, with its Remote Keyboard disabled. Tapping that
action restored **Request Remote Control**. The runner verified exact
client-key cleanup, host cleanup, and restoration of the prior Simulator app
data. The close trigger itself and the two native host logs were retained in
the private output.

Report: `/private/tmp/maccompanion-selected-window-close-verified-20260928/report.json`,
SHA-256 `646050b3aa0306ecc2366caa06ac3792018b4716c1be7e4a019bafad9ff08b86`.
Normal app source input SHA-256:
`a86b2ce1e9cf51ecbb033e861ed8db73cbe1b623954a830528ed7c33c568b4ac`.
The signed menu log records two `native-local-presentation-input-admitted`
markers, then `native-local-backend-failed` and `local-xpc-invalidated`.
Both transient Sunshine logs record termination. This journey uses a
synthetic final input sink; keyboard and pointer delivery were exercised in
separate selected Window journeys, not this close test.

Initial test attempts queried the disposable Mac status bridge after its
intentional XPC invalidation, and later asserted on a stale SwiftUI Stop
element that can remain in the accessibility tree during navigation cleanup.
The final test checks the visible failed-session recovery action and disabled
keyboard authority instead. It does not claim automatic re-selection of a
replacement Window, physical iPhone playback, actual Mac input, installed
Mac GUI capture, or visible-area bitrate behavior.
