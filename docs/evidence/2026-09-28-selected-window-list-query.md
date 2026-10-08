# Selected Window list query correction (2026-09-28)

The normal Mac selected-Window admission check and local activation check both
called `CGWindowListCopyWindowInfo` with `.optionIncludingWindow` alone. Apple's
[Core Graphics documentation](https://developer.apple.com/documentation/coregraphics/cgwindowlistoption/optionincludingwindow)
requires combining that option with an above- or below-window option for a
meaningful result. These checks could therefore reject a still-current
selected window. The exact earlier media-role closure cannot be attributed to
this query from the retained logs, so it remains an intermittent reliability
issue until reproduced with the content-free retirement diagnostics.

Both checks now query on-screen windows and locate the exact selected window
ID and owning process. The selected capture still requires the same bounds,
display, process launch, scale, rotation and Control deadline before video or
input can continue. Missing, wrong-owner and duplicate IDs fail closed. The
focused test includes a sibling window before the selected one.

The focused test and full `bash scripts/validate.sh` passed with the Mac GUI
available, including all 115 indexed fixtures. In the restricted environment,
the unrelated desktop test failed because `CGMainDisplayID()` was zero; that
test passed immediately with GUI access. The exact-source normal paired
Simulator Window journey then passed Desktop → selected Window → Desktop with
three native presentations, TLS/pairing proof, keyboard, pointer,
exact-key cleanup and restoration of the original Simulator app/data. The
three retained Sunshine logs selected `hevc_videotoolbox` and did not select
`libx264`. Private report:
`/private/tmp/maccompanion-selected-window-query-simulator-retry-20260928/report.json`,
SHA-256 `a9dd831de075aaf40ed92dd9eefda2ea25a1db86bed45ec5bd45035d4391be20`.
The first live attempt exhausted temporary disk during a rebuild before
pairing; only this turn's rebuildable Swift cache was removed, and the retry
passed.

The signed normal Mac Debug app was then rebuilt and staged with the exact
previously tested Sunshine package. The stage gate verified its complete
native catalog and containing signature. The installed development bundle at
`~/Applications/Mac Companion.app` was replaced, with the preceding bundle
retained at `/private/tmp/maccompanion-installed-pre-window-query-20260928.app`.
The installed and staged menu executables both have SHA-256
`ca4492ea488428468eb855ef3304291abcd1cabf79afe4e6ebfc354aa305028f`;
the previous executable was
`c7fe2feeaa553030e4b56744fcb4f5502b3135dc87e914e6a3a6cc528eefc8f3`.
The existing registered Agent job was restarted without changing its
registration, and both new menu and Agent processes were observed loading
from the installed bundle. The iPhone installation was not changed because
this correction is in the Mac app only.

This is Simulator evidence with disposable Mac consent and a synthetic final
input sink, plus signed Mac installation evidence. Installed Mac GUI capture,
physical iPhone playback, real LAN/input, 20 consecutive transition journeys,
viewport bitrate and corresponding-source completion remain open.

Correction: the earlier UI test guarded the modifier/shortcut block with
`cycle == 0`, while cycles start at 1. The report's modifier/shortcut flag for
this run overstated what the UI test executed. The later
`2026-09-28-window-transition-soak.md` run executes that block and verifies it.
