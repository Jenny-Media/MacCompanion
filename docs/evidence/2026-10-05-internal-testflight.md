# Direct iOS client internal TestFlight — 2026-10-05

## Authorized scope

The user requested an internal TestFlight version and their existing App Store
Connect account as a tester. The artifact uses the normal direct iOS client,
built-in macOS Screen Sharing and optional Remote Login. No Mac application or
helper is installed. External testing, App Review submission and public release
are outside this checkpoint.

App Store Connect app: `6819496840` (`media.jenny.maccompanion.ios`).
Internal Testing group: `3711a8df-cb86-4a49-8153-29ab4dabc070`.
The existing account holder was added; no user, role or broader account access was
created. Automatic distribution is off so builds are selected deliberately.

## Archive and signing

`scripts/prepare_vnc_internal_testflight.py` requires the completed normal device
build report, checks all 572 application input hashes and the native library,
uses pinned package versions and rejects experimental source paths. The optimized
InternalTesting configuration excludes DEBUG and retains the direct-client
composition selector. The archive version is `1.0 (1)` using stable Xcode 27.0.

The existing Apple Distribution certificate signs the app and session widget.
Matching App Store profiles were created for the existing app ID and newly
registered existing widget ID `media.jenny.maccompanion.ios.session-status`.
No certificate or private key was created. Profiles are stored outside Git.
The archive verifies exact app/widget application identifiers, team identifiers,
existing private Keychain groups, `get-task-allow = false` and deep signatures.

The initial unsigned archive cannot be distributed by Organizer because it has
no team. A proposed development-signing command was rejected by automatic approval
review; it was not executed. The subsequent App Store distribution signing path
uses the installed certificate and exact profiles. An initial signed inspection
caught omitted explicit Keychain groups; the final archive includes and verifies
the existing groups before upload.

Final signed archive binary SHA-256:
`70895a6c7b938b8f4fed13fee8e49bd4dcdcf6ab93add4787bb9aecae88835e1`.
Final archive/report/logs are outside Git under
`/private/tmp/maccompanion-testflight-distribution-final-20261005/`.

Required stable-Xcode `bash scripts/validate.sh` passes after the final script
changes (`/private/tmp/maccompanion-testflight-validation-final-20261005.log`).
It also passes after the final TestFlight documentation update using explicit
stable Xcode (`/private/tmp/maccompanion-testflight-ready-validation-stable-20261005.log`).
A preceding sandbox invocation stopped at Swift package manifest evaluation;
the stable run with Xcode/cache access completed with exit status zero.
Trial/commerce Simulator evidence is in the preceding
[pricing checkpoint](2026-10-05-lifetime-price-and-pro-trial.md).

## Distribution state

Xcode Organizer completed the **TestFlight Internal Only** upload at 23:07 local
time. Organizer shows Uploaded to Apple for `1.0 (1)`. Upload Symbols Failed is a
non-blocking warning for the pinned OpenSSL framework, whose archive lacks a
matching dSYM. Application and widget symbols are present.

Apple processed build ID `f1be75fa-aba2-4423-aa3f-af02cefa6920`. The questionnaire
identifies standard encryption outside Apple OS facilities. The user confirmed
this internal beta is outside France; the France distribution answer was saved
as No. The preceding standard-algorithms selection was rechecked before saving.
The compliance prompt cleared, and no Info.plist encryption exemption was added.
Future public distribution, including France, requires a separate scope review.

What to Test is saved. The build is assigned to Internal Testing, whose page
confirms **1 Tester and 1 Build**. Its Builds tab shows `1.0 (1)`, **Internal**,
**Testing**, expiring in 90 days. Its Testers tab shows the existing account holder
as **Invited** on October 5, 2026. Invitation acceptance and physical TestFlight
installation remain unconfirmed. Screenshots are saved outside Git as
`maccompanion-testflight-invited.jpg` and `maccompanion-testflight-testing.jpg`
under the current task's visualization directory.

Browser tab control repeatedly timed out. Native Chrome control through cua_repl
recovered the visible TestFlight page and completed the compliance and assignment
actions, with the resulting tester and build states verified in the UI.
The dependency report remains `releaseAdmitted = false`; internal testing does
not satisfy external/public release gates.
