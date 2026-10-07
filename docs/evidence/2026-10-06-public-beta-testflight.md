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
replace the obsolete Observe/Act/Mac-helper draft. The user supplied the required
review contact phone directly; contact information and review notes were completed
in App Store Connect. Personal contact details are not recorded in Git.

Automatic approval rejected broad personal-browser tab enumeration. Work continued
through a new tab opened directly to the authorized App Store Connect site.
Automatic approval separately rejected creating the external public group,
requiring confirmation at action time for the expanded access. The user then
explicitly confirmed **Public Beta, 100 testers**. The external group was created
as `a6ee74fa-d78d-45a4-a6f2-aa14659d4c73`; build **1.0 (5)** was submitted through
its review wizard. App Store Connect independently confirms **Waiting for Review**,
zero external testers and one assigned build. No vendor sign-in is required;
the review notes explain reviewer-owned Mac authentication. A misleading automatic
approval rejection of the checkbox action was resolved by inspecting its checked
state and explicitly setting it to unchecked, consistent with that review flow.

The public-link setup is prepared with **Set Limit = 100**, but has not been
confirmed or activated. Its UI offers open access or device/platform criteria,
without a country selector. Screenshots remain outside Git, including
`maccompanion-public-beta-waiting-for-review-20261006.jpg` and
`maccompanion-public-beta-100-tester-draft-20261006.jpg` in this task's visualization
folder. Submission is not approval or external testing availability.

## Public-link scope still pending

The earlier outside-France compliance answer is preserved. After the discussion,
the user explicitly requested **dropping France support**. The existing store
availability had included all 175 countries or regions. Only France was deselected;
the confirmation dialog specifically named France. The saved availability summary
now reports **174 countries or regions** and its Europe table confirms
**France: Not Available**. Screenshot evidence remains outside Git as
`maccompanion-france-not-available-20261006.jpg` in this task's visualization folder.
The app has not yet been released on the App Store. No French declaration has been
filed, and no application encryption or source-bound archive input was changed.

Lifetime Pro (`6819497277`) and 14-day Trial (`6819497930`) availability was also
saved without France. After reloading each product, its form reports **174 of 175
countries or regions selected**, Save is disabled, and the reopened country
selector confirms France is unchecked. The product prices, base country,
future-region setting and trial terms were preserved. Required stable-Xcode
`bash scripts/validate.sh` passes; the log is outside Git at
`/private/tmp/maccompanion-france-exclusion-validation-20261006.log`.

The public link remains inactive because its UI has no country filter, and
excluding France from the store does not prove that the beta link is regionally
enforced. The owner was asked to choose controlled invitations for outside-France
testers or a public link with an unenforced outside-France notice. The latter has
not been assumed from the country exclusion request. The 100-tester draft and
submitted build remain prepared.

Current Apple guidance specifies a French encryption declaration for standard
encryption outside the operating system **when distributing on the App Store in
France**. The earlier blanket statement about every public beta was too broad.
Apple separately says required encryption documents must precede App Review or
TestFlight App Review. ANSSI distinguishes unrestricted use from supplying or
importing encryption products, with exceptions depending on classification.
Its current process is an online declaration, requesting company information,
registration evidence (or a foreign equivalent) and product/technical documents.
The shipped SSH/OpenSSL dependency graph is unchanged. The earlier recommendation
to retain France as a planned market is superseded by the subsequent explicit
product-owner decision above.

References:
- https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers
- https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption
- https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation
- https://cyber.gouv.fr/reglementation/reglementation-identite-confiance-numerique/controles-reglementaires-cryptographie/controle-moyen-de-cryptologie/
- https://demarche.numerique.gouv.fr/commencer/declaration-relative-a-un-moyen-de-cryptologie
