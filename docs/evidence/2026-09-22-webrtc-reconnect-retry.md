# WebRTC reconnect retry follow-up

The operator reported that foreground reconnection worked once, then failed
and stopped without pressing Stop. The earlier attribution to a deliberate
Stop action is withdrawn. The old diagnostics recorded a stopped state but
did not retain its trigger; the exact cause of that event remains unproven.

Source review found two independent weaknesses: negotiation or terminal peer
failure cleared resume intent, and answer creation could label the receiver
Receiving before any video frame arrived. Both are corrected in this isolated
experiment. A failed peer now preserves the original bounded resume intent,
retries up to three times with backoff while active, and allows a later
foreground return to retry within the unchanged expiry. A missing first frame
also triggers recovery. Only current frames produce the Receiving state.

Stop and expiry still cancel pending automatic work. New diagnostics retain a
bounded transition log, automatic retry count, and Stop-control callback count.
A control callback records activation, not proof of deliberate human intent.
The app remains an in-process experiment using the paired-device/local file
relay, not production signaling or authorization.

## Validation

| Check | Result |
|---|---|
| Mac, iOS device, and Simulator builds | Passed with the two existing codec-setter warnings |
| Simulator repeated foreground test | Eight cycles passed, including interruptions during reconnect, fresh session IDs, advancing frames, and Stop persistence |
| Injected negotiation failure | Separate eight-cycle run passed with one recorded automatic retry after deliberately failing the first replacement negotiation |
| Physical iPhone 18 Pro Max | Eight-cycle native UI regression passed on the repeat run, including fresh sessions and advancing video; its final explicit test-button action was the only recorded Stop-control callback |
| Physical first attempt | Retained failure: XCTest did not observe the requested Home transition at line 48. Its cause is not established; it is not attributed to operator interference or WebRTC |
| Expiry regression | Passed with the revised code; a 30-second test expired in background and did not reconnect on return |
| Required repository validator | Again blocked by the existing absent fixed Xcode-beta stapler path; no full-validation pass is claimed |
| Manual Wi-Fi interruption | Operator confirmed Wi-Fi recovery and background recovery; reported slow loss indication and slower foreground recovery |

The initial Simulator launch used the wrong tool argument for fault injection;
that result is retained as the normal-path eight-cycle run. The separate fault
run used the documented launch argument, and diagnostics confirm that the
injection and automatic retry actually occurred. An injected negotiation error
is not a Wi-Fi outage.

The [JSON record](2026-09-22-webrtc-reconnect-retry.json) records source hashes,
compact results, and the local evidence directory. Raw test bundles and device
diagnostics stay outside the repository. No long physical soak was added; the
operator's decision to skip it remains in effect.

Production targets, independent grants, pairing, and input are unchanged. The operator confirmed both recovery paths. Wi-Fi recovery felt fast, while
loss indication and background recovery need responsiveness work. This is
qualitative manual evidence: the latest prepared relay does not contain a
matching transition trace, so no exact Wi-Fi timing is attributed to it.
