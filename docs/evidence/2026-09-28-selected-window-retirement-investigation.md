# Selected Window retirement investigation (2026-09-28)

One exact-source paired Simulator Window run previously lost its media role
before a selected stream presented. The retained Sunshine log showed its
termination handler during encoder probing; the Agent then failed lease renewal
with `endpointClosed`, and the iOS media pump reported `invalidRead`. The
earliest reason for the helper termination is not established by those logs.

The Mac backend watcher and managed video process watchdog now emit
content-free diagnostics when they initiate retirement. They distinguish a
failed watcher check from lost Control admission or a passed deadline, and
record whether the selected capture was still current. No authority, wire
format, credential, screen content, or release target changed. These events
did not fire in the passing run below, so this change improves the next
failure's attribution; it is not a claimed fix for the intermittent closure.

The normal paired Window Simulator journey passed on the updated source:
Desktop, selected Window, then Desktop, with three native presentations and
input delivery. The selected Window used `hevc_videotoolbox`; no session chose
`libx264`. The normal app's shortcut modifier path was exercised once, while
pointer and keyboard delivery were exercised in each session. The UI test now
scrolls the shortcut sheet without querying controls that SwiftUI removes from
the accessibility hierarchy while offscreen.

The run confirmed live TLS and pairing proof, exact client-key cleanup, host
cleanup, and restoration of the original Simulator app data. Private report:
`/private/tmp/maccompanion-window-retirement-simulator-shortcuts-once-20260928/report.json`,
SHA-256 `0ebd5cdcf7f49e3386d316f977aa29ca4b9f6b2b76a956a7371c06f1a63db1f7`.
Normal source input SHA-256:
`1bae3f9bc05b81625462471b7375bae3d800e34c7e0f3314616a9d250e3dd06b`.

Earlier retries were interrupted by a full temporary volume and an Agent job
left listening on the disposable test port. Its executable and state paths
were verified to belong to the interrupted test, and that exact launchd job
was stopped. The original Simulator app data was restored from the runner's
backup before further tests. Only rebuildable Xcode caches from completed
runs were removed; private reports and logs were retained.

This Simulator pass does not establish physical iPhone playback, paired LAN
behavior, or the cause of the earlier intermittent shutdown. The installed
Mac and iPhone development apps were not changed during this investigation.
