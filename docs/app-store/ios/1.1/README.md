# Mac Companion iOS 1.1 release archive

**iOS 1.1 (167) was released on November 4, 2026.** Apple’s public catalog
shows version 1.1, and App Store Connect shows **Ready for Distribution**.
The released source is `028c955040b2429c6e6ede8f48adfe7a642c0d15`.
The official listing is <https://apps.apple.com/app/id6819496840>.
The archived [1.0 materials](../1.0/README.md) remain unchanged.

## Verified release state — November 4

The corrected October 30 submission
`609f17ea-1224-4399-84d5-4cdc62714fc8` is **Review Completed**. All six items
are Approved: iOS 1.1 (167), 14-day Trial, Lifetime Pro, Remote Desktop,
SSH Terminal, and Trackpad & Keyboard. No further submission is needed for 1.1.
Manual release was selected during preparation and review; the owner subsequently
reported publication, which was independently verified in the public catalog.

Build 167 completed processing and remains Testing in Internal Testing (1 tester)
and Public Beta (3 testers) as of this check. The executable came from successful
Xcode Cloud build 166; its internal-only upload is separate from normal export 167.
The public beta link remains <https://testflight.apple.com/join/pFeKTuux>.

A later 1.1 upload, build 169, failed with Apple errors 90186 and 90062 because
the 1.1 version train is closed after approval. This does not affect the released
build. The next development marketing version is 1.1.1; the app and Live Activity
extension must advance together. This archive continues to describe shipped 1.1.

## Features included in the released source

- Saved key/shortcut sequences shipped in [PR #40](https://github.com/Jenny-Media/MacCompanion/pull/40),
  merge `9f5e1b9`. It is an ancestor of the build 167 source.
- iOS Copy Text from Screen shipped in [PR #11](https://github.com/Jenny-Media/MacCompanion/pull/11),
  merge `3ec3942`, with later selection/session refinements in
  [PR #19](https://github.com/Jenny-Media/MacCompanion/pull/19), merge `796012f`.
  Both are ancestors of the build 167 source.

The open status of [#32](https://github.com/Jenny-Media/MacCompanion/issues/32)
tracks owner acceptance, rather than missing iOS delivery.
[#6](https://github.com/Jenny-Media/MacCompanion/issues/6) retains paused macOS
scope and any outstanding manual OCR/accessibility cases. Neither issue means
the iOS feature is unreleased. macOS development remains paused.

## Preserved copy and artwork

These files archive the approved 1.1 materials. They are not instructions or
authorization to modify a live record or submit a future release.

| Material | Source |
| --- | --- |
| Name and subtitle | [name](en-US/name.txt), [subtitle](en-US/subtitle.txt) |
| Description, keywords and promotional text | [description](en-US/description.txt), [keywords](en-US/keywords.txt), [promotional text](en-US/promotional-text.txt) |
| Review instructions | [App Review notes](en-US/app-review-notes.txt) |
| Build, URLs, release policy and verified release state | [metadata.json](metadata.json) |
| 34 screenshots and four Header/Search creatives | [screenshots.md](screenshots.md), [artwork-manifest.json](artwork-manifest.json) |
| Owner checkpoint and historical rehearsal | [reviewer-setup.md](reviewer-setup.md) |
| Release highlights | [release-summary.txt](release-summary.txt) |

The initial App Store release did not use a What’s New field.
[The unused draft](en-US/whats-new.txt) is retained as historical copy.

The description includes local Files backup/restore and optional iCloud Keychain
sync for Mac settings, keyboard layouts, shortcuts, saved text, menus and
positions. Credentials and trusted Mac identities remain local. Restore keeps
a recovery copy, replaces local Macs and controls, and turns sync off while
retaining existing cloud data.

Only reviewed final artwork is committed under `screenshots/`: 34 final JPEGs
and four opaque RGB PNG creatives. The manifest records their paths, dimensions,
SHA-256 and capture/reuse provenance. Raw captures, rejected uploads, fixtures,
source bezels, credentials and logs remain outside Git in the external
`ios-1.1-mac-grid-refresh/` evidence archive.

## Preparation and submission history

- October 29: the owner authorized converting the unreleased record to 1.1,
  attaching build 167, and applying the reviewed copy and screenshots. Nine Mac
  scenes were refreshed; 25 other screenshots remained byte-identical. The
  owner reported the requested device checks worked and authorized submission.
- The October 29 submission `89d28b52-2e38-4360-b89f-d75e06783895` entered review,
  then was withdrawn with explicit owner approval to correct separate creatives.
- October 30: four Header and Search Results replacements finished processing
  and were assigned to the main product page and Remote Desktop custom page.
  Reload checks confirmed those placements and the existing 34 screenshots.
  The six-item package was resubmitted as `609f17ea-1224-4399-84d5-4cdc62714fc8`.
  The external `creative-assets/resubmission-receipt.json` preserves that dated
  Waiting for Review checkpoint; it is not the current release status.
- November 4: public release and all six approvals were verified. The merged
  website release is recorded separately in [website deployment notes](../../../website-release-2026-11-04.md).

The owner’s device confirmation is recorded as owner-reported acceptance.
The unchecked rehearsal boxes do not represent failed tests or an unfinished
App Review gate. They preserve which detailed physical cases lack individual
agent execution records. Simulator artwork does not prove physical input,
signed iCloud propagation, purchases, or physical Duo acceptance.
