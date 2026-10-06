# Saved Macs optimized validation and Vercel website — 2026-10-06

## Saved Macs root cause

The user reports the normal internal TestFlight app displays “Saved Macs could
not be read” on every launch. A read-only copy of its saved-Mac settings file
was inspected outside the checkout, without copying credentials or recording
real names, addresses or input content here. The schema-3 file contains three
valid canonical records. The device file was never changed or deleted.
The temporary settings copy was removed after diagnosis.

The actual `DirectMacRecordV1` normalizer accepts that file without optimization,
but rejects it when compiled with `swiftc -O`. Per-condition checks isolate the
bound `CharacterSet.controlCharacters.contains` predicate: in this optimized
context it reports ordinary names as containing control scalars. Replacing it
with an explicit scalar closure accepts all three unchanged records. This is a
context-sensitive optimized predicate failure, not malformed JSON or evidence
of lost credentials. The original TestFlight source hash matches the failing
source. The analogous named SSH key validator is corrected as well.

The authoritative direct-client fixture now indexes 11 synthetic name cases:
ASCII, Unicode, emoji, trimmed whitespace, empty/whitespace-only, newline, NUL,
bidirectional format control and length limits. `verify_direct_mac_names.py`
extracts the actual native validators and executes them in both `-Onone` and
`-O`, including canonical schema-3 saved-record round trips. It fails with the
original predicate and passes after the correction. Invalid control/format
characters remain rejected; no wire behavior, credentials or identity changes.

Stable Xcode 27.0 `bash scripts/validate.sh` completed with exit status zero,
including this new regression gate. The validation log remains outside Git at
`/private/tmp/maccompanion-validation-saved-macs-20261006.log`.

## Website

The user approved the v1 website and authorized Vercel deployment to
<https://mac.jenny.media/>. The authenticated `xcv58s-projects` team now owns the
`mac-companion` Vercel project. The custom domain verified against its existing
Vercel DNS; no DNS changes were required. Only the built static public files
and Vercel configuration were uploaded, not native sources or local data.

Final production deployment is `dpl_6r6Xqsoff7199bP5vakTPGXXLQXf`, READY with
`mac.jenny.media` assigned and no alias error. Production serves `/`, `/privacy/`,
`/support/` and the approved hero artwork with HTTP 200. The three page bodies
and license file match generated `dist/` bytes exactly. Responses include
`nosniff` and `X-Frame-Options: DENY`. Browser inspection confirms the expected
page and loaded images.
The verification screenshot remains outside Git. The earlier owner-private
Sites preview is separate. Website publication does not release the iOS app.

## Updated internal build

The normal source-built device build passed. Optimized internal TestFlight
`1.0 (2)` archived with the existing app/widget identities, certificate,
profiles and Keychain groups. Exact native input hashes and strict signatures
passed. The signed application binary SHA-256 is
`6ce2dcf76a2f8c29897c9aef3f7c8b830665cb80d66f0d6e2419868f871207cc`.

Xcode Organizer completed TestFlight Internal Only upload at 00:29 local time
and marks build 2 Uploaded to Apple. An initial account check failed; a retry
succeeded without changing accounts or credentials. The pre-existing OpenSSL
dSYM warning remains non-blocking; app and widget symbols are present.
Archive/report/logs are outside Git under
`/private/tmp/maccompanion-testflight-distribution-saved-macs-20261006/`.

Apple processed build `2a9bcbd8-4796-43fe-96ed-3c493922c68c`. The same standard
encryption and outside-France internal beta answers were rechecked and saved;
no exemption declaration was added. Focused What to Test notes are saved, and
the existing Internal Testing group is assigned with one tester. Physical
TestFlight acceptance remains a separate check. The group's Builds page confirms
`1.0 (2)`, Internal, Testing, expiring in 90 days. Availability proof is saved
outside Git as `maccompanion-build2-testing.jpg` in this task's visualization
directory. The development dependency graph remains
`releaseAdmitted = false`; this checkpoint does not authorize public app release.
