# Normal native session soak and iPhone update (2026-09-28)

The normal iOS Control channel had a reply timing gap: display catalog and
display selection commands installed their response waiters only after the
authenticated send completed. A correlated reply received during that send
cleared the pending request before a waiter existed, leaving the caller hung.
The waiters and deadlines now start before each send. A late send failure can
finish only its own still-pending request. The catalog regression reproduced
the hang before the fix; the focused catalog flow's 18 cases and a new early
display-selection reply case pass after it. No wire message or grant semantics
changed.

The updated normal iOS source input SHA-256 is
`5294389075d7388ceafb13f05672667eef254feeb986c12c115df8b4536f5c06`.
The `iphonesimulator` and `iphoneos` Moonlight frameworks and normal app were
built for that source. The required `bash scripts/validate.sh` passed with 116
indexed fixtures after the bridge and status-burst test changes. Private
validation log:
`/private/tmp/maccompanion-validate-20260928-current-targets-final.log`, SHA-256
`c98d5dbea72afa06f275f0d890608dbfc97edb60894a791d6649a9067e9607bf`.

## Normal app Simulator results

The dedicated iPhone Simulator completed ten consecutive paired Control
starts, fresh native presentations, keyboard/shortcut/pointer checks, and
Stop-to-Observe transitions. Each Stop required inactive capture, an idle
runtime and no queued media. The test also verified paired-workspace reopening,
TLS/pairing proof, client key cleanup, host cleanup, and restoration of the
original Simulator app and data. Private report:
`/private/tmp/maccompanion-display-reply-fixed-ten-session-diagnostic-20260928/report.json`,
SHA-256 `95f6f500359fe4a0f31b998b6c1b013f79c2f6f46ec516591a3ba9b282926c5f`.
An independent ten-session repeat on the same source also passed with the
same admission, input, Stop, key cleanup and Simulator restoration checks;
its diagnostic log recorded no rejected status request. Private report:
`/private/tmp/maccompanion-display-reply-fixed-ten-session-repeat-verified-20260928/report.json`,
SHA-256 `ec0461a08789b5ca4bbe0d1cd8db917df8702e8645c9f5459fc2bc75c3d597df`.

One earlier attempt on the same app source failed on the third Stop when the
disposable consent bridge closed a `journey-status` request. Its host log
recorded a backend health failure and local XPC invalidation. The precise
cause was not established; content-free error-case diagnostics were added to
the disposable probe before the successful repeat. The failed attempt's
report is retained at
`/private/tmp/maccompanion-display-reply-fixed-ten-session-20260928/report.json`,
SHA-256 `2264670c767120d38a093806c154f376c6ed6ec8e81699a11cc57f64352871fc`.
It remains an intermittent reliability risk rather than a passing result.

The failed status request returned an immediate transport EOF after Stop. The
disposable signed Simulator bridge could reject a new request while the prior
response socket was still closing; that timing is a plausible explanation,
not a proven cause of the earlier failure. The bridge now waits up to one
second for that socket handoff, keeps administrative commands serialized, and
records a distinct busy-timeout diagnostic if the wait expires. A new
ten-session run passed with this bridge. Private report:
`/private/tmp/maccompanion-serialized-bridge-ten-session-20260928/report.json`,
SHA-256 `870bac3743f56186ba7d2cee6f6d9d4099c7d27f381799c66ac6b661873d837d`.
The paired Simulator test then added twelve immediate status reads after
each Stop. All ten sessions and 120 additional post-Stop reads passed, with
inactive capture, idle runtime, an empty media queue, and full cleanup and
Simulator restoration. The host log recorded no bridge rejection or busy
timeout. Private report:
`/private/tmp/maccompanion-serialized-bridge-status-burst-20260928/report.json`,
SHA-256 `e91cf934f547e4877de8a76fa7d4bd5ff7980427a24107438c518e86ab279ed4`.
The normal app source fingerprint is unchanged; the bridge and test remain
disposable validation tools under `Experiments/`.

A separate exact-source Simulator run kept one normal Control session active
for 30 minutes. Thirty one-minute checkpoints required rising host media
record counts, a single native presentation, available keyboard input, and a
new host pointer event. Final Stop, idle runtime, empty media queue, key
cleanup and original Simulator state restoration passed. Private report:
`/private/tmp/maccompanion-display-reply-fixed-thirty-minute-20260928/report.json`,
SHA-256 `644e0a0c838b65d85d45143bfd4de45cb0294031add19479c576bacff68bc915`.

These are normal iOS Simulator app tests against a disposable signed Mac Agent
with substituted Mac consent and a synthetic final input sink. The reports
show continuing host video production and app input usability; they do not
prove physical iPhone pixels, actual Mac input posting or installed Mac GUI
capture. The first-run Stop-status failure remains open for reproduction and
root-cause analysis because a passing stress run cannot establish its cause.

## Installed development apps

The normal Mac app at `~/Applications/Mac Companion.app` still passes strict
deep signature verification and has bundle ID `media.jenny.maccompanion`. Its
installed build precedes this iOS display-reply change; no Mac source was
changed for that fix.

The normal iOS app was built and signed with the existing Apple Development
configuration, then installed in place on the paired iPhone 18 Pro Max as
`media.jenny.maccompanion.ios`. Device inventory confirms version `0.1.0`,
build `1`. The signed executable SHA-256 is
`995de88ee1530d8afd9fd1fb81ab15488e9bfc79d0767cbc6c43a9f5b2935d1a`.
Private signing log:
`/private/tmp/maccompanion-display-reply-fixed-device-ios-signed-20260928.log`,
SHA-256 `ba16572629741da80f7dde3d06ba15c85f7889089ee7b31d72616a9495c26f42`.
Private inventory receipt:
`/private/tmp/maccompanion-display-reply-fixed-device-inventory-20260928.txt`,
SHA-256 `6213234b70eb877e5628fc5c31ea24481684fd2f1b04577f20caf0cf92b142d6`.
The previous and updated signed iOS builds have the same development team and
application identifier. No app uninstall or data clear occurred.

An attempted device launch was denied by iOS because the phone was locked.
Existing pairing, physical playback, real LAN/input behavior, and usability
on the phone remain unverified until an unlocked-device journey. Viewport
bitrate and release admission remain separate milestones.
