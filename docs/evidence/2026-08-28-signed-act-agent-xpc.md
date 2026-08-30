# Signed bounded Act checkpoint — 2026-08-28

The pre-physical goal remains active. This extends the previous 49-case
signed Agent/XPC matrix with three Act cases. No installed product, production
Keychain, TCC setting, real audio state, Simulator or physical iPhone is used.

## What now runs

- Signed Mac administration requests an Agent-owned review for one published
  capability and exact retained device. It cannot supply effects, descriptors,
  revisions or grants. The reply retains the complete descriptor/provider facts,
  registry generation, local device name, revisions, current grant set and a
  five-minute lifetime. Control's reserved identifier is excluded from this path.
- A generation-owned `LocalCapabilityGrantHandlerV1` delegates registration and
  decisions to the same `AgentCapabilityAuthorityV1` used by discovery and
  operation execution. Approval fences primary ingress before the existing
  exact SQLite grant transaction and refreshes inventory before release. Decline
  does not change authority or interrupt primary. Pending reviews disappear on
  menu-generation loss; exact completed decisions have a bounded handler-local
  receipt cache, not a claimed restart-persistent grant-decision cache.
- Closed Act request/review/decision codecs use the existing signed device-
  administration XPC family, authorization methods, single-flight gate, size
  limits and timeouts. A tagged decision envelope distinguishes Act from the
  existing Control decision. Normative IPC text and the indexed fixture were
  updated first; cryptographic transcripts/signing rules were not changed.
- The isolated Agent advertises `NativeAudioMuteCapabilityV1` and loads the real
  `NativeAudioMuteProviderV1` with an in-memory `DefaultOutputMuteControllingV1`.
  The second execution deliberately returns a mismatching read-back. It never
  constructs the CoreAudio controller. Client catalog, router, operation,
  approval, persistence and provider owners are production implementations.

## Signed journey assertions

1. Initially empty catalog rejects the ungranted operation **at the client**.
   This is not a malicious-client test of remote server denial.
2. Exact review retry returns the same facts. Decline and its exact retry leave
   grants unchanged; a changed decline-to-approve replay is rejected.
3. A fresh approval grants only Act, retires the old primary, and reconnects
   with a fresh authenticated session and one-capability catalog.
4. Desired `muted=true` succeeds with a verified result. Exact repeated invoke
   does not execute again. A separate `muted=false` operation hits the injected
   bad read-back and fails as `provider.rejected`; the next succeeds.
5. Exactly three test audio executions occur. Observe remains available and
   Control remains inactive throughout the Act journey.
6. After graceful and abrupt Agent restarts, status and same-operation invoke
   replay succeed with zero additional provider executions. Persisted status
   does not claim to retain the earlier result payload.
7. Subsequent Control grant review retains the separate Act grant. All earlier
   signed pairing, Control, revocation and pending-install race cases still run.

The saved operation checkpoint and software identities are private temporary
test files removed by the runner. Evidence contains no command parameters,
key material, QR payloads, user content or real audit database.

## Defect found during validation

The first full validation failed the new review round-trip test:
`/private/tmp/maccompanion-act-final-validation.log`. `CanonicalJSONValue`
represents object members as arrays; `JSONDecoder` keyed-container order is not
stable across processes. Retaining that order in the new descriptor wrapper
made otherwise identical reviews compare unequal. A separate focused run could
pass, so a single green run was insufficient evidence.

The wrapper now reconstructs the validated domain descriptor/schema before
retaining its wire projection. The strict canonical-byte and unknown-field
checks remain unchanged. Repeated decode coverage, malformed effects/provider/
time/grant tests, and request/decision replay, expiry, registry/name changes,
generation loss and independent Control preservation tests cover this path.
The final focused run passes six tests (including parameterized cases):
`/private/tmp/maccompanion-act-descriptor-after.log`.

Initial integration logs are not final-source evidence:
`ntm892fg` failed compilation; `qatjq6g7` caught missing explicit catalog loading
in the harness; `hzjf549n` passed 52 cases before descriptor normalization and
the report-limit corrections. The normal UI's explicit catalog-load step is
now present in the harness. A subsequent normalization initializer compile error
was corrected before the final focused run.

## Final signed verification

Three consecutive final-source matrix runs pass **52/52**, with independently
verified cleanup:

- `/private/tmp/maccompanion-agent-xpc-evidence._kh6yffs/report.json` — 52.781s.
- `/private/tmp/maccompanion-agent-xpc-evidence._guwmlih/report.json` — 41.858s.
- `/private/tmp/maccompanion-agent-xpc-evidence.ftrd0j7c/report.json` — 43.127s.

All have source fingerprint
`49eb9941217331d542bb00362308f4c4dad71ae58547f8ad1452144dd1b1393b`,
recomputed independently after the runs. Exact case sets, missing UUID launchd
jobs, deleted test stores/helper copies/plists and absence of matching helper
processes were rechecked independently. Evidence logs remain available.

Command: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify_agent_xpc.py`,
three times, stopping on failure. No fingerprinted source changed during or
between those runs. Durations are short integration checks, not soak evidence.

## Full validation and Release isolation

- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/validate.sh`
  exits zero: **1,765 tests across 42 runners**, all 77 indexed JSON fixtures,
  repository/policy/source-isolation checks, platform builds and C syntax
  checks. Log: `/private/tmp/maccompanion-act-final-verified-validation.log`.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --package-path Packages/MacCompanionKit -c release --target CompanionAgentApplicationPlatform`
  exits zero. Log: `/private/tmp/maccompanion-act-final-release.log`.
- Defined-symbol inspection (`xcrun nm -U`) of the same eight startup/transport/
  network/runtime objects as the prior checkpoint finds **401 Debug test-seam
  symbols and zero Release test-seam symbols**. The matcher includes `Isolated`,
  `isolatedTestID`, `isolatedLoopback`, `makeUnstartedLoopbackListener`, and
  `startForInstalledTestRuntime`. The new probe/controller remain in the
  Debug-only experiment target, which is not a Release dependency. The source
  isolation guard explicitly forbids constructing CoreAudio in the Act probe.
- `git diff --check` passes. No commit, production installation, publication,
  signing/account configuration change, or physical-device action was made.

## Remaining work

P5 is not complete: malicious-client denial through remote ingress, cancellation
semantics, interruption after execution admission and outcome-unknown recovery,
provider/lifecycle loss, and broader fault coverage remain automatable work.
The visible Act administration UI and combined Simulator journey remain open.
An exact decision retry cache surviving Agent/menu restart is not provided by
this slice; durable state must be re-read and presented by recovery UI.

Software key custody and user-presence gestures, active-console/display facts,
audio hardware and Control capture/input/indicator are explicit substitutes.
No Face ID, actual audio mutation, hardware performance, stable-toolchain
compatibility, installation or release claim follows from these tests. Earlier
launch/handshake stalls and the other pre-physical worklist requirements remain
open. Short repeated runs are not the required seven-day soak.
