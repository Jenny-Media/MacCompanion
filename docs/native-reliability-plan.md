# Native reliability work

The acceptance goal is a normal Mac/iPhone remote desktop session that survives
view changes, resize, Spaces, foreground recovery and ordinary network loss.
This document tracks implementation and evidence separately. Passing unit or
Simulator tests does not establish physical acceptance or production readiness.

## Measured cause of slow switching

The previously installed normal client drains its renderer and native enrollment before
selecting a new surface. It then creates an enrollment, host and streaming
connection. The fresh presentation receipt precedes input admission.

On 2026-10-03, a source-bound normal Simulator journey completed 22 switches:
20 Window/Desktop changes and two display changes. Median completion was
3,047 ms and p95 was 4,658 ms. Native preparation alone had a p95 of 3,060 ms.
These are local diagnostic measurements, not physical Wi-Fi measurements.
The Mac capture and video were real; final input injection was synthetic.

No multi-second smoothing delay is intentional. Existing 100 ms capture cutover
protects against queued samples and is insufficient to explain these timings.

## Implementation order

1. **Own each complete transition.** Implemented: selection remains reserved
   through fresh presentation/input, overlapping local selections cannot retire
   Control, and late workspace publications/completions cannot release the gate.
2. **Measure the entire journey.** Implemented: monotonic, content-free stages,
   closed error classifications, complete/failed/cancelled/incomplete accounting,
   and isolation from historical diagnostic log entries. The UI journey must
   also succeed; a completed selection reply or old successful record is insufficient.
3. **Recover media independently.** Implemented: bounded first-sample waiting
   and one Desktop recovery under the still-current original Control binding.
   Recovery cannot loop; it rearms only after 30 healthy seconds or a manual view
   choice. Stop, background, expiry and Control loss remain terminal fences.
4. **Keep the native connection for ordinary switches.** Connected in the normal
   client, Agent, Mac backend, capture child and encoder. Peers opt in explicitly;
   a switch pauses capture/input, proves a fresh logical enrollment, updates the
   existing stream filter and waits for the new frame epoch. Runtime acceptance
   now passes the 202-switch gate for the latest candidate, with physical
   acceptance still pending. A preceding candidate passed 202 retained switches,
   while the following preflight candidate failed after 144.
   The following watcher-fix candidate also failed after 63 retained switches
   and a successful Desktop recovery: its next Window handoff had no fresh
   presentation. The process watchdog reported invalid local Control/capture
   while the original deadline was valid. Exact validation classification is
   being investigated; the phase fix alone does not resolve reliability.
   The diagnostic follow-up also loses its native selected capture after 151
   retained switches and recovers Desktop; its UI journey still fails. An
   expanded controlled resize/reselection journey passes and proves reuse of
   the fresh recovery host. Native-child rejection classifiers now pass their
   source builds and contracts. The diagnostic source exposes a separate
   controlled-resize failure: shared retirement waiters return before exact
   retired ownership is published, making health tear down local XPC and
   cancel recovery. A 32/32 regression reproduces it; publishing inside the
   shared drain repairs all 32 and preserves malformed-evidence/wrong-scope
   rejection. Open-picker recovery feedback and reselection acceptance
   now pass on the rebuilt normal client after a fresh surface-bound inventory
   refresh. Required stable validation and both SDK/all normal builds pass;
   the final-source gate passes 202 retained switches, 204 advancing presentations
   and one host/native connection per Control session. Its complete journal and
   all cleanup pass. Both normal updates are installed with pairing preserved;
   Mac app/Agent listener run, while the affected iPhone is locked. Simulator
   median is 912 ms, p95 1,180 ms; physical latency acceptance remains pending.
   Final-source resize, movement, closure, background and network recovery pass.
   A one-minute Desktop hold also passes; Mission Control automation times out
   before any ordinary Space change can be verified, leaving that case open.
   Keep both outcomes in the evidence ledger. A deterministic backend watcher
   race also reproduced healthy retention being retired after a suspended
   phase check. Local lifecycle generations now fence obsolete assessments;
   tests also require current original Control loss to drain. The first live
   candidate exposed a Retina native-pixel
   mismatch before initial video; that failure is retained and the corrected
   geometry now passes a strict regression test.
5. **Pass real acceptance.** Pending: repeated physical switches, resize/Spaces,
   background and network recovery, long sessions, and a same-device comparison
   against native Sunshine/Moonlight.

## Retained connection handoff

The normative design is `spec/capability-protocol/v0/native-stream-continuity.md`.
Its complete implementation must preserve the original primary, registered
session key, Control generation/deadline, native certificates, host process,
encrypted video connection and encoded canvas.

```mermaid
sequenceDiagram
    participant Client
    participant Authority as Agent / Mac authority
    participant Capture
    Client->>Client: Fence and drain old input; pause decoder
    Client->>Authority: Retain exact predecessor
    Authority->>Capture: Suspend old capture delivery
    Authority-->>Client: Confirm retained transport
    Client->>Authority: Select new view and prove fresh enrollment
    Authority->>Capture: Update existing SCStream; attach new frame epoch
    Capture-->>Client: Fresh independently decodable frame
    Client->>Authority: Correlated presentation receipt request
    Authority-->>Client: Current geometry and fresh input admission
    Client->>Client: Release selection gate
```

Retention does not preserve presentation or input authority. A fresh existing
golden challenge/proof binds the new surface to the exact retained certificates.
Queued pictures keep their capture epoch through encoding; emission-time
relabeling is forbidden. Every failure, Stop or uncompleted handoff joins the
owned drain. Unsupported peers keep the existing replacement path.

## Acceptance gates

- At least 200 normal switches across Desktop, displays and selected windows;
  every completed switch has advancing frames and correct fresh input mapping.
- Ordinary switches keep one host process and one video connection. Record
  identity/count evidence without addresses, certificates, screenshots or input.
- Physical local Wi-Fi p95 switch completion below one second, measured from
  local selection fencing to fresh input admission.
- Resize, closed/moved windows, Spaces, rapid selection, Stop during selection,
  stale callbacks, background/return and network interruption each have an
  explicit passing outcome and bounded recovery.
- One hour on the affected iPhone, including keyboard/modifiers, pointer and
  switching; no terminal loss requiring a new Control request in healthy operation.
- Compare the same Mac, phone, network, codec, resolution and bitrate against
  native Sunshine/Moonlight. Separate initial startup from view-switch latency.

A short successful run does not meet these gates. Preserve failing runs and
their classifications; do not exclude them from reliability denominators.
