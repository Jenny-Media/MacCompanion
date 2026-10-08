# Selected Window geometry loss and recovery (2026-09-28)

The disposable AppKit target can now move or resize its synthetic Window after
the normal paired iOS app verifies the selected Window's second native
presentation. A Debug Simulator-only status command emits a readiness marker;
the runner changes the Window only after that marker. This avoids changing the
capture geometry before the UI test has finished checking its live stream.

Moving or resizing the Window invalidates the selected capture's exact bounds.
The signed Mac menu reports local backend failure and XPC invalidation, and
the managed Sunshine process terminates. The normal iOS app returns to its
paired workspace, disables Remote Keyboard, shows **Stop Failed Session**, and
shows **Request Remote Control** after that failed session is stopped. The
runner verifies the target actually performed the geometry change, both
native presentation admissions, client-key cleanup, host cleanup, and
restoration of the prior Simulator app data. This is safe retirement, not
seamless video continuation through a move or resize.

- Move report: `/private/tmp/maccompanion-selected-window-move-20260928/report.json`,
  SHA-256 `e050872a3b09e7a7285e608dbc411f938737e876dccf63c5bc4dd4ef765cd71e`.
- Resize report with explicit readiness marker:
  `/private/tmp/maccompanion-selected-window-resize-ready-20260928/report.json`,
  SHA-256 `1683be96858ab35293782034426cfaa9392b1761beb3993d68a671568fe7d979`.
- Close regression on the same ready-synchronized fixture:
  `/private/tmp/maccompanion-selected-window-close-ready-20260928/report.json`,
  SHA-256 `ca96081d9f56ed443ba956dad84f967c5b55e9e74afc13522314b4c9ff8e8e33`.

The stronger resize diagnostic tapped **Request Remote Control** after stopping
the failed session and required a fresh decoded stream. It did not reach that
stream within 45 seconds; the UI returned to its paired workspace. Report:
`/private/tmp/maccompanion-selected-window-resize-restart-ready-20260928/report.json`,
SHA-256 `8d5c6dbf460cce55aad5902ae39cad8edbf0a59aa53c08129d7409ffa40aa94c`.
The failing run cleaned its owned host, keys, and Simulator state. The
disposable Mac menu records local XPC invalidation and does not launch a
replacement signed menu generation. The normal Mac dashboard has an
unavailable-product recovery path; this disposable setup does not exercise
it. Thus the failure identifies a missing end-to-end restart check, not a
confirmed installed-app restart failure.

The completed restart check now starts a replacement signed disposable Mac
menu after the old local XPC generation is invalidated. The replacement
re-publishes the isolated Agent's existing durable Control admission through
signed local XPC. The normal paired iOS Simulator app requests Control again,
receives a fresh native Window stream, retains an enabled keyboard for five
seconds, and stops the new session. The replacement menu reports advancing
media records, a completed native backend retirement, and an idle runtime with
no active capture or queued media. Three native presentations were admitted
across the two disposable menu generations. The one UI test passed; the runner
verified owned host cleanup, client-key cleanup, and Simulator data restoration.
Report: `/private/tmp/maccompanion-selected-window-resize-reactivated-v5-20260928/report.json`,
SHA-256 `76bd130aed1e18062221677be2b429e50fce6520c19d0593ffd5d061c417d13e`.

An earlier replacement-menu run tapped Stop soon after the restarted keyboard
became enabled. Its UI test returned to the workspace, but the disposable Mac
backend reported `unavailable` and invalidated local XPC before the runner
could verify idle state. A separate no-delay rapid Stop variant now passes in
two paired Simulator runs. Both replacement menus report completed backend
retirement and idle capture with no queued media; both runs clean the owned
host, client keys, and Simulator data. Reports:

- `/private/tmp/maccompanion-selected-window-resize-rapid-stop-20260928/report.json`,
  SHA-256 `af48329a558ec0d2e9298a70340e89786e901ffc9f01b9c239cbf4b2044c82d3`.
- `/private/tmp/maccompanion-selected-window-resize-rapid-stop-v2-20260928/report.json`,
  SHA-256 `0f5215acaace31d3c49354318622ab1801d5e0ee3993251662917736e6987834`.

The earlier failure is still unexplained, so these two passes do not establish
that rapid Stop is free of intermittent teardown failures.

This uses a Debug Simulator-only consent bridge and a disposable Mac menu. It
does not establish that the installed Mac dashboard automatically recovers its
own menu generation or that a physical iPhone receives the restarted stream.

The tests use substituted Mac consent and a synthetic final input sink.
Physical iPhone playback, actual Mac input, installed Mac GUI recovery,
same-LAN behavior, and automatic geometry re-enrollment remain open.
