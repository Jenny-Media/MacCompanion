# Physical acceptance checklist

Status: execution-ready checklist; no physical result is claimed.

Use this checklist in two explicit phases. Candidate-stabilization runs may be
performed before the new source-bound seven-day soak so physical defects can be
found and fixed without wasting a campaign. Final acceptance and promotion may
be claimed only after the exact frozen candidate completes the soak and every
applicable item below passes. Every run binds the exact source revision,
clean/dirty state, candidate version and build, archive hashes, macOS/iOS
versions, hardware models, route, signing identities, and evidence-record
paths. A later source or build invalidates affected results; it never inherits
the prior campaign's elapsed time.

## Entry gate

- [ ] **Final-acceptance gate:** the current campaign in
  [`evidence/prephysical-soak-ledger.json`](evidence/prephysical-soak-ledger.json)
  has seven distinct UTC dates, at least 518,400 elapsed seconds, and
  `complete: true` for the exact candidate source fingerprint.
- [ ] The final repository validation, repeated signed Agent + Simulator
  journey, full Simulator suite, Release isolation, and disposable cleanup pass
  against that source.
- [ ] Stable Xcode 26.6 and the supported stable macOS/iOS SDKs are installed;
  beta-only evidence is labeled separately and cannot promote the candidate.
- [ ] Explicit production App IDs, profiles, distribution identities, release
  custody, privacy manifests, SBOM, notarization, stapling, update metadata and
  rollback artifacts validate for the exact archives.
- [ ] The Apple persistent-capture disposition is recorded. If unavailable,
  the candidate uses the ordinary-consent capture path and states its lifecycle
  limit; it does not claim unattended persistent capture.
- [ ] Legal/privacy approval covers the Stage 3 disclosure, retention schedule,
  Apache-2.0 license, trademark policy, security reporting, and tester region.
- [ ] Test devices contain no irreplaceable data; evidence capture excludes
  screen content, typed text, credentials, keys, passcodes and private logs.

Stop on a signature/profile mismatch, stronger-than-observed status, missing
local indicator, unexplained authority survival, stale frame/input admission,
content-bearing diagnostic, or cleanup uncertainty. Preserve evidence and do
not continue to a broader cohort.

## Candidate and clean installation

- [ ] Fill and validate the canonical Mac lifecycle record described in
  [`evidence/2026-08-23-mac-lifecycle-physical-evidence-matrix.md`](evidence/2026-08-23-mac-lifecycle-physical-evidence-matrix.md).
- [ ] On a clean standard user, download the notarized distribution artifact,
  retain quarantine, launch without Gatekeeper bypass, and verify app, Agent,
  team, identifiers, hardened runtime and privacy resources.
- [ ] Before enabling, prove there is no listener, advertised route, pairing,
  grant, session, login item, remote mutation or restored prior authority.
- [ ] Enable Mac Companion through explicit local consent. Verify Agent
  registration, reciprocal signed XPC identity, dashboard readiness, listener
  truth, visible menu ownership and restart/login behavior.
- [ ] Exercise denial, partial permission, later grant, revocation and refresh
  for Local Network, Camera, Screen Recording and Accessibility. Permission UI
  must identify the correct process and request capture/input permission before
  the first Control attempt where macOS permits.

## Physical iPhone pairing, Observe and Act

- [ ] Fill and validate the canonical record described in
  [`evidence/2026-08-23-ios-physical-evidence-record.md`](evidence/2026-08-23-ios-physical-evidence-record.md)
  on a fresh passcode-protected device after first unlock.
- [ ] Pair by QR and two-device SAS. Confirm expiry, host pin, local device
  names, fingerprint presentation, Face ID/user-presence behavior and durable
  key custody. Retry/cancel/reopen/reinstall cases must never create divergent
  one-sided pairing.
- [ ] Retain at least two paired iPhone/iPad clients at once, reconnect each
  independently, administer each by its exact displayed identity, and verify a
  second concurrent remote session is denied without disturbing the active one.
- [ ] Obtain a current Observe snapshot without starting Control. Verify stale,
  unavailable, locked, logout and reconnect labels, plus host-derived active
  data-access indication and immediate device revocation.
- [ ] Explicitly grant Act independently of Observe and Control. Run one
  consented `setAudioMuted`, verify the actual system result, exact replay,
  cancellation, outcome-unknown recovery and audit entry; restore the original
  mute state before leaving the case.
- [ ] Deny Local Network, verify no route or broader authority is inferred, then
  restore it in Settings and recover under the same authenticated pin.

## Interactive Control and adaptive UX

- [ ] Grant Control independently and verify the Mac review shows exact device,
  requested interactions and current grant. Decline and stale-review replay
  must add nothing.
- [ ] Verify first current Desktop frame, visible local indicator, pointer move,
  primary/secondary click, drag, scroll, pinch/zoom, direct keyboard, ordinary
  iOS keyboard, modifiers and shortcuts in at least two ordinary apps.
- [ ] Verify Stop immediately removes capture/input authority while Observe and
  separately granted Act remain usable. Remote revoke, local revoke and menu or
  Agent loss must also terminate Control and release held input.
- [ ] Verify Desktop, App Focus, Window Focus and Smart Zoom, including automatic
  focus-to-zoom, manual zoom interaction, app/window switch, disappearance,
  secure-field refusal, fallback, rotation/scale change and fresh keyframe.
- [ ] With two online Mac displays, switch the Shared Display inside an active
  Control session in both directions. Verify the old surface stops, the new
  surface requires a fresh configuration and clean keyframe, input pauses until
  acknowledgement, and display attach/detach never admits stale coordinates.
- [ ] Verify the native composer and local iOS input surface only when focus is
  verified editable and non-secure. Ordinary keyboard and shortcuts remain
  usable without an editable field. No typed text enters audit or diagnostics.
- [ ] Verify background/foreground, another foreground app, route loss/recovery,
  Wi-Fi change, screen lock/unlock, sleep/wake, menu restart, Agent restart and
  iOS process restart. Control requires fresh presence where specified; no old
  frame, surface token, input transition or operation may resume.
- [ ] Record genuine lock-surface support as `supported` or
  `lockedInteractionUnavailable`. Status may remain available while the user is
  logged in and locked; logout must be explicitly unreachable.

## Routes and performance

- [ ] Bind every measurement and decision to the closed
  [`performance-acceptance` profile](../spec/performance-acceptance/v0/profile.json)
  and follow its [methodology](../spec/performance-acceptance/v0/README.md).
  A changed threshold requires a reviewed profile revision or ADR.
- [ ] Repeat the essential Observe/Act/Control journey over same-subnet IPv4,
  supported IPv6, private DNS and one documented no-relay private-network route
  such as Tailscale. Record discovery and connection truth; never fall back to a
  Jenny Media relay.
- [ ] On a healthy LAN, measure at least enough samples for p50/p95: session
  request to first current frame (p95 <= 2.5 s), glass latency (p50 <= 150 ms,
  p95 <= 300 ms), pointer-to-visible response (p50 <= 180 ms, p95 <= 350 ms),
  app/window selection to keyframe (p95 <= 1.0 s), focus-to-stable Smart Zoom
  (p95 <= 300 ms), fallback (p95 <= 500 ms), and Observe reconnect (p95 <= 3 s).
- [ ] Run a continuous 60-minute Control session and the seven-day installed
  Observe soak. Record idle/active CPU, resident memory, energy, battery,
  thermal state, network bytes, dropped frames, reconnects, log/audit/database
  growth and disk use. Demonstrate no unbounded growth.
- [ ] Resolve all eight `requiresPhysicalMeasurementAndApproval` entries in the
  performance profile before promotion: Mac CPU/RSS, iOS CPU/RSS, energy and
  battery, idle/Observe network bytes, installed disk growth, pairing time and
  text-session termination. The pre-physical Simulator baseline is diagnostic
  only and cannot supply those physical release thresholds.
- [ ] Verify the 1920x1200/2,304,000-pixel, 30-fps and 8-Mbit/s caps plus
  adaptation and clean-keyframe behavior under congestion and thermal pressure.

## Update, removal, safety and usability

- [ ] Execute all twelve signed old-to-new, failure and rollback cases in
  [`evidence/2026-08-23-mac-update-physical-evidence-matrix.md`](evidence/2026-08-23-mac-update-physical-evidence-matrix.md),
  including active/uncertain Control denial and no background update traffic.
- [ ] Revoke permissions during a session, suspend and permanently revoke a
  device, fill audit/store to bounded limits, simulate disk full, and verify the
  product fails closed with understandable recovery and no silent authority.
- [ ] Uninstall completely: stop remote work, unregister the Agent/login role,
  remove listener, revoke pairings and product data, leave no helper, then prove
  reinstall restores no authority. Record what is user-recoverable.
- [ ] Run VoiceOver, Dynamic Type, Reduce Motion, orientation and supported
  hardware-keyboard checks. All consent, unavailable, reconnect, Stop and
  revocation controls must be reachable and correctly named.
- [ ] Five target testers complete clean Mac+iPhone onboarding to a current
  Observe snapshot without assistance. Retain time-to-value, abandonment and
  help-required evidence; then run the separate Stage 3 calibration and
  confirmatory cohorts defined by ADR-0002.
- [ ] Independent security/privacy review has no unresolved critical finding.
  Human promotion review confirms every record is truthful, candidate-bound
  and complete before external beta distribution.

## Exit record

Record each item as `passed`, `failed`, or `not-run`; `not applicable` requires
an approved ADR. Link content-free evidence and list every deviation. A passed
checklist establishes physical acceptance for only the exact candidate. It does
not by itself prove market-MVP repeat use, approve publication, or authorize a
later release.
