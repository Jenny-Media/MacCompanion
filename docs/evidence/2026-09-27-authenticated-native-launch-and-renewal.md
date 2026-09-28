# Authenticated native launch and renewal continuity

## What changed

A new disposable signed integration lane joins the normal production pairing,
primary authentication, Control grant/approval, generated bootstrap media,
local XPC, menu runtime, native certificate enrollment and managed Sunshine host.
The client decodes the bootstrap H.264 into a retained Mac pixel buffer and sends
the normal acknowledgement before native preparation. It then attests its
in-memory TLS certificate, accesses the sealed native host with mutual TLS,
launches the sole Desktop, validates the encrypted stream route, and proves the
native enrollment and HTTPS listener remain current across two scheduled Control
lease renewals. Actual primary Stop drains the host and its private state while
Observe continues on the same primary.

The live lane found and repaired four defects:

- Native client acceptance imposed a two-hour maximum on a four-hour Control
  session. It now projects the authenticated acceptance lifetime once, using the
  smaller of that lifetime and positive wall-clock time remaining. Overflow,
  expired and overlong lifetimes fail closed; clock skew cannot add lifetime.
- A default async unavailable snapshot method shadowed the concrete menu runtime
  read in the backend factory closure. The protocol now requires an explicit
  implementation; the test substitute explicitly returns unavailable.
- The experimental Swift process owner and C supervisor also imposed two hours.
  Both now enforce Control's four-hour maximum without changing the supplied
  original deadline. Admission/overlong and real child cleanup checks pass.
- Native client authority treated the surface wire descriptor's ten-second
  freshness as the lifetime of an acknowledged active surface. The normative
  surface protocol defines relative validity as freshness, not authorization.
  Native authority now retains the original Control deadline and exact active
  session/epoch/surface/revision checks. Descriptor admission, proof deadlines,
  replacement, Stop, role loss and revocation remain independently enforced.

Specifications and manifest-indexed admission fixtures were updated before the
behavior repairs. Signing fields and golden cryptographic vectors are unchanged.
The signed runner also waits for actual primary listener readiness before pairing
and bounds the wait for removal of its exact disposable launchd job during cleanup.

## Verified snapshot

Stable Xcode 27.0 (27A266a), macOS 27.2. Source input SHA-256:
`c97da76844ca8bd379ec433b8cffe754e285e243cd12de5e6b36ef828786efdf`.
Pinned Sunshine binary SHA-256:
`0d84ac61a653f61237b60f927bbec7228d7bdc2e3f00a54ec705447584e837d2`.

- Signed native lane: all four stages pass; private helper/job/state cleanup is
  verified. Its report now records authenticatedLocalXPCFlow,
  authenticatedPrimaryFlow, actualNativeHTTPSLaunch and nativeSurvivesLeaseRenewals
  as true. Native decoded frame, phone presentation and release admission remain
  false. Evidence: `/private/tmp/maccompanion-agent-xpc-evidence.6od8674q/native-report.json`.
- Process owner checks pass denied, expired and overlong admission, four-hour
  deadline admission through the real supervisor, live revocation, terminal
  owner and concurrent Stop. This is admission evidence, not a four-hour soak.
- Six client approval/native-routing cases cover all three reply delivery orders,
  valid four-hour and rejected overlong lifetimes, acknowledged-surface continuity
  beyond descriptor freshness, and cancellation/late-reply fencing.
- Stable `bash scripts/validate.sh` exits 0. Log:
  `/private/tmp/maccompanion-authenticated-native-validation.log`.
- Eight native TLS checks and the managed host admission/launch/cleanup probe pass.
- Fifteen native component checks pass on the dedicated MacCompanion Simulator
  `8FF65ABB-572E-4EE4-9A9F-F61AA302A586`; both unsigned SDK builds pass.
- Three normal Control Simulator UI journeys and five pairing reliability
  checks pass; disposable runtime/credential cleanup completes. Report:
  `/private/tmp/maccompanion-feature-tests.Gtf0A3/report.json`. This is a normal
  Control regression, not native phone playback evidence.
- The live native report, host/TLS probes and all six framework inventory records
  match the source fingerprint above. Inventory remains releaseAdmitted=false.

Reproduce the signed lane with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 scripts/verify_native_agent_xpc.py \
  --root /private/tmp/maccompanion-sunshine-moonlight-20260926
```

First build the managed test supervisor with `test_managed_host.py` against the
pinned source-built host. The runner constructs an isolated temporary package
outside Git, statically links its native test TLS dependency, and uses UUID-owned
signed helpers and private state. It adds no dependency to permanent targets.

## Limits and next step

This joins actual authenticated production owners through real primary TLS and
signed local XPC. Software test custody and consent, generated bootstrap pixels,
indicator/capture/input effects and the loopback route are explicit substitutes.
The bootstrap decoder runs on the Mac and retains a pixel buffer; no visible
phone frame or native Moonlight decoder is exercised by this lane. HTTPS launch
success and an encrypted route do not prove decoded native video or presentation.

The default Mac app still has no admitted managed host factory, and the normal
UIKit app does not automatically supply the experimental native preparer.
Dependency/process/TCC admission, native presentation and input, corresponding
source packaging, signing, installation and physical acceptance remain open.
Installed apps and the physical iPhone were untouched.

Next: compose the native preparer and renderer into the normal client owners in
a disposable Simulator target, then verify a visible decoded native frame,
Stop/reconnect and presentation/input fences under this authenticated host lane.
