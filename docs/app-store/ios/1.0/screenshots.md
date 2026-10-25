# iOS 1.0 screenshot handoff

All media remains outside application Git. The local handoff package is:

`/Users/yihong/.codex/visualizations/2026/10/25/01a17109-d76e-7d41-8c62-d77d9b3f58e1/mac-companion-ios-1.0/`

- `index.html`: copy and screenshot review gallery.
- `app-store-connect/en-US/`: **26 selected JPEG exports**, native dimensions,
  no alpha channel. No upload has been attempted.
- `originals/en-US/`: unchanged PNG originals of those selected images.
- `manifest.json`: per-file SHA-256, source attempt, device set, locale, dimensions,
  actual geometry and division, synthetic/no-transport scope, and executable/test
  provenance. `validation-summary.json` retains the required validation result.
- `copy/`: paste-ready local text and metadata. Repository sources remain
  authoritative; compare them again before any later ASC edit.

## Devices and sizes

| Folder under `app-store-connect/en-US/` | Simulator / runtime | Native exported dimensions | Images |
| --- | --- | --- | --- |
| `iphone/` | iPhone 17 Pro / iOS 27.0 | 1206×2622 portrait; 2622×1206 landscape | 7 |
| `iphone-large/` | iPhone 17 Pro Max / iOS 27.0 | 1320×2868 portrait | 5 |
| `ipad/` | iPad Pro 13-inch (M5) / iPadOS 27.0 | 2064×2752 portrait; 2752×2064 landscape | 7 |
| `duo/` | iPhone Duo / iOS 27.1 | 1398×2034 outer; 2853×2007 open/Book; 2007×2853 Tabletop | 7 |

The ordinary portrait sets show Desktop, Terminal, Trackpad & Keyboard, My Macs,
and the session menu. iPhone/iPad landscape examples show Desktop and Terminal.
Duo includes outer Desktop, fully open Desktop, Tabletop Desktop and Compose Text,
and Book Desktop, Terminal and Compose Text. Separate outer/inner slots must be
selected in ASC at the later authorized media application step.

Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
were checked October 24, 2026: the selected dimensions are listed, JPEG is
accepted, images cannot have alpha, and each device-size set can contain 1–10
images. The medium iPhone and 13-inch iPad required families are covered.
Recheck the live media editor and requirements before upload; a local size check
is not an ASC acceptance receipt. Raw Simulator PNGs have an alpha channel, so
they are retained as originals and are **not** the upload set. macOS `sips`
created separate quality-100 JPEG format conversions without resizing, cropping,
retouching or synthesizing UI.

## Build and localization provenance

- Application source: freshly fetched main at merged PR #45 commit
  `9a9fbfbcef809ed31be1ee48accaf3873ef24801`. All **642** declared normal-app
  build inputs match current source.
- Build: normal managed iOS Simulator builder, followed by an isolated hosted
  capture target. No Experiments code is linked into a release target.
- Capture app: **1.0 (142)**, using the app/extension version metadata from the
  unchanged production cloud project. It uses a private QA bundle ID,
  `dev.maccompanion.proqa.ios`, and is not a distributable build. The original
  normal development report remains **0.1.0 (1)** and is recorded separately.
- Xcode **27.1 (27A9275)**, Simulator SDK **27.1**; runtime per table above.
- Capture executable SHA-256:
  `53203425f6639a1f233ca4e6b515a58363e01b0fdf9e687bdce76941b116e79a`.
- Capture test source SHA-256:
  `a798ca571da7e1d43c44a66766f10cb850e62b3a5ca14fdf7c0b4e1d5f898562`.
- Language `en`, locale `en_US`, ASC locale **en-US**, Light appearance and Large
  Dynamic Type. Keyboard text is native English. There are no other existing
  ASC iOS localizations to replace or fabricate.
- Each final selected capture journey passed its opt-in XCTest. The three
  ordinary portrait runs, Duo native run, and iPhone/iPad landscape runs are six
  successful capture journeys. This is capture validation, not a full native
  application suite or live transport test.

## Visual review and acceptance limits

The selected rendered images were inspected for content, localization, cropping,
control placement and accidental real data. They show labelled synthetic desktop
and Terminal content, one fake `Studio Mac` record, and current controls. The
library uses Mirror Mac Screen rather than advertising virtual-display behavior.
No credentials, real saved Mac, personal desktop, Mac helper or prototype screen
is included. The session menu may truncate the deliberately long local-sample
name; this is the current compact control rendering. Terminal input keys that
require a live SSH session remain inactive in the no-transport sample.

Native Duo controls, rather than geometry overrides, selected Closed, Open and
Partially Open plus rotation. Measured Book is **951×669 pt** with a **40×669 pt**
vertical division at x=455.5. Measured Tabletop is **669×951 pt** with a
**669×40 pt** horizontal division at y=455.5. Compose Text stays visible above the
native keyboard in the selected Book and Tabletop images. These are synthetic
layout screenshots; no Send or live input delivery is claimed.

Original attempts remain under
`/private/tmp/maccompanion-ios-1.0-release-20261024/`: an interrupted initial
phone run, the old synthetic library preference, two native files whose requested
Book label actually measured Tabletop, a first-use keyboard tutorial image, and
empty landscape setup attempts. None is silently overwritten or included in the
selected export set. Historical comparison/physical evidence under
`/Users/yihong/work/iphone-duo-compatibility/reports/` is untouched.

Owner-confirmed ordinary iPhone live-input checks remain separate, as detailed
in [README.md](README.md). Further physical Duo acceptance uses **TestFlight**.
No physical device, real Mac connection, upload or release was used for capture.

See [capture-recipe.md](capture-recipe.md) for reproduction and local driver paths.
