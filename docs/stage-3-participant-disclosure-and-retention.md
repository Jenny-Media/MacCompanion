# Stage 3 participant disclosure and retention schedule

Status: Draft for legal and privacy review. Dogfood may continue, but
calibration and confirmatory enrollment remain disabled until Jenny Media
approves a dated revision and the product presents that exact revision before
enrollment.

Last source review: 2026-08-23

## Purpose and boundary

Mac Companion is an unfinished beta that lets a person check, operate, and
control a Mac they own or are authorized to use. Jenny Media is evaluating
whether the separately useful Observe, Act, and Control paths solve repeated
real-world problems safely and clearly. This is product testing, not medical,
employment, education, or emergency-service research.

The iPhone/iPad app connects directly to the participant's Mac over a local or
explicitly configured private route. Jenny Media does not provide a relay or a
Mac Companion account. The product remains usable if a participant declines
the optional study, stops participating, deletes the local report, or never
exports it.

Only an adult who owns or is authorized to administer both devices should
participate. Do not test with an employer-, school-, client-, or other
third-party-managed Mac unless that organization has separately authorized
the test. Do not use sensitive production systems, enter passwords or recovery
codes through Control, or expose information belonging to another person.

## What the beta can do

The three paths have independent authorization:

- **Observe** returns fresh, content-free Mac status without starting screen
  capture.
- **Act** performs one named, separately approved desired-state action. The
  Stage 3 action is `setAudioMuted`; the participant should visibly verify the
  Mac's mute state after each attempt.
- **Control** can show live pixels and post mouse and keyboard input after
  separate local grants. A persistent visible Mac indicator and local Stop are
  safety controls, not a guarantee that unfinished software cannot fail.

The beta may disconnect, report an unknown outcome, show stale or incomplete
state, fail to stop promptly, or require a physical return to the Mac. A person
remains responsible for the Mac and should keep physical access available
during testing. Lock, local Stop, and device revocation must be tested only
with non-sensitive content and a recoverable local session.

Stage 3 does not authorize a shell, arbitrary SSH commands, general file
access, clipboard access, audio streaming, hidden automation, or silent
capability expansion. Route availability never grants product authority.

## Mac Companion study report

Study enrollment is optional and off by default. While an explicitly started
study session is active, the app can retain one bounded report locally on the
participant's iPhone or iPad. The report contains only:

- a random cohort-scoped study code and study phase;
- app/build, protocol, and OS major versions;
- closed result and category codes for install, permission, pairing, route,
  connection, Observe, Act, Control, Stop, revoke, recovery, workaround, and
  physical-return events;
- capped counts and elapsed durations needed for the published cohort rules;
- authenticated route class limited to LAN, private DNS, or private network;
- Control mode and manual/automatic transition facts;
- the closed `setAudioMuted` capability identifier and terminal result, never
  the requested or observed audio value; and
- participant-reviewed comprehension, safety, and recovery answers.

The generated report does not contain screen images, titles, typed text,
pointer coordinates, clipboard, audio, files, commands, app/process lists,
Accessibility content, network addresses, DNS or Bonjour names, device or host
identifiers, pairing material, credentials, Apple Account data, contact data,
precise location, raw logs, or crash dumps. Mac Companion has no study-report
uploader or analytics SDK.

Before sharing, the app shows the exact report. Export requires a separate
participant action through a user-selected destination. The participant may
delete the local report instead. Optional notes must be reviewed separately;
participants should not include names, secrets, screenshots, personal content,
or information about another person.

## TestFlight and support data are separate

Apple's TestFlight service separately processes tester/build information,
sessions, crashes, and optional feedback. Feedback can expose a tester's email,
device and OS details, carrier, time zone, connection type, screenshots, and
comments. Apple states that downloadable crash reports are available for 120
days. These facts are outside Mac Companion's content-free study report.

Jenny Media will disable TestFlight screenshot feedback for Stage 3 cohort
groups because a screenshot could contain mirrored Mac content. Participants
should use the monitored study contact for sanitized feedback. Jenny Media
will use TestFlight information only to improve Mac Companion and related
products, consistent with the Apple Developer Program terms, and will not
provide it to another party except a service provider bound to that limited
purpose.

The applicable Apple references are the
[TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/),
[beta tester feedback reference](https://developer.apple.com/help/app-store-connect/reference/testflight/beta-tester-feedback/),
[feedback management instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/view-tester-feedback),
and [Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/).

## Voluntary participation and withdrawal

Participation is voluntary. A participant may skip a task, deny a permission,
stop Control locally, revoke the paired device, delete the local report, stop
exporting reports, leave the TestFlight group, or ask Jenny Media to stop
contacting them. Declining or withdrawing does not remove ordinary use of an
otherwise available beta build.

On a verified withdrawal request, Jenny Media will stop study contact and
delete the contact mapping, participant-level exported report, and raw
feedback it controls within 30 days, except for a narrowly documented legal or
security hold. Facts already combined into a non-identifying aggregate may not
be separable after the contact-to-study-code mapping has been deleted.

## Jenny Media retention schedule

The FTC recommends collecting only what is needed, limiting access, setting a
written retention period, and disposing of information when the business need
ends. This schedule applies those principles to Stage 3; it does not replace
legal review. See the FTC's
[Protecting Personal Information: A Guide for Business](https://www.ftc.gov/business-guidance/resources/protecting-personal-information-guide-business).

| Record | Storage and access | Normal deletion deadline |
| --- | --- | --- |
| Local Mac Companion study report | Participant's iPhone/iPad; participant-controlled preview, export, and delete | Participant choice or app removal; Jenny Media has no copy until explicit export |
| Contact, eligibility, cohort, and study-code mapping | Separate encrypted access-controlled Jenny Media record; never merged into the exported report | 30 days after cohort close, and no later than 90 days after close |
| Exported content-free report | Encrypted access-controlled cohort folder; only people analyzing Stage 3 results | 90 days after the cohort decision, and no later than 180 days after receipt |
| Optional sanitized notes or support feedback | Stored separately from the generated report; minimum necessary access | 90 days after issue or cohort closure, whichever is later, unless converted to an anonymous product issue |
| Accidentally received screenshot, raw diagnostic, or personal content | Restricted quarantine for review and deletion; not added to study analysis | Seven days after discovery unless the participant explicitly asks for support retention or a documented security/legal hold applies |
| TestFlight tester and feedback records under Jenny Media control | App Store Connect; cohort operators only | Remove tester and deletable feedback within 30 days after cohort close; Apple-controlled residual retention follows Apple's terms |
| Consent/withdrawal audit | Study code, disclosure revision, timestamps, and outcome; no contact details after mapping deletion | 24 months after cohort close |
| Aggregate cohort decision | Counts, rates, candidate/build, dates, exclusions, and decision; no participant rows or quotations | Up to five years as product-decision evidence |

Deletion is recorded by category, cohort, date, operator, and result without
retaining deleted content. Backups must age out on the same schedule or the
schedule must state the shorter documented backup cycle before enrollment.
Access is reviewed at cohort start and close. Free-form quotations, recordings,
or public case studies require separate, specific permission and are never
authorized by accepting this disclosure.

## Incident and contact instructions

If remote input, capture, or authority appears wrong, stop using the iOS app,
choose local Stop on the Mac, lock the Mac if needed, and revoke the paired
device. Do not continue merely to complete a study task. Report the closed
safety category first; share screenshots or diagnostics only after Jenny Media
explains what they contain and obtains a separate confirmation.

The approved disclosure must replace these placeholders before external
enrollment:

- study contact name: `[REQUIRED]`
- monitored email: `[REQUIRED]`
- privacy/withdrawal email: `[REQUIRED]`
- company mailing address or other legally required contact: `[LEGAL REVIEW]`
- effective date and revision: `[REQUIRED]`
- countries/regions permitted for the first cohorts: `[LEGAL REVIEW]`

## Approval checklist

Calibration and confirmatory enrollment remain closed until all are true:

- Jenny Media legal/privacy review approves the audience, consent language,
  regional scope, withdrawal handling, and retention schedule;
- every placeholder above is replaced and the exact approved revision is
  archived;
- the product presents the exact revision before enrollment and records only
  the revision plus acceptance time in the local study boundary;
- TestFlight screenshot feedback is disabled for the cohort group and the
  monitored support/withdrawal channels are tested;
- the contact-to-study-code mapping store, access list, deletion procedure,
  backup cycle, and incident owner are exercised with synthetic data; and
- a dry run proves local preview, export, withdrawal, deletion, aggregate-only
  publication, and final cohort data disposal without using personal content.
