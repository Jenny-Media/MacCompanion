# Mac Companion iOS App Store materials — 1.0

Prepared locally on October 24, 2026. No App Store Connect write, build/media
upload, App Review submission, release or website deployment is authorized by
this preparation. macOS and visionOS release materials/packaging are outside
this change.

## Screenshot refresh — October 26, 2026

The current screenshot handoff contains 28 designed preview images using official bezels
and the approved Focused layout, with genuine macOS windows, configured keyboard
rows, clearer Compose Text and Tabletop leading the Duo sequence. The latest
revision keeps normal Mac title-bar controls, fixes the Pro keyboard label and
Duo Terminal corner clearance, enlarges iPad feature details, and clarifies the
no-helper setup headline. See [screenshots.md](screenshots.md) for the
gallery and provenance, [screenshot-copy.json](screenshot-copy.json) for canonical
headlines and order, and [capture-recipe.md](capture-recipe.md) for reproduction.
The dated store snapshot and original submission checklist below are historical;
re-read live App Store Connect state before any later submission. This refresh
changes no store fields, selected build, release metadata or localizations.

## Authoritative copy

Paste each UTF-8 text file without its final file newline. Existing `en-US` is
the only iOS version localization and app-info localization returned by the live
read; it is preserved. Do not remove or replace a localization added later.

| Field | Source | Limit checked |
| --- | --- | --- |
| Name | [en-US/name.txt](en-US/name.txt) | 30 characters |
| Subtitle | [en-US/subtitle.txt](en-US/subtitle.txt) | 30 characters |
| Description | [en-US/description.txt](en-US/description.txt) | 4,000 characters |
| Keywords | [en-US/keywords.txt](en-US/keywords.txt) | 100 UTF-8 bytes |
| Promotional text | [en-US/promotional-text.txt](en-US/promotional-text.txt) | 170 characters |
| App Review notes | [en-US/app-review-notes.txt](en-US/app-review-notes.txt) | 4,000 UTF-8 bytes |
| URLs, copyright, locale, release policy | [metadata.json](metadata.json) | Existing URLs and manual release preserved |
| What's New | `null` in metadata.json | Unavailable for an initial App Store version |
| Internal candidate summary | [release-summary.txt](release-summary.txt) | Not an ASC What's New field |
| Reviewer rehearsal | [reviewer-setup.md](reviewer-setup.md) | Final candidate rehearsal required |

Apple's [app-information reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
and [platform-version reference](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
were checked October 24, 2026. The latter specifies **bytes** for keywords and
Review Notes. Subtitle is shared app information across platforms: this PR stages
its wording only; applying it later requires checking that shared effect.

Run `python3 scripts/validate_ios_store_materials.py` or the required
`bash scripts/validate.sh`. This does not call App Store Connect. The authoritative
App Store marketing version in `Native/iOSCloud/project.json` remains **1.0** for
both app and session-status extension; build number 142 is unchanged. The legacy
`project.yml` development version is not a production version change.

## Historical live record inspected October 24 before editing

The authenticated GET-only snapshot is retained outside Git at
`/private/tmp/maccompanion-ios-1.0-release-20261024/asc-before.json`.

- App `6819496840`, bundle `media.jenny.maccompanion.ios`, primary locale `en-US`.
- iOS version `1.0`, `READY_FOR_REVIEW`, manual release; selected build **25**
  uploaded October 9. Its description and review notes still describe unencrypted
  desktop/input transport and omit Remote Login from Desktop setup.
- Five existing screenshots each in `APP_IPHONE_61`, `APP_IPHONE_67`, and
  `APP_IPAD_PRO_3GEN_129`: 15 originals remain unchanged in ASC. The snapshot
  preserves their IDs, filenames, checksums, image dimensions and delivery state.
- Latest build returned at inspection: **153**, valid, uploaded October 24.
  Processing validity alone does not establish source identity or release
  acceptance. This PR does not select it or any other build.
- The existing support, marketing and privacy URLs are preserved. Review contact
  and any private account records stay outside Git. No vendor sign-in/demo login
  is required; reviewer-owned Mac credentials are entered only in the app.

See [screenshots.md](screenshots.md) for current-source captures, provenance and
visual review. Originals and rejected attempts are retained separately outside
the application repository.

## Claims and acceptance

The source authority is [remote-desktop-mvp.md](../../../remote-desktop-mvp.md),
`Native/VNC/DirectDesktopSSHTunnel.swift`, `Native/Terminal/`,
`Native/VNC/DirectProAccess.swift` and [duo-workspace-qa.md](../../../duo-workspace-qa.md).
Desktop and Trackpad & Keyboard use built-in Screen Sharing inside a verified
SSH tunnel through Remote Login. Terminal and SFTP Files use Remote Login.
Files is available for the free saved Mac; Pro expands Macs/keys and customization.
No helper, QR pairing, legacy Observe/Act interface, audio, per-app/window capture,
prototype transport or virtual-display feature is advertised in these materials.

The comparison/acceptance archive is
`/Users/yihong/work/iphone-duo-compatibility/reports/`. Its current
`review-fixes-20261024/mac-companion/PENDING_LIVE_CHECK.md` supersedes historical
merge holds, and `iphone18-install-20261024/OWNER_ACCEPTANCE.md` records owner
confirmation of typing, Compose Text, pointer delivery, rotation and app return
on an ordinary **iPhone 18 Pro Max**, associated with development **1.0 (161)**
at reviewed `26ebeb2`. That is owner-reported manual evidence; the running version
was not independently reread during the check. It is separate from native Duo
Simulator synthetic-host posture/composer/viewport evidence. Older physical Duo
images and rejected Simulator repairs retain their original source identities.
Future physical Duo acceptance uses **TestFlight**. No live Mac session or remote
input was started for this materials task.

The branch was created from freshly fetched `origin/main`
`9a9fbfbcef809ed31be1ee48accaf3873ef24801`, GitHub's confirmed merge commit for
PR #45. Reviewed `26ebeb2` is included. Existing checkouts were preserved.

## Original submission gates recorded October 24

1. Review and explicitly authorize the final metadata/media application. Replace
   selected build 25 with a source-verified **1.0** release candidate covering
   these claims; this task performs no build upload or selection.
2. Complete the clean iPhone/iPad reviewer rehearsal on that candidate. Preserve
   owner acceptance at its recorded scope. Physical Duo live folds/keyboard/
   foreground acceptance remain a separate TestFlight follow-up.
3. Recheck current App Privacy/export answers, review contact, IAP review state,
   territory availability and media-slot acceptance in ASC. Preserve France's
   exclusion and manual release. Do not infer purchase/review approval from
   synthetic StoreKit or a processed build.
4. Deploy the revised iOS support/marketing copy only after separate publication
   authorization. Local site build/check does not update the live support URL.
5. Recheck Apple's field and screenshot requirements at submission time, then
   obtain explicit authorization for submission and eventual publication.

## Validation and copy review

Required managed `bash scripts/validate.sh` passed on Xcode 27.1 (27A9275):
**1,987 Swift tests across 42 result groups**, plus the repository/platform checks.
Evidence is retained at
`/private/tmp/maccompanion-ios-1.0-release-20261024/validation-retry/runs/20261025T032933Z-3425de618b3a`.
The first attempt ran out of disk space; its failed logs and cache were preserved.
Space subsequently recovered without this task deleting any cache or evidence.

The field validator passes: name 13/30, subtitle 28/30, description 2,449/4,000,
promotional text 155/170 characters; keywords 85/100 and review notes 3,305/4,000
UTF-8 bytes. Website generation, route/link checks and JavaScript syntax pass.
Final copy was read against the direct-client implementation and the live record:
SSH transport and prerequisites, free Files access, optional Pro/trial, supported
layouts, reviewer authentication and initial-release text are aligned. No
candidate build, media upload, IAP approval or physical Duo result is inferred
from these checks.
