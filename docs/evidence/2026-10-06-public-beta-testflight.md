# Connection sheets and public-beta TestFlight — 2026-10-06

## Authorization and source

The user requested committing the approved changes, publishing a new TestFlight
version, creating a public tester group, and submitting the latest beta build
for review. App/source commit `768708b6e259ef243c34bccd353cfc1b04a52e7e`
contains the approved compact connection sheets, headerless Terminal controls,
pinned decoder correction, normative fixtures, tests, and metadata-only paused
host-capture investigation. No Mac helper is introduced.

## Verification and archive

- Required stable-Xcode `bash scripts/validate.sh` passes before upload.
- The prior final stable Simulator build and hosted direct-client QA pass:
  129 tests, one intentional capture skip, zero failures; the final 10-test
  recovery/layout/capture check also passes.
- The fresh normal device build passes and all 577 frozen application inputs
  match the committed sources. The optimized archive is **1.0 (5)**.
- Xcode 27.1 RC (`27A9275`, SDK 27.1) preserves the previously uploaded Duo APIs;
  the deployment floor remains iOS 26. RC evidence remains provisional. Exact
  physical acceptance is separate from earlier local development-build testing.
- Existing app/widget IDs, distribution certificate, exact App Store profiles,
  private Keychain groups, strict deep signatures and disabled debugging verify.
  The archive excludes experimental sources.
- Signed application binary SHA-256:
  `fba0217b8ba4688cdb067bb9075c4a60d75ce6543ef9045278746886b5f29386`.

Archive, source-bound report, export options and logs remain outside Git under
`/private/tmp/maccompanion-public-beta-20261006-*`. The dependency graph remains
`releaseAdmitted = false`; the explicitly authorized external beta is not a
production App Store admission.

## Upload and review preparation

Earlier builds 1–4 were uploaded as Internal Only. Build 5 uses the normal
App Store Connect route with `testFlightInternalTestingOnly = false` and a fixed
build number. Xcode confirms **Upload succeeded / EXPORT SUCCEEDED** at 22:57
America/New_York. App Store Connect independently lists **1.0 (5), Processing**,
build `f20f0a2e-ed5f-4292-97ff-3a60135e0359`. Processing completed and the
standard-encryption / previously authorized outside-France declaration was saved.
Build 5 reached **Ready to Submit** and was assigned to the existing Internal
Testing group, which has one existing tester. Its Builds page confirms **1.0 (5),
Testing, expires in 90 days**, with five assigned builds. Build-specific What to
Test notes are saved. The latest observed physical installation remains build 4;
installation/acceptance of build 5 is not claimed. Availability proof is outside
Git as `maccompanion-testflight-build-5-testing-20261006.jpg` in this task’s
visualization folder.

The existing OpenSSL missing-dSYM warning is non-blocking; app/widget symbols
are included. No new certificate, profile, identity or account access was created.

The beta description and HTTPS marketing/privacy URLs have been saved. Both
public support and privacy pages return HTTP 200. The direct-client review notes
replace the obsolete Observe/Act/Mac-helper draft. Review-contact fields are blank;
Apple cannot save their related review notes until a required phone number is
provided. The contact question is pending, with no invented phone number.

Automatic approval rejected broad personal-browser tab enumeration. Work continued
through a new tab opened directly to the authorized App Store Connect site.
Automatic approval separately rejected creating the external public group,
requiring confirmation at action time for the expanded access. The uploaded build,
review notes, and **Public Beta** group draft are prepared; the proposed initial
public-link limit is 100 testers. A fresh confirmation question is pending.
Screenshots remain outside Git. No public group or link has been created and no
Beta App Review submission is claimed at this point.

## Public-link scope still pending

Apple also asks whether the beta will be distributed in France. The earlier
outside-France answer is preserved for the current internal beta. Apple's
public-link guidance documents device/platform criteria; a worldwide public
link must not silently reuse that narrower declaration. Apple documents a
French encryption declaration for industry-standard encryption provided outside
the operating system. The shipped SSH/OpenSSL dependency graph is unchanged.
The user was asked whether to include France with the required documentation,
or retain outside-France controlled testing and leave the public link inactive.
No answer or encryption document is invented.

References:
- https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers
- https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption
