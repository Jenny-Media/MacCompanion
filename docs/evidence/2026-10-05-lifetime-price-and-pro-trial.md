# Lifetime Pro pricing and optional 14-day trial

## Approved scope and Apple records

The user authorized creating the App Store product with a US lifetime price of
$9.99 and a 14-day free trial. The existing direct-client iOS identifier
`media.jenny.maccompanion.ios` is now registered with Jenny Media LLC. Registration
retains the installed application's identity; no certificate, profile, Keychain
group, Mac helper or additional Apple capability is introduced.

App Store Connect now contains:

| Record | Identifier | Price / state |
| --- | --- | --- |
| Mac Companion iOS app | 6819496840 | Free download; version 1.0 Prepare for Submission |
| Lifetime Pro non-consumable | 6819497277 / `media.jenny.maccompanion.pro.lifetime` | US base $9.99; Prepare for Submission |
| 14-day Trial non-consumable | 6819497930 / `media.jenny.maccompanion.pro.trial14` | $0.00; Prepare for Submission |

The saved product pages show English (U.S.) names/descriptions, all-country
availability, Family Sharing off, review notes and an actual Simulator capture
of the purchase screen. Price schedules include 175 countries/regions; Apple
provides comparable regional lifetime prices. The app's availability is configured
for release in all 175 regions, with the iOS app excluded from automatic Mac and
Vision Pro compatibility distribution. No build is uploaded or submitted for
review, and none of these products is live.

The pages initially reported creation errors although both records persisted.
Fresh visible record lists were checked before further work to avoid duplicate
creation. Screenshot processing can also overwrite unsaved notes: trial notes
were reapplied after processing and checked on a fresh page with Save disabled.
Lifetime notes and processed screenshot likewise appear with Save disabled.

## Trial contract and implementation

Apple's [App Review guideline 3.1.1](https://developer.apple.com/app-store/review/guidelines/)
permits non-subscription trials through a free non-consumable named XX-day Trial.
The separate product is named **14-day Trial**. Enrollment is explicit and there
is no subscription, renewal or automatic upgrade charge.

The normative direct-client profile and sole indexed fixture were updated before
implementation. The app verifies the product ID, non-consumable type and
revocation status. Its trial lasts exactly 1,209,600 seconds from verified StoreKit
`originalPurchaseDate`; restore, repeat purchase and reinstall cannot reset that
date. Verified history includes revoked trials, so refund does not reoffer a trial.
Unverified or incompatible history grants no access and prevents new enrollment.
The enrollment button requires the zero-price trial and the localized lifetime
product to be loaded, so the upgrade price is disclosed before starting.

Expiry is evaluated on foreground and with a bounded local deadline while running.
There is no per-frame work, account or time server. Offline evaluation uses device
time; rollback within a running process cannot extend the trial, but this is not
a tamper-resistant clock across launches. Lifetime access overrides trial expiry.
Expiry/refund retains saved data, free Mac/key choices and active connections.
The permanent basic tier remains available without a time limit.

## Verification

- Required `bash scripts/validate.sh` passes on stable Xcode 27.0 (exit 0), with
  `MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1` and 133 indexed fixtures. Log:
  `/private/tmp/maccompanion-trial-validation-20261005.log`.
- Hosted native Simulator suite: 86 tests executed, one opt-in capture skipped,
  zero failures (85 passed). Real `SKTestSession` checks cover product lookup and
  $9.99/$0.00 prices, verified trial purchase, restore with unchanged end date,
  duplicate enrollment, exact expiry, relaunch, refund history, retained free
  choices and lifetime upgrade. Indexed cases include invalid/future transactions.
  Result: `/private/tmp/maccompanion-trial-simulator-20261005/QA/Results.xcresult`.
- The suite's wrapper could not obtain the data container after Xcode shut down
  the isolated Simulator. This happened after TEST SUCCEEDED; its subsequent
  independent OpenSSH export step is not claimed as rerun here. That feature's
  previous independent checks are recorded in the named-key evidence.
- A separate opt-in screenshot test passes after the final UI changes. Five
  actual production-view captures cover light/dark, large text, active trial and
  lifetime unlock. Light/dark and large text were visually inspected. Images
  remain outside Git and the harness is excluded from the normal app.
  Result: `/private/tmp/maccompanion-trial-screens-20261005.xcresult`.
- The normal Simulator application rebuild passes with exact source/dependency
  hashes in `/private/tmp/maccompanion-trial-simulator-20261005/build-report.json`.
  The first compile exposed actor isolation in task cleanup; `isolated deinit`
  corrects it and both the native tests and normal build pass afterward.

## Remaining distribution work

Apple requires the first non-consumable purchases to accompany a new app version
for review. A distribution build, app listing/privacy/export/review metadata,
review submission and Apple approval remain separate gates. Local StoreKit tests
are not evidence of a live App Store purchase. The trial update has not been
installed on the physical iPhone in this task. The prior reviewed feature update
remains installed. No commit, push or public release was performed.

This checkpoint supersedes earlier statements that the iOS App ID/store records
were unregistered and that 19.99 was only a proposed local test price. Historical
Mac-host release gates remain archival; the current MVP has no Mac app/helper.
