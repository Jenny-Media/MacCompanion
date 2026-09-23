# WebRTC recovery responsiveness follow-up

The operator confirmed that Wi-Fi interruption recovery and background recovery
worked with the preceding build. Wi-Fi recovery felt fast, but loss indication
and return from background were slow. This is qualitative operator evidence;
the latest prepared manual relay did not capture a matching transition trace.

## Changes confined to the experiment

- Clear stale video after 1.5 seconds without a presented frame, checked every
  0.5 seconds. Show “Waiting for video” without declaring a network outage or
  replacing an otherwise connected peer. Fresh frames restore presentation.
- Include the pending reconnect request in the bounded receiver status snapshot,
  saving a paired-device file transfer per idle relay iteration. Keep the same
  session, generation, request correlation, and original expiry validation.
- After forwarding a request, wait at most 1.5 seconds for the local host offer
  before starting another device read. No network signaling service was added.

Use the matching receiver and relay versions. Production targets, independent
grants, pairing, input, and dependency selection are unchanged.

## Evidence

| Check | Result |
|---|---|
| Simulator and signed iPhone build | Passed; revised receiver installed on the iPhone 18 Pro Max |
| Mac host | Reused the prior signed app; all four Mac source hashes match |
| Four-second capture-process pause | Simulator hid stale video after 1.65 seconds and resumed about 0.11 seconds after the host resumed, on the same session |
| Simulator foreground regression | Eight cycles passed, including one injected negotiation failure, automatic retry, interrupted reconnects, advancing frames, and Stop persistence |
| Expiry | Revised receiver passed the 30-second background expiry regression |
| First physical UI attempt | Failed before tests started: automation mode initialization timed out |
| Physical UI retry | Failed its 40-second Receiving wait during one foreground cycle; eventual recovery was recorded |
| Required repository validation | Blocked by the existing absent fixed Xcode-beta stapler path; no aggregate pass claimed |

The capture pause verifies stale-frame handling, not a physical Wi-Fi outage.
Its recovery timing is a diagnostic observation, not glass-to-glass latency.

The revised physical trace contains eight foreground recoveries in approximately
2.7–3.7 seconds and one in 61.1 seconds. Earlier physical traces generally took
4.7–6.5 seconds. These are activation-to-recorded-Receiving observations from
partial and complete runs, not a controlled benchmark or a passing physical
regression. All measured samples, including the slow one, are retained in the
[JSON record](2026-09-22-webrtc-responsiveness.json).

During the slow cycle, four consecutive paired-device status copies each hit
the 15-second tool timeout. About 59.6 seconds elapsed before the receiver
admitted the replacement offer, followed by about 1.5 seconds to Receiving.
The tool timeout's underlying cause is unresolved. This isolates the observed
delay to the period before media negotiation could proceed; it does not prove
consistent physical recovery or justify tuning WebRTC ICE based on that delay.

## Next step

Keep the faster stale-frame indication. Before assessing production foreground
latency, move the experiment's offer/answer/reconnect exchange onto the app's
authenticated session channel through the required protocol and authorization
review. Avoid expanding this temporary device-file relay into a custom signaling
service. Reuse WebRTC for media transport and keep existing authorization and
expiry boundaries. The remaining physical timing result stays open until that
path is tested; no longer physical soak was added.

Raw diagnostics, synthetic-window test results, build logs, and result bundles
remain in the private local evidence directory named in the JSON record.
