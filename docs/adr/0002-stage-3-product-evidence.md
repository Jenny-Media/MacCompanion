# ADR-0002: Stage 3 audience, product slice, and evidence gate

- Status: Accepted for Stage 3 calibration and confirmatory testing
- Date: 2026-08-23
- Owners: Mac Companion product, privacy, and security
- Supersedes: provisional percentages in the product proposal where this ADR
  is more specific

## Context

Mac Companion has a technically ambitious three-path design, but construction
and feature breadth do not prove that people repeatedly need the product. The
Stage 3 market-MVP gate requires a calibration cohort followed by a separate
confirmatory cohort. Thresholds, denominators, representative jobs, privacy
rules, and failure handling must be fixed before cohort results are inspected;
otherwise ordinary attrition or post-hoc metric selection could be presented
as product evidence.

The [competitive task matrix](../research/2026-08-23-competitive-task-matrix.md)
also shows that QR pairing, direct LAN/private routes, app/window focus,
hardware video, and touch control are category expectations. The hypothesis to
test is the combination of independently useful Observe, Act, and Control,
revision-safe adaptive interaction, and truthful authorization and recovery.

This ADR defines product-study evidence. It does not replace the protocol,
security, physical-device, App Review, notarization, legal, or release gates.

## Decision

### Initial audience

The beachhead is an adult owner of one supported, logged-in personal Mac and
one supported iPhone or iPad who:

- wants direct private operation over a LAN or a private route they manage;
- has a real reason to check or operate the Mac while away from its keyboard;
- accepts installing the visible Mac menu app and per-user Agent; and
- can keep the Mac logged in and awake for the job being tested.

The calibration cohort should intentionally include always-on Mac mini/home-Mac
owners and developers or technical creators who leave long-running builds,
Simulator sessions, terminals, or applications on a Mac. Technical fluency is
recorded as a cohort attribute, not used to exclude a failed onboarding attempt.
MacTools users are welcome but MacTools is not required and cannot define the
Stage 3 result.

This is a hypothesis, not a claim that these users constitute a large market.
Teams, managed enterprise Macs, pre-login administration, shared family Macs,
cloud Macs, and people seeking general shell/file access are outside the
confirmatory population.

### Current workarounds to compare

The study asks which workaround the tester would otherwise have used:

- return physically to the Mac or defer the job;
- Apple Screen Sharing or a conventional remote-desktop product;
- SSH, a script, Shortcut, or a narrow remote-control utility;
- keep the primary laptop nearby; or
- no current workable alternative.

This answer is a fixed category plus optional tester-written context. It is not
inferred from installed applications or network inspection.

### Representative real jobs

A **real job** has a tester-owned outcome beyond setup, demonstration, or
following the study script. The tester records the intended outcome and a
closed result (`completed`, `notCompleted`, or `outcomeUnknown`) without
submitting screen contents or typed text.

Representative jobs are:

| Path | Qualifying jobs | Does not qualify |
| --- | --- | --- |
| Observe | Check whether a build or long-running task is still active; inspect fresh Mac health, power, thermal, storage, or current availability; distinguish stale/unreachable from live state before deciding what to do. | Merely opening the app, viewing onboarding, or reading cached state as though it were current. |
| Act | Set the Mac's audio mute state through the separately granted `setAudioMuted` action and verify the reported result/current state without opening Control. | A UI-only dry run, an unverified toggle, or an action attempted from inside a screen-control session. |
| Control | Recover from an unexpected dialog; inspect or operate Xcode, Simulator, Terminal, or another tester-owned app; complete a visual mouse/keyboard task through Desktop, App Focus, Window Focus, or Smart Zoom. | Moving the pointer only, viewing a frame only, or executing credentials, purchases, messages, destructive work, or private production data for the study. |

A user need not use all three paths. The study retains the chosen path and
whether opening Control was actually necessary.

### Smallest three-path product slice

The Stage 3 candidate includes only what is required to test the hypothesis:

1. one Mac and one phone/tablet in the supported UX;
2. visible per-user Mac Agent administration, QR/SAS pairing, named-device
   revocation, and content-free local activity history;
3. direct same-LAN operation plus explicitly configured user-managed private
   endpoints, with no Mac Companion account or relay;
4. fresh/last-known Observe state with honest unreachable, stale, locked,
   sleeping, and unavailable presentation;
5. the desired-state `setAudioMuted(Boolean)` Act capability with its own
   grant, durable operation identity, cancellation/outcome semantics, and
   verified result;
6. separately granted live Desktop pixels, mouse, and keyboard plus App Focus,
   Window Focus, manual/automatic Smart Zoom, explicit current mode, and safe
   visual fallback; and
7. an opt-in, previewable, user-exported study report.

Shell, arbitrary files, clipboard, audio streaming, virtual displays, headless
or pre-login operation, multiple Macs/phones in the UX, general workflows,
MacTools/providers, semantic Window Text, AI, and a vendor relay remain outside
this slice. Competitor breadth does not reopen them.

### Cohort sequence

1. **Internal dogfood:** exercise the same jobs and report schema until the
   study procedure itself is usable. Dogfood is not market evidence.
2. **Calibration:** 10–20 eligible testers use an external TestFlight candidate
   for 14 complete days. They attempt self-initiated real jobs; prompted setup
   tasks are recorded separately. Calibration can find defects, revise the
   product, and estimate variance, but cannot pass the market-MVP gate.
3. **Confirmatory:** a separate group that did not participate in dogfood or
   calibration uses the subsequently frozen candidate and protocol for 14
   complete days. Evaluation requires at least 15 eligible testers and targets
   20. Fewer than 15 is **inconclusive**, never a pass or a denominator change.

The confirmatory build, supported OS range, enrollment cutoff, study start and
end, report schema version, and this ADR revision are recorded before the first
confirmatory participant begins. Results from replaced builds remain defect
evidence but are not pooled into a new build's confirmatory result.

### Denominators

- An **enrolled tester** accepted the study disclosure and received access.
- An **eligible tester** met the predeclared device/OS/ownership requirements,
  installed both candidate apps, and attempted first-run setup during the
  window. Pairing, permission, route, crash, or usability failures do not make
  that tester ineligible.
- An **activated tester** completed pairing and received one fresh authenticated
  Observe result. A tester who needed developer intervention can activate but
  is still a pairing-with-intervention failure.
- A **developer intervention** is any private command, database edit, manual
  identity repair, special build, remote debugging session, or step not
  available in the candidate's normal UI and public beta instructions. Normal
  answers to documented questions are support, not intervention.
- A **distinct use day** is a local calendar date on which at least one real job
  completes. Repeated attempts at the same failed setup do not create use days.
- A **repeated path job** means qualifying real jobs in that path on at least
  two distinct use days.

Exclusions are limited to facts established before the first setup attempt:
unsupported hardware/OS, no personally controlled Mac, or inability to install
the candidate under the published requirements. Voluntary withdrawal remains
in the eligibility denominator through the last observable step and is also
reported separately. No participant is removed for failure, low use, technical
fluency, or an unfavorable answer.

### Preregistered confirmatory thresholds

All of the following must pass on the same confirmatory cohort:

| Gate | Threshold |
| --- | --- |
| Clean-install pairing | At least **80% of eligible testers** complete pairing without developer intervention. |
| Repeated real value | At least **60% of activated testers** complete a real job on **three distinct days** within the 14-day window. |
| Repeated Control | At least **five testers** complete qualifying Control jobs on at least two distinct days. |
| Repeated nonvisual value | At least **three testers** complete qualifying Observe or Act jobs on at least two distinct days without starting or maintaining Control for those jobs. |
| State/grant comprehension | At least **80% of eligible testers** correctly distinguish paired, connected, viewing, controlling, and approval-required, and correctly state that pairing, Act, and Control do not authorize one another. Missing or incomplete final checks are not successes. |
| Adaptive differentiation | At least **three testers** complete applicable real jobs with App Focus, Window Focus, or Smart Zoom on two distinct days, and fewer than **80% of aggregate valid Control-active duration** is Desktop-only. A cohort with no applicable adaptive job is inconclusive, not a pass. |
| Safety | **Zero confirmed stale-authority input incidents**, unintended-surface/field input incidents, behind-lock content disclosures, unauthorized capability elevations, or failures of the local Stop/revocation control. Any such incident blocks the market-MVP result regardless of percentages. |
| Truthful recovery | No recurring confusion pattern causes testers to treat unreachable, stale, locked, sleeping, or `outcomeUnknown` as a stronger state. Two or more independently confirmed occurrences of the same misleading product presentation fail this gate until fixed and re-tested. |

Percentages use integer counts and are rounded only for display. Passing uses
the exact fraction (`successes * 100 >= threshold * denominator`), not a rounded
percentage. Missing or corrupt reports do not count as success. Product-side
evidence may establish a safety failure, but absence of a diagnostic event
cannot establish that a user-facing task succeeded.

### Product decisions after the cohort

- **Pass:** every security/release gate and every table threshold passes. Stage
  3 may be called the market-facing MVP.
- **Inconclusive:** enrollment is below 15, study evidence is materially
  incomplete, the build changes mid-window, or applicable adaptive jobs are
  absent. Fix the study/product and run a new confirmatory cohort; do not lower
  a threshold.
- **Simplify:** technical/repeat-use gates pass but Observe/Act or adaptive
  modes are rarely chosen. Preserve safety boundaries, narrow the product
  claim, and remove ceremony rather than forcing path usage.
- **No-go for a capability:** a path repeatedly creates unacceptable safety,
  privacy, platform, support, or review cost and cannot pass after a bounded
  remediation cycle. Record the evidence and remove or defer that capability;
  do not hide the result in an aggregate score.

Calibration can change the candidate, copy, onboarding, or study mechanics.
Changing a confirmatory threshold, denominator, eligibility rule, job
definition, or safety rule requires a new dated ADR before a new confirmatory
cohort begins. Results are never retrospectively re-scored under the new rule.

## Privacy-preserving study evidence

There is no centralized telemetry in Stage 3. Evidence is retained locally and
shared only through an explicit tester export with preview and consent. The
product remains fully usable if the tester never exports.

### Permitted report facts

- report schema, app/build, protocol, OS-family/major-version, cohort phase,
  and an opaque study code assigned outside product identity;
- content-free phase/result codes for install, permission, pairing, route,
  connection, Observe, Act, Control, surface change, fallback, Stop, revoke,
  and recovery;
- monotonic elapsed durations and capped counts needed for the thresholds;
- coarse route provenance (`lan`, `privateDNS`, or `privateNetwork`) only after
  authenticated use;
- Control mode (`desktop`, `application`, `window`, or `focusedRegion`) and
  whether a transition/fallback was automatic or manual;
- closed operation capability identifier for the built-in
  `setAudioMuted(Boolean)` and closed terminal outcome, without parameter or
  prior/current audio value; and
- tester-entered closed job category, path, outcome, workaround category,
  physical-return reason, comprehension answers, and optional free-form notes
  reviewed by the tester before sharing.

Durations are sufficient to derive time to pair, first fresh Observe, first
controllable frame, route recovery, surface transition, and active-mode share.
The report distinguishes `notAttempted`, `unsupported`, `denied`, `failed`,
`notCompleted`, `outcomeUnknown`, and `completed`; missing evidence is never
converted into success.

### Prohibited report facts

The generated report never contains or derives:

- screen frames, screenshots, thumbnails, OCR, app/window/document titles,
  bundle identifiers, process lists, Accessibility values or element labels;
- typed text, key codes, pointer coordinates, clipboard, audio, file paths,
  shell commands, operation parameter values, or provider-private data;
- device/host IDs, pairing fingerprints, public keys, certificates, tokens,
  signatures, credentials, Keychain references, IP addresses, DNS names,
  Bonjour names, Wi-Fi identifiers, route endpoints, or Tailscale identity;
- Apple Account, email, phone, person name, precise location, contacts,
  advertising identifiers, or a stable cross-study product identifier; or
- raw platform errors, crash dumps, unified logs, or private release/account
  metadata.

Optional tester notes are outside the generated safe schema. The preview warns
the tester not to include secrets or personal content, and the recipient treats
notes as potentially sensitive. Generated facts and notes remain visibly
separate.

### Retention and sharing

- Study evidence is local, bounded, and deletable before export.
- Export is off by default, requires an explicit action, shows the exact report,
  and uses an ordinary user-selected share destination.
- The app does not silently retry, upload in the background, or infer consent
  from TestFlight participation.
- The study code is random and unique to one cohort. The mapping to contact
  details, if needed for scheduling, is stored outside Mac Companion evidence
  and deleted under the study's written retention schedule.
- Published results use aggregate counts and label sample size, candidate
  build, dates, and exclusions. Free-form quotes require separate permission.

The existing sanitized Agent diagnostic export and scoped self-audit are
operational troubleshooting sources, not automatically a valid study report.
The bundle-independent [study-evidence kernel](../evidence/2026-08-23-stage-3-study-evidence-kernel.md)
implements a separate versioned schema and deterministic evaluator that admit
only the facts above and pass a prohibited-field corpus. The
[local report owner](../evidence/2026-08-23-stage-3-local-report-owner.md) adds
bounded atomic persistence plus exact preview, explicit export, and destructive
delete in the permanent iOS product. The later
[local enrollment and initial capture](../evidence/2026-08-23-stage-3-local-enrollment-capture.md)
adds optional dogfood-only enrollment, explicit day sessions, and initial
pairing/connection/first-live-Observe bindings. The
[explicit Act and Control capture](../evidence/2026-08-23-stage-3-act-control-capture.md)
then adds tester-confirmed mute outcomes and content-free active-mode Control
duration without inferring real-job intent. The
[authenticated route and final-review checkpoint](../evidence/2026-08-23-stage-3-route-and-final-review.md)
completes the local capture loop with exact winning-route provenance, explicit
Observe jobs, physical returns, comprehension, safety, recovery review, and an
immutable final lock. Disclosure, physical verification, and actual cohorts
stay open.

## Consequences

- The product thesis and thresholds can fail; the project cannot call a green
  technical alpha a market-facing MVP.
- Observe or Act adoption is not inflated by forcing a screen session, and
  Control adoption is not inflated by making it the only route to status.
- Adaptive modes must demonstrate repeated applicable value rather than exist
  as screenshots or feature-list differentiation.
- A user-risk incident overrides aggregate engagement.
- Product comparison remains honest because Mac Companion uses the same
  stopwatch and recovery taxonomy defined in the competitive matrix.
- The versioned report is now locally persistent, previewable, explicitly
  exportable, and deletable without repurposing diagnostic logs or adding
  telemetry; truthful product capture and physical cohort evidence remain.

## Rejected alternatives

- **Calibration alone proves MVP:** rejected because the same observations
  would tune and judge the product.
- **One blended cohort:** rejected because repeat testers and repaired installs
  would bias onboarding and comprehension evidence.
- **Post-hoc thresholds:** rejected because they reward whichever metric looks
  favorable.
- **Screen-control minutes as the primary metric:** rejected because it would
  penalize fast Act/Observe outcomes and reward inefficient remote desktop use.
- **Mandatory use of all three paths:** rejected because the product promises
  independently useful paths, not ceremony.
- **Centralized analytics:** rejected for Stage 3 because it is unnecessary for
  the no-account/no-relay hypothesis and would create a new data path.
- **Raw diagnostic export as study evidence:** rejected because operational
  diagnostics do not encode job intent, completion, comprehension, or cohort
  denominators and may invite overcollection.

## Required evidence before the calibration cohort

- A strict versioned study-report schema and prohibited-field corpus. **Built
  and bundle-independently verified.**
- Local bounded storage, preview, delete, and explicit export UI. **Built and
  Simulator-compile verified; signed physical behavior remains.**
- Optional explicit local dogfood enrollment and session-gated content-free
  capture. **Pairing, authenticated connection, and first-live-Observe
  bindings are built and compile/fault tested; remaining product facts and
  signed physical truth comparison remain.**
- Deterministic aggregation that reproduces every denominator and threshold in
  this ADR from fixtures without network access. **Built and
  bundle-independently verified.**
- A written participant disclosure and retention schedule reviewed for the
  target jurisdictions.
- Internal dogfood proving the report matches visible product truth across
  denial, failure, `outcomeUnknown`, fallback, Stop, and revocation.
- A signed candidate that independently passes the physical, security,
  entitlement, distribution, and App Review preparation gates.
