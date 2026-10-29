# Mac Companion iOS 1.1 release materials

Prepared October 29, 2026 for **1.1 (167)**, source
`028c955040b2429c6e6ede8f48adfe7a642c0d15`. The owner authorized committing the
reviewed release copy, final artwork and manifest while keeping submission held.
The later Asset Library staging is recorded below. No production build was
selected, review reply sent, app submitted or published, or website updated.
The archived [1.0 materials](../1.0/README.md) remain unchanged.

## Candidate and store state

- Build 167 completed processing, its binary is Validated, and it is Testing in
  Internal Testing (1 tester) and Public Beta (3 testers). The public link is
  <https://testflight.apple.com/join/pFeKTuux>.
- The executable came from successful Xcode Cloud build 166 for the source above.
  Its internal-only upload is separate from the normal export numbered 167.
- The production record inspected October 29 remains **iOS 1.0 (157), Rejected,
  manual release**. Its description, review notes and other fields were preserved.
  Apple's October 27 VPN information request already has a clarification reply;
  the submission still shows Unresolved Issues. Do not send a duplicate reply or
  resubmit merely to clear that information request.
- A first released App Store version has not been established. The separate
  [What's New draft](en-US/whats-new.txt) is conditional copy, not an instruction
  to populate an unavailable initial-release field. Confirm the live version
  workflow before applying this package. Do not overwrite the rejected 1.0 record
  or cancel its submission as part of preparation.

## Asset Library staging and retained 1.0 record

On October 29, six new backup/sync images were uploaded only to Asset Library,
increasing its asset count from 162 to 168. At the last saved inspection
(20:07 UTC / 4:07 PM Eastern), three were ready with Add for Review available
and three still showed Processing. Those are dated observations; recheck live
processing before later application.

The owner explicitly chose **Keep the 1.0 record unchanged** rather than
convert the rejected record to 1.1. Eight release fields matched the before
snapshot, build 157 and manual release remained selected, and Save was disabled.
No new images were assigned to a version, no 1.1 draft was created, and build 167
was not attached to production. Existing screenshot selections, custom product
pages and the review conversation were preserved. Release text remains local.
Apple's [new-version workflow](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version/)
requires the current version to be Ready for Distribution before a separate
version can be created. Do not convert 1.0 or cancel its submission without new
explicit instructions.

## Copy to review

Use each UTF-8 file without its final file newline. `en-US` is the prepared
localization; preserve any additional live localizations.

| Field | Source | Limit |
| --- | --- | --- |
| Name | [en-US/name.txt](en-US/name.txt) | 30 characters; unchanged |
| Subtitle | [en-US/subtitle.txt](en-US/subtitle.txt) | 30 characters; unchanged shared app information |
| Description | [en-US/description.txt](en-US/description.txt) | 4,000 characters |
| Keywords | [en-US/keywords.txt](en-US/keywords.txt) | 100 UTF-8 bytes |
| Promotional text | [en-US/promotional-text.txt](en-US/promotional-text.txt) | 170 characters |
| App Review notes | [en-US/app-review-notes.txt](en-US/app-review-notes.txt) | 4,000 UTF-8 bytes |
| What's New, when available | [en-US/whats-new.txt](en-US/whats-new.txt) | 4,000 characters; conditional draft |
| URLs, locale, candidate and release policy | [metadata.json](metadata.json) | Existing identifiers, URLs and manual release |
| Final screenshots and provenance | [screenshots.md](screenshots.md), [artwork-manifest.json](artwork-manifest.json) | 34 reviewed exports; six staged in Asset Library |
| Reviewer rehearsal | [reviewer-setup.md](reviewer-setup.md) | Pending on the final signed candidate |
| Release highlights | [release-summary.txt](release-summary.txt) | Internal handoff, not a store field |

The description corrects the old saved-text exclusion: opt-in iCloud Sync now
covers Mac settings, both keyboard layouts, shortcuts, saved text, menu items and
positions. Credentials and trusted Mac identities stay local. Files backup is a
separate feature that works without iCloud; restore replaces this device's saved
Macs and controls, keeps a recovery copy, and turns sync off. The reviewer notes
include the VPN clarification and precise setup for the shared saved Mac login.

The source authorities are [keyboard layout sync](../../../keyboard-layout-sync.md),
[key previews](../../../keyboard-key-previews.md),
`Native/VNC/DirectLocalBackupSettings.swift`, `DirectLocalBackupStore.swift`,
`DirectRecoveryV1.swift`, and the direct SSH/VNC/SFTP clients. No Pro entitlement,
purchase approval, cloud-account delivery, physical acceptance or new transport
capability is inferred from a processed TestFlight build.

## Before later application and submission

1. Review this local copy and media. Re-read the production review thread and
   decide how the unreleased 1.0 record should be handled before any version edit.
2. Complete the [candidate rehearsal](reviewer-setup.md), including real-device
   backup/restore, credential and trust reconfirmation, and signed two-device
   iCloud propagation. Record results against build 167. Physical Duo acceptance
   uses TestFlight and remains separate from Simulator screenshot evidence.
3. Recheck App Privacy against expanded opt-in sync, encryption answers, IAP
   review items, review contact, localization/media slots, and availability.
   Preserve the existing France exclusion and manual release. No privacy answer
   or territory setting is changed by these materials.
4. Inspect support/marketing pages for outdated sync or backup guidance. Website
   updates are a separate publication step; existing URLs are retained here.
5. Obtain authorization for applying the concrete final draft and, separately,
   App Review submission. **Do not submit from this package.**

Run `python3 scripts/validate_ios_store_materials.py` and the required
`bash scripts/validate.sh`. The reviewed final JPEGs are preserved under
[screenshots/en-US/](screenshots/en-US/) with a hash/dimension manifest.
Raw captures, rejected probes, fixtures, build products and validation logs stay
outside application Git. No simulator is erased or deleted for release preparation.

The field validator and full required `bash scripts/validate.sh` passed on
Xcode 27.1 (27A9275). The final commit check also verifies every selected JPEG's
hash and encoded dimensions, and rejects altered exports, unlisted files and
non-final paths. Full validation evidence is in the external handoff's
`commit-validation/runs/20261029T202442Z-acc5d3f0728e/`. Native screenshot journeys passed
sequentially on the existing iPhone, iPad and Duo QA devices. The external
`verification.json` records image dimensions/hashes, source identity, reuse,
device retention and the preparation checkpoint. The subsequent staging receipt
is in the same external handoff's `asc-application-20261029/application-status.json`.

Apple's [field reference](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
and [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
were checked October 29, 2026. Recheck live requirements before later submission.
