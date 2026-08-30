# Pre-physical MVP execution goal (historical)

Activated: 2026-08-28, explicitly authorized by the user.

Superseded: 2026-08-29 by the Stage 2 physical-alpha candidate goal. This
document remains the authoritative record of the completed disposable and
Simulator-first preparation boundary; it is not the current execution goal.
Its retained one-day soak campaign is source-bound historical evidence and
cannot be resumed or credited to the newer candidate source.

## Finish line and authority

Bring the project to **readiness for physical acceptance testing**, not a
certified external beta or market-MVP result. Complete every safely automatable
required path, retain exact evidence, and deliver one consolidated physical
acceptance checklist. Preserve the normative staged plan, protocol fixtures,
independent Observe/Act/Control grants, and Simulator-first policy.

Use the current repository without discarding its existing changes. Do not
touch the physical iPhone, installed production apps/Agent, production Keychain
or privacy settings, or publish/upload/change external accounts without fresh
authorization. Tests may use disposable signed processes, UUID-named services,
temporary stores, Simulator, and the test host's own window/PID. Do not silently
grant permissions or introduce Release authentication bypasses. No per-change
review skill or subagent delegation is implicitly enabled by this goal.

A blocked dependency blocks only its dependent work. Continue other safe
items; document the exact boundary and evidence needed. Do not call a required
automatable failure deferred or complete. Only hardware, external decisions,
or genuinely missing authority may remain at handoff. A multi-day soak must
record real elapsed time; use the product scheduling mechanism for ongoing
monitoring rather than claiming a short test is equivalent.

## Starting evidence (not proof of remaining work)

- [Authenticated Simulator journey](evidence/2026-08-28-authenticated-simulator-journey.md).
- [Production renewal scheduler and 16-test UI suite](evidence/2026-08-28-agent-renewal-simulator.md).
- [24-case isolated startup/bootstrap/status XPC matrix](evidence/2026-08-28-isolated-agent-xpc.md):
  three passing runs, 1,742 repository tests, Release seam exclusion, cleanup.

Older execution-ledger paragraphs are historical. Do not re-open completed work
solely because an old row calls it a gap; verify the latest source/evidence.

## Dependency-aware worklist

| ID | Work | Depends on | State / required proof |
| --- | --- | --- | --- |
| P1 | Full enabled-Agent preparation/composition in isolation | Existing startup harness | **Complete for the disposable pre-physical boundary.** The signed 55-case matrix covers production enabled/menu/listener/primary owners, real pairing and Observe, graceful/crash Agent restart, replacement-menu recovery, and cleanup. Installed login-item/Keychain custody remains physical acceptance evidence. |
| P2 | Signed administration and menu presentation XPC | P1, or independent transport fixtures | **Complete for signed transport; physical UI remains.** Signed pairing, Act/Control review and decisions, reviewed revocation/replay/restart, menu loss and presentation recovery pass. The actual installed Mac consent/history/diagnostics UI remains on the physical checklist rather than being replaced by a test bridge. |
| P3 | Signed Interactive XPC and final Agent authority | P1–P2 | **Complete for the disposable pre-physical boundary.** Signed lease issuance/final admission/renewal/Stop, both role proofs, revocation during preparation, final-admission race, menu loss, and active runtime cleanup pass. Test-owned capture/input/indicator effects remain explicitly substituted. |
| P4 | Combined authenticated Simulator journey | P1–P3 | **Complete.** The signed Agent + Simulator journey covers pair/reconnect/Observe/Act/Control, verified focus, automatic zoom, pointer, both keyboards, Stop-to-Observe, client restart, background/foreground and route-loss recovery. Agent process restart remains separately covered by the signed 55-case matrix. |
| P5 | End-to-end bounded Act | P1; can proceed beside P2–P3 | **Complete for automated evidence.** Signed review/decline/approval, remote ungranted denial, `setAudioMuted` through the native provider with test-only audio, read-back failure, cancellation, exact replay and outcome-unknown recovery pass through the combined UI and signed matrix. Actual system mute mutation remains an explicit physical/manual authorization gate. |
| P6 | Fault, persistence and recovery closure | Incrementally with P1–P5 | **Complete for required automated paths.** Pairing, Observe, grants and revocation survive process restarts; final-admission, late-renewal, replacement-menu, retained-callback, background, route-loss and renewal-fault regressions pass. The [current-source startup/handshake stress gate](evidence/2026-08-29-agent-startup-handshake-stress.md) completes 200 consecutive signed launches, including 50 complete menu handshakes, under the unchanged deadline and retires the older timeouts as historical rather than current failures. Repository storage/migration/full/corruption fixtures remain part of the final validation gate; installed identity recovery remains physical acceptance evidence. |
| P7 | UX and compatibility acceptance | P4; static/UI checks independent | **Automated slice complete; physical UX pending.** Accessible Stop, Desktop/focused surfaces, automatic zoom, pointer, native composer, ordinary iOS keyboard, direct keyboard, secure-focus refusal, background and reconnect behavior pass. Cross-app ergonomics, real secure fields, orientation/hardware keyboard and permission UI require physical acceptance. Smart Input stays optional. |
| P8 | Performance and soak evidence | Stable P4–P7 | **Active only for elapsed soak time.** Three generated live runs, three real-window runs and the full 16-scenario suite pass. The [startup/handshake stress gate](evidence/2026-08-29-agent-startup-handshake-stress.md) passes two independent 100-cycle runs with sub-0.4-second maxima and exact cleanup. A source-bound 199.018-second resource baseline is retained with honest Simulator limits. The closed performance profile machine-checks 10 latency gates, 7 media caps, bounded growth/soak, durable caps and eight explicitly physical-only decisions. Day 1 of seven is retained; six later UTC dates and 518,400 actual elapsed seconds remain. |
| P9 | Safe local release preparation | Independent; final run after P1–P8 | **Complete for the authorized local construction boundary.** Production compilation, Release isolation, SBOM/update/rollback validators and an explicitly unsigned, artifact-free release-evidence manifest pass. Stable Xcode 26.6, distribution custody, signed/notarized artifacts and publication remain external gates. |
| P10 | Consolidated security/privacy checkpoint | P1–P7 | **Complete for automated checks.** Malformed identity/frame, authorization, replay, revocation, race, cleanup, privacy-manifest and material-boundary checks pass. A separate independent reviewer/subagent pass remains intentionally unperformed because this goal did not authorize it and is a pre-public-beta gate. |
| P11 | Final regression and evidence reconciliation | P1–P10 | **Complete except the time-dependent P8 gate.** Current-source signed repetitions, full repository validation, unsigned evidence, performance baseline, consolidated checkpoint and physical acceptance checklist are retained. Final completion waits for the source-bound seven-date soak and one last exact-current reconciliation. |

The [machine-checked completion audit](evidence/2026-08-29-prephysical-completion-audit.md)
maps every remaining requirement to actual elapsed time, physical hardware,
fresh authorization, or an external resource/decision. Its validator rejects
any unresolved automatable required-path failure or source/soak mismatch.

Update a row only with a linked checkpoint and explicit remaining substitutes.
Passing unit tests do not prove full runtime composition or hardware custody.

## Expected later gates (prepare; do not claim passed)

- Physical iPhone/iPad UI, Face ID/Secure Enclave, final signed identity custody.
- Clean-user installed lifecycle, login/logout/user switching/lock/sleep,
  permission denial/revocation/refresh, update and uninstall, TCC attribution.
- Real LAN/Bonjour/Local Network permission and private IPv4/IPv6/DNS/Tailscale routes.
- Apple managed-capture disposition, explicit distribution App IDs/profiles,
  stable release toolchain/custody, notarization/stapling/TestFlight/App Review.
- Legal/privacy/policy approval, actual repository protections and private
  reporting, explicitly authorized publication and release promotion.
- Unassisted tester checks, calibration and separate confirmatory cohorts per
  ADR-0002. Later provider/semantic/admin/AI breadth is outside this goal.

These are anticipated boundaries, not blanket exemptions: automate all safe
preparation, simulation, and validation before placing an item in the handoff.

## Checkpoint log

### 2026-08-28 — goal activated

- Created the explicit durable goal and this worklist.
- Re-read repository authority and current Simulator/XPC evidence.
- Next: inspect production preparation, enabled root, and existing injection
  seams; implement the smallest verifiable P1 checkpoint without production
  Keychain, network advertisement, installed Agent, or physical-device effects.

### 2026-08-28 — real primary/local composition checkpoint

- Extended the signed startup matrix from 24 to 32 cases. The new cases prepare
  the real required-audit primary product, lifecycle observation/event pump and
  local status reader; they no longer inject those owners or status snapshots.
- [Checkpoint evidence](evidence/2026-08-28-pre-physical-primary-xpc.md): three
  consecutive final 32/32 runs, 1,742 repository tests, and zero matching Release
  test symbols. Graceful/abrupt restart, unchanged persisted identity, and
  missing-key rejection pass. Two earlier pre-output launch timeouts remain an
  open reliability finding; the runner now captures exact-job state and stacks.
- Platform substitutes: disposable software identity custody, empty providers,
  unavailable Interactive, inert process starter, and UUID-only local service.
- P1 remains active: full menu/presentation binding and loopback-only enabled
  network composition are next. This is not yet the combined Simulator journey
  or durable remote Observe status-sequence proof.

### 2026-08-28 — enabled runtime and menu/presentation integration

- The 35-case signed matrix now invokes the production enabled-runtime
  coordinator, full menu/presentation composition, primary/lifecycle owners and
  shared listener service. The Debug adapter substitutes only its loopback
  binding/port, private-endpoint readiness for Bonjour, and generated review
  stimulus. Actual listener readiness is required; no LAN advertisement occurs.
- Generated review delivery, duplicate suppression and exact withdrawal pass.
  Real QR create/dismiss retries, fresh QR, no-device Control-grant rejection,
  loopback binding inspection and concurrent shutdown pass.
- [Checkpoint evidence](evidence/2026-08-28-enabled-presentation-xpc.md): three
  consecutive final 35/35 runs with cleanup, 1,744 repository tests, and zero
  matching Release test symbols. No physical device or installed-product action
  occurred. A menu handshake timeout joins the earlier unresolved launch-stall
  finding; later passing repetitions do not close either reliability gate.
- P1/P2 remain active: connect the real client pairing transcript to this
  Agent, then grant/administration and Interactive execution. Include loss of
  the menu with an outstanding QR and replacement-menu recovery in the fault
  matrix; source inspection alone does not prove that recovery path.

### 2026-08-28 — real pairing, durable Observe and menu-loss repair

- [Checkpoint evidence](evidence/2026-08-28-real-pairing-agent-xpc.md): 40 signed
  cases pass in three consecutive final runs, 1,748 repository tests pass,
  Release has zero matching test symbols, and disposable cleanup is verified.
- Real pinned-TLS client pairing, matching code/key review, signed approval,
  exact replay and altered-decision rejection, saved-client authentication and
  SQLite-backed Observe sequence advancement now pass through the production
  Agent graph, including graceful and forced Agent restart.
- The outstanding-QR menu-loss test reproduced an actual retained-presentation
  defect. Fixed Agent-side retirement/generation fencing with the normative
  rule, indexed fixture and regression coverage, preserving listener/Observe
  ownership and in-flight durable approval semantics.
- P1/P2/P6 remain active. Next: signed grant/administration and Interactive
  execution through this same composition, broader pairing fault boundaries,
  and the combined Simulator journey. Earlier launch/handshake stalls remain
  open. No physical-device or installed-product action is requested yet.

### 2026-08-28 — signed Control grants, runtime and admission-race repair

- [Checkpoint evidence](evidence/2026-08-28-signed-control-agent-xpc.md): three
  consecutive final 43/43 signed matrices, 1,750 repository tests, zero matching
  Release test symbols and independently verified disposable cleanup.
- Production signed Control-grant decline/fresh approval, Agent lease issue/
  final admission, signed menu runtime install, both role authentications, two
  scheduled renewals and client Stop preserve the independent Observe primary.
- Display withdrawal during paused preparation now rejects Control without
  losing signed XPC or Observe. This reproduced a real encoder/closed-decoder
  mismatch for nil display IDs; explicit JSON null fixes both publication and
  receipt, with indexed vectors and regression tests. Signed-menu connection
  loss also retires the active runtime and its cleanup effects.
- P2/P3/P6 remain active. Active console/display and capture/input/indicator
  effects are explicit test substitutes. Durable-grant race, remaining signed
  administration/Act, surface/focus/media/input and combined Simulator work
  remain, followed by UX/performance/actual soak and final handoff. Earlier
  launch/handshake stalls remain unresolved. No physical test is requested.

### 2026-08-28 — signed revocation and replacement-menu recovery

- [Checkpoint evidence](evidence/2026-08-28-signed-revocation-agent-xpc.md): three
  consecutive final 48/48 signed matrices, 1,755 repository tests, Release seam
  exclusion and independently verified disposable job/process/state cleanup.
- Added exact reviewed revocation to the authenticated administration transport.
  The real Agent handler retires active primary/Control authority, removes grants,
  advances both revisions once and persists one receipt/security event. Stale
  reviews/altered replays fail; exact replay and revoked reconnect checks survive
  graceful/forced Agent restart.
- The new replacement-menu case reproduced a permanent router-closure defect.
  Endpoint failure now fences only that generation and retains cleanup; fresh
  authenticated generations wait for cleanup, while explicit shutdown remains
  permanent. Regression coverage includes repeated endpoint loss and late callbacks.
- Next: durable-admission/pending-revocation races, other signed administration
  and visible UI binding, bounded Act, then the combined Simulator media/input
  journey. Test platform effects remain explicit substitutes. Earlier startup/
  handshake stalls and the remaining goal work are still open; no iPhone is needed.

### 2026-08-28 — pending Control revocation and renewal fencing

- [Checkpoint evidence](evidence/2026-08-28-pending-control-revocation.md): three
  consecutive final 49/49 signed matrices, 1,760 repository tests, Release seam
  exclusion and independently verified cleanup. No physical-device activity.
- A second genuinely paired client exposed capture starting after revocation
  closed primary while Desktop preparation was paused. Binding/runtime owners
  now fence the exact pending install before serialized cleanup; primary closure
  and explicit Stop reach that fence first. Late receipts require revocation,
  and stale connection/generation events cannot cancel a different install.
- A deterministic late-lease-lookup regression exposed renewal starting after
  termination. The renewal owner now rechecks its retained attempt token. An
  unrelated full-suite failure exposed a test-helper lost wakeup; an early-resume
  latch and regression repair it without extending production deadlines.
- Next: P5 bounded Act using `NativeAudioMuteProviderV1` with an isolated
  `DefaultOutputMuteControllingV1`, real registry/grant/approval/operation routing,
  and no CoreAudio mutation. Continue P2/P3 administration and durable fault
  closure, then combine signed Agent owners with the Simulator media/input lane.
  Earlier startup stalls, required UX/performance/soak and final handoff remain
  open; the overall goal is not complete.

### 2026-08-28 — signed bounded Act core journey

- [Checkpoint evidence](evidence/2026-08-28-signed-act-agent-xpc.md): three final
  52/52 signed matrices, 1,765 repository tests across 42 runners, Release
  build/test-seam exclusion and independent cleanup verification pass.
- Added the missing generation-owned Act grant review/decision XPC route using
  the shared production registry/grant authority. Review retry, decline,
  changed-decision rejection, fresh approval and primary reconnect are tested.
  Control remains independently granted, and Observe works without Control.
- `NativeAudioMuteProviderV1` now runs through real operation routing with an
  in-memory audio controller. Read-back mismatch fails closed; exact replay,
  including after graceful/abrupt Agent restart, causes no extra execution.
  A process-dependent descriptor equality defect in the new review path was
  caught by full validation and fixed through validated schema normalization.
- Next: extend P5 with remote malicious-client denial, cancellation and
  interruption/outcome-unknown recovery plus provider/lifecycle faults, then
  combine signed Agent owners with Simulator UI/media/input. Visible Act
  administration UI, the broader P2/P3/P6 closure and remaining readiness work
  are still required. No system audio, installed products or iPhone was touched.

### 2026-08-28 — signed Act cancellation and interrupted recovery

- [Checkpoint evidence](evidence/2026-08-28-act-concurrency-recovery.md): expanded
  the signed matrix to 55 cases (three consecutive current-source passes) and
  full validation to 1,769 tests/42 runners. Release isolation and independent
  cleanup verification pass.
- Reproduced a real primary-reader bottleneck: pending provider execution blocked
  status and cancellation. Bounded concurrent Act responses now preserve the
  ordinary request lane, with overflow, teardown, revalidation and liveness tests.
- A genuinely authenticated raw client proves host-side ungranted denial. Same-
  primary running status and repeated cancel work while the test result is
  paused, with only one cancellation hook. A crash after the fake effect but
  before terminal commit becomes outcomeUnknown and never reexecutes on replay.
- P5 remains active for broader provider/lifecycle/storage fault coverage and
  combining signed Agent owners with Simulator UI/media/input. Visible Act
  administration, P2/P3/P6 and earlier startup/handshake reliability findings
  remain open, along with UX/performance/compatibility/real-time soak and handoff.
  This milestone does not require or authorize any physical-iPhone action.

### 2026-08-29 — signed end-to-end Control and automated gate closure

- The signed Agent + Simulator lane now crosses production client pairing,
  configured-route ownership and UI, pinned TLS, the disposable signed Agent,
  signed Mac XPC, Observe, bounded Act, Control grant/lease/runtime, rendered
  video, pointer, verified focus and automatic Smart Zoom, both keyboard paths,
  Stop, client restart, background/foreground and route-loss recovery.
- Three generated live repetitions and three signed test-window repetitions
  pass. The exact-current full Simulator suite passes all 16 tests in 910.204
  seconds with zero skips, including its 192+ second idle lane, five-cycle
  Stop/drop/reconnect, authenticated restart/revocation/renewal, and pairing
  regressions. A terminal decoded-frame teardown race and an Xcode 27 per-key
  idleness timeout were found, repaired and covered by focused regressions.
- Day 1 of the source-bound seven-date soak passed for 198.649 seconds. The
  fail-closed ledger requires seven distinct UTC dates and at least 518,400
  elapsed seconds. The daily task was paused at the user's request on 2026-08-29
  after preserving Day 1; it cannot count duplicate dates, changed source,
  short runs, physical devices, installed apps or failed cleanup. The campaign
  therefore remains 1/7 and will not advance unless explicitly resumed.
- Final signed repetitions, repository validation, unsigned release evidence,
  latency/resource reconciliation and the eventual physical checklist remain.

### 2026-08-29 — reconciled automated gate and physical handoff

- [The consolidated checkpoint](evidence/2026-08-29-prephysical-automated-gate.md)
  binds signed journeys, the 55-case Agent matrix, 16-case Simulator suite,
  complete repository gate, construction-only release evidence and the exact
  remaining boundaries.
- A source-bound 199.018-second generated-Simulator run now retains one-second
  CPU/RSS observations for only the disposable host and Simulator client. It is
  a diagnostic baseline, not a release-budget pass; physical latency, energy,
  battery, thermal and real-route measurements remain explicit.
- The [closed performance profile](../spec/performance-acceptance/v0/README.md)
  freezes every existing latency/media/storage/soak number, operationalizes the
  one-hour RSS-growth gate, and prevents eight unresolved physical budget
  classes from being mislabeled passed. Its validator is part of `validate.sh`.
- [`physical-acceptance-checklist.md`](physical-acceptance-checklist.md)
  consolidates clean install, signing, pairing, Observe/Act/Control, adaptive
  UX, lock/recovery, routes, performance, update, removal, accessibility,
  usability, security and promotion evidence with fail-closed stop rules.
- All currently possible short-duration automated work is complete. P8 remains
  active solely because the exact-source campaign is Day 1 of seven; real time
  cannot be substituted or backfilled. Its scheduler is intentionally paused by
  user request; this does not convert the incomplete elapsed-time gate into a
  pass or a deferral.
