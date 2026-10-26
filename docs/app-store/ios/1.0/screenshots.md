# iOS 1.0 designed screenshot handoff

All image files and native input fixtures remain outside application Git. The
current local handoff is:

`/Users/yihong/.codex/visualizations/2026/10/25/01a17109-d76e-7d41-8c62-d77d9b3f58e1/mac-companion-store-design-v7/`

- `index.html`: review gallery for the complete **28-image English preview set**.
- `exports/en-US/`: composed RGB JPEG exports, without transparency.
- `raw/`: unchanged native Simulator captures, geometry and capture manifests.
- `artwork-manifest.json` and `verification.json`: selected source, copy, build,
  device, locale, hashes and validation provenance.
- `artboards/` and `design.css`: editable composition sources.
- `sources/` and `evidence/`: external native capture/reproduction drivers and logs.

The selected visual direction is **Focused**: an official Apple bezel, a small
Mac Companion brand label and a one- or two-line headline. The native phone
keyboard is visible where useful. The phone hero focuses the genuine TextEdit itinerary above the keyboard. Compose Text uses the native docked panel; iPad Compose and keyboard customization use portrait devices for a larger view. Customization includes a proportionally enlarged crop of the same native configured rows, outside the device.
[screenshot-copy.json](screenshot-copy.json) is the authoritative headline and
ordering source. Native interface labels are never replaced by marketing text.

## Curated device sets

| Export subfolder | Simulator / runtime | Composed export dimensions | Images |
| --- | --- | --- | --- |
| `iphone18-pro/` | iPhone 18 Pro / iOS 27.0 | 1206×2622 portrait | 7 |
| `iphone18/` | iPhone 18 Pro Max / iOS 27.0 | 1320×2868 portrait | 7 |
| `ipad/` | iPad Pro 13-inch (M5) / iPadOS 27.0 | 2064×2752 portrait artboard; landscape or portrait device | 7 |
| `duo/` | iPhone Duo / iOS 27.1 | 2853×2007 landscape; 2007×2853 portrait | 7 |

Phone and iPad open with Screen Sharing, Terminal and Compose Text. Duo opens with Tabletop Screen Sharing, Book Terminal and Book Compose Text. These three
images each explain a core benefit independently. Images four and five cover
customizable keyboard rows (marked **Pro**) and Files over SFTP. Trackpad &
Keyboard follows on phone and iPad; Duo uses Book Screen Sharing in that
position. Built-in Mac setup closes every seven-image set. The My Macs images
remain preserved in the earlier set but are omitted from this sequence.

The iPad raw captures are 2752×2064 landscape, or 2064×2752 portrait for
Compose Text and keyboard customization. Each is placed proportionally inside
the matching bezel orientation on a portrait artboard. Duo Tabletop uses the unchanged
open-device bezel rotated into portrait, with the native portrait capture.

Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
were rechecked October 26, 2026: the required iPhone family is Dynamic Island
**medium**, and the required iPad family is **13-inch**. The large Pro Max and Duo
sets are additional coverage. Each family stays below the ten-image maximum;
JPEG is accepted and transparency is excluded. Recheck the live media editor
before any future upload. Local dimension validation is not an ASC receipt.

Apple's [screenshot guidance](https://developer.apple.com/help/app-review/guideline-reference/2-3-3-screenshots)
allows framing and explanatory artwork while requiring the app in use to remain
clear. Every composition preserves actual native controls, device geometry and
screen aspect ratio. The complete redesigned set supersedes the earlier raw
upload candidates; all 26 earlier images and the v2–v4 previews remain preserved
in their original external folders.

## Source and content provenance

- Latest fetched `origin/main`: `35a060ed36b7e2a7d77570a07d7e044d24d2a2fb`.
  Its application tree matches reviewed capture revision
  `3cede88ffe967095a73ad8acdbbd38a4c90b40f1` exactly. Merged PR #45 commit
  `9a9fbfbcef809ed31be1ee48accaf3873ef24801` is included.
- All 642 declared application build inputs are rechecked. The screenshot work
  does not change shipping code, dependency pins, version or packaging.
- Capture host: **1.0 (142)**, private QA bundle `dev.maccompanion.proqa.ios`,
  Xcode **27.1 (27A9275)** and Simulator SDK **27.1**. This is local Simulator
  provenance, not an uploaded TestFlight or App Store build.
- Language `en`, locale `en_US`, ASC locale **en-US**, Light appearance and Large
  Dynamic Type. The audited existing iOS localization set remains unchanged.
- Files, Trackpad & Keyboard and setup retain unchanged earlier native captures.
  Refreshed desktop, Compose Text, Terminal and configured-keyboard captures use
  current native views through the external opt-in QA fixture. No fixture or
  experiment enters a release target. Files uses a seeded synthetic directory;
  no file transfer is performed. Customization demonstrates Pro UI and is labeled
  **Pro** in the artwork.
- Mac content combines genuine Finder and TextEdit window captures containing
  only synthetic local files, placed on a bundled macOS wallpaper. It is a
  composition of real native windows, not an unmodified full-display capture or
  a live Screen Sharing connection. The previous fictional AI workspace remains
  preserved but is not selected in this revision.
- Terminal uses the repository's isolated SSH test fixture on the Simulator's
  loopback address, with an ephemeral key and public synthetic test login.
  Native controls have a real connected SSH input owner. Output is synthetic;
  displayed shell commands are not executed. This does not establish input
  delivery to a physical Mac or model a required Mac Companion server/helper.
- Compose Text and Files are core features; keyboard customization requires Pro.
  No remote Mac, system service, account, networking or security settings are
  changed for these captures.
- Setup uses built-in Remote Login for all modes, plus Screen Sharing for the
  desktop and trackpad. There is no required Mac Companion helper or server.
  No prototype virtual-display feature is advertised.
- Official Apple bezel assets are reused under the user's existing approval of
  the iPhone 18, Duo and iPad resource licenses. The matching medium iPhone 18
  Pro PNG comes from that same approved archive. Assets remain unmodified;
  composition uses placement, proportional sizing and portrait orientation.

## Validation and acceptance boundary

The handoff records each successful native capture journey and rendered-image
check. Review native geometry, keyboard/tutorial state, text legibility, bounds,
bezel aperture fit and per-file hashes before promoting any image. Full
`bash scripts/validate.sh` is required for the materials branch; local
beta-toolchain results remain provisional until the stable Xcode lane passes.

Duo uses native hinge and rotation controls, not injected geometry.
Book measures **951×669 pt**, with a vertical **40×669 pt** division at x=455.5;
Tabletop measures **669×951 pt**, with a horizontal **669×40 pt** division at
y=455.5. The flat open marketing bezel is not a physical folded-device photo.
Keyboard customization, Files and setup are native inner-display layouts; no separate fully open posture
acceptance is claimed for those captures. Native slider angle alone did not
clear the observed Book division, so it is not treated as posture proof.

Owner-confirmed ordinary iPhone live-input checks remain separate from synthetic
Simulator screenshots and fold evidence. Future physical Duo acceptance uses
**TestFlight**. Historical evidence under
`/Users/yihong/work/iphone-duo-compatibility/reports/` remains untouched.

All four existing Mac Companion materials QA Simulators are reused. No new
Simulator is created for this revision, and none is erased or deleted. Exact
UUIDs, final states, result bundles and rejected attempts are recorded in the external handoff.

This work stops before any App Store Connect field/build change, media upload,
App Review submission or publication. macOS materials and packaging are outside
scope. See [capture-recipe.md](capture-recipe.md) for reproduction.

The prior 21-image v5 set was uploaded and verified separately. This v7 set is
a local preview and has not been uploaded. The App Store version/build and
pending review confirmation are outside this revision. Final v7 validation,
sequential native capture journeys and rendering results are recorded in the
external `verification.json`; stable-toolchain and physical acceptance gates
remain distinct.
