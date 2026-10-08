# Native playback through the normal client owners

## What changed

The normal workspace now accepts an optional live-product factory, preserving
its existing Observe, Act and Control paths. A generated Debug-only Simulator
application supplies the experimental Moonlight adapter through that factory.
Its pairing, primary connection, Control approval, role channels, bootstrap
acknowledgement, UIKit surface and native video owner are production components.
The Mac side uses disposable signed helpers and real local XPC to enroll the
client certificate and start the managed Sunshine host.

The selected-primary network state exposes its authenticated numeric route only
for the exact current connection ID. IPv4 and IPv6 routes are available after
selection; DNS and Bonjour names remain unavailable without separately measured
numeric-route evidence. The normative launch document and manifest-indexed
admission fixture were updated before this behavior. Four parameterized route
checks passed, including selection, replacement, wrong-ID and disconnect cases.

The live journey found two startup defects:

- The UIKit product closed its configured native preparer while the bootstrap
  frame acknowledgement was still pending. It now preserves that inert adapter
  until the first active refresh. After native preparation starts, loss of the
  active surface still cancels and drains it immediately; product close remains
  the terminal cleanup path.
- The experimental Mac lease wrapper inherited an unavailable display-catalog
  method instead of forwarding to its actual runtime adapter. The normal live
  screen automatically requests this catalog. Explicit catalog/selection
  forwarding now keeps that request on the existing authenticated XPC path.

The generated app also embeds the engine's OpenSSL runtime dependency. Its
initial omission caused a launch-time loader failure, before any app journey.
No experimental dependency was added to a permanent target.

## Verified snapshot

Stable Xcode 27.0 (27A266a), macOS 27.2. Native candidate source input SHA-256:
`a4aafe954c2758ed5c3df36d3739067a1f0dfaa0199e4b5e3078c529fb722b1a`.
Pinned Sunshine binary SHA-256:
`0d84ac61a653f61237b60f927bbec7228d7bdc2e3f00a54ec705447584e837d2`.

Simulator: MacCompanionWebRTCQA,
`8FF65ABB-572E-4EE4-9A9F-F61AA302A586`, iOS 27.0.

The finalized report is
`/private/tmp/maccompanion-agent-xpc-evidence.okexcn02/signed-simulator-report.json`:
one UI test passed, zero failures, cleanup verified. Its combined app/harness/
signed-helper source fingerprint is
`9d7c885817beaccf98665f8af18e2d2a6a15196ce7b4443e48e3774d0fd15b3b`.
The shared probe support hash is
`0e639c2f2368c1899ec5c613522c61af31939b183574aa9ee51f389ea11feed2`.

That test verifies two complete cycles on the same authenticated primary:

1. Real pairing, independent Act/Control grants and fresh authenticated selection.
2. Bootstrap decode and the exact surface acknowledgement before enrollment.
3. Managed host enrollment, mutual TLS, Desktop launch and native decode.
4. The normal native owner admits the exact decoded geometry and displays the
   frame. Each cycle's surface pixel check passes; private test attachments were
   inspected and show streamed desktop content. No image was added to Git.
5. Native presentation adds no input events. The second cycle accounts for the
   previous Stop's required release-all event rather than expecting a zero
   cumulative counter.
6. Actual primary Stop removes the live surface and drains the host/private
   state. Observe still succeeds on the same primary, and a fresh native session
   starts without pairing again.

Xcode's optional Simulator diagnostics collection stalled after the successful
test. Only that exact diagnostics child was terminated; Xcode then exited 0 and
finalized the result bundle. The runner now explicitly disables this optional
collection using the installed Xcode's supported flag. The recorded UI report
predates that operational runner-only flag; native/application sources match the
candidate hash above.

The separate signed native lane was rerun sequentially after the Simulator
host was released. All four stages passed and cleanup was verified in
`/private/tmp/maccompanion-agent-xpc-evidence.631xw8j2/native-report.json`.
It proves enrollment, actual HTTPS launch, two Control lease renewals, host
retirement and Stop preserving Observe at the same candidate hash. A concurrent
attempt failed during listener startup and is not passing evidence.

Both unsigned SDK builds match this candidate hash. Fifteen native component
tests passed on the owned Simulator: four engine tests and eleven adapter/owner/
TLS tests. The inventory verifies all six framework binaries across the two
SDKs and still reports `releaseAdmitted: false`. Repository validation passed
with the stable toolchain; the fixture index contains 104 validated JSON files.

## Limits and next work

Follow-up: [continuous native Stop and restart](2026-09-27-continuous-native-stop.md)
repairs the race described below and verifies two continuous-bootstrap cycles
at a newer source snapshot. This checkpoint retains its original finite-bootstrap
evidence and limitations.

This is an authenticated loopback integration through normal owners in a
generated experimental app. Local consent, key custody, the bootstrap pixels,
indicator and input effects are test substitutes. The continuing native stream
is actual managed Sunshine capture of the approved physical display.

The generated bootstrap stops producing after its acknowledgement; queued
records still use the real role/XPC drain. A separate trial with continuous
legacy bootstrap production exposed a Stop race: a late media publication can
invalidate the menu connection and prevent restart. The finite-bootstrap native
result does not repair or validate continuous legacy-stream shutdown. Repairing
that production race requires its own lifecycle/protocol evidence and any
normative fixture updates before security behavior changes.

Native pointer, keyboard, modifiers and shortcuts remain disabled pending native
presentation/input admission, including actual desktop geometry, letterboxing,
focus and input fences. The displayed native frame alone grants no input.

Permanent app composition still supplies no experimental adapter/backend.
Dependency/corresponding-source admission, Mac process/TCC ownership, permanent
signing gates, normal-app packaging, LAN behavior, signed installation and
physical iPhone acceptance remain open. No installed Mac product, physical phone,
privacy setting, production Keychain or publication was changed.
