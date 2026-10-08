# Selected Window VideoToolbox checkpoint (2026-09-28)

## Failure and cause

The normal paired Simulator Window journey displayed video, but the selected
Window host chose software encoding. The same 800×532 Window fell back to
`libx264` with both ad hoc and Apple Development signed development packages;
the Desktop sessions on either side used VideoToolbox. Signing was not the
cause, and the development signing experiment was removed.

Sunshine's encoder viability probe uses a fixed 1920×1080 mode. Managed
selected capture is fixed to the client's exact admitted 800×532 mode. The
VideoToolbox path asked the selected ScreenCaptureKit adapter for the probe
size, which its exact-mode guard rejected before the actual session. Sunshine
then selected its software encoder. The pinned
`sunshine-selected-encoder-probe.patch` changes only the selected capture
probe to use the already resolved display's admitted dimensions. Desktop
probing and the actual negotiated stream mode are unchanged.

## Validation

- The revised pinned Sunshine source, submodules, and patches verify. The
  source-built host and normal Simulator Moonlight engine and iOS app rebuilt.
- The normal paired Window and App tests passed on the final source input.
  Each displayed Desktop, the selected surface, then Desktop again, with three
  native presentations. Window geometry was 800×532 and App geometry was
  848×580. All six streaming sessions used `hevc_videotoolbox`; none selected
  the software encoder.
- The run verified live TLS and pairing proof, exact client-key cleanup, host
  cleanup, and original Simulator app/data restoration. The App UI test's
  shortcut sheet now scrolls until Shift is actually tappable after Tab moves
  the sheet down; the original test attempted a zero-sized offscreen element.
- One final-source Window run failed during the selected-surface handoff when
  the media role closed before a new stream began. The exact-source retry
  passed without a source or package change. This intermittent early closure
  still needs a reliability investigation; it is not counted as a passing run.

## Evidence boundary

- Private report: `/private/tmp/maccompanion-selected-encoder-probe-window-simulator-20260928/report.json`,
  SHA-256 `4dd81e741880965f1f941810ac1b7ec42f3c678629605b08e53461baa16b0667`.
- Final-source Window report:
  `/private/tmp/maccompanion-selected-encoder-probe-final-window-retry-20260928/report.json`,
  SHA-256 `2ad96c4c4a08c2a6497d09fe25576f3194ba10065d0e953e42264f99ba0410cc`.
- Final-source App report:
  `/private/tmp/maccompanion-selected-encoder-probe-final-app-retry-20260928/report.json`,
  SHA-256 `692932cc88a6bfe2e6b9dddd1311df2d65212141885f7b57236340cf0d3fa88e`.
- The final Simulator/client source input SHA-256 was
  `0b4af5e5b4cb0e33835c301269d90f9993895aacb85fc31deaf4f52979d1348c`.
- Source-built host package manifest SHA-256:
  `79ea6411525e5538adc30f977e979d3d9708913f694c292d0f3f74f309218c29`.
- Packaged host executable SHA-256:
  `11b19e258e69ad069fe2d55d5b434ae812bc0b3c4c805635456ccc8ec4da1478`.
- Pinned probe patch SHA-256:
  `eca21bb6848e8e3cd01dc0bc2f05c7b38c6e7f80f72be8e0d507122155d2216d`.

The Simulator tests used disposable Mac consent and a synthetic final input
sink. They do not measure latency, bitrate or battery use, or establish paired
LAN or physical iPhone playback. The current development build is installed
on Mac and iPhone, as recorded in the companion installation checkpoint.
Viewport bitrate and corresponding-source completion remain separate work.
