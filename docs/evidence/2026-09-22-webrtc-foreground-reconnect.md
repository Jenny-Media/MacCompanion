# Automatic foreground reconnection in the disposable WebRTC receiver

On September 22, the operator requested automatic background-to-foreground
reconnection before completing the short Wi-Fi interruption test, and chose
to skip the longer physical soak. Long-session reliability remains unverified
and does not block the next development step.

## Behavior

Backgrounding clears video, retires the old frame sink and peer, and restores
normal device idle behavior. Returning to the foreground automatically requests
a fresh media peer through the existing local/paired-device file relay. Both
ends use a new session ID; the captured source, generation, and original test
expiry remain fixed. A request ID correlates the replacement offer and answer.
Late callbacks from an older peer cannot display into the new session.

Stop clears pending resume intent. A replacement offer delivered after Stop is
ignored. Returning after expiry cannot extend or restart the original test.
This covers in-process scene transitions, not recovery after process eviction
or device reboot. The receiver still requires the bounded test relay to be
running; these files are not production signaling or authorization.

## Validation

- Mac capture and signed iOS device receiver builds passed on Xcode 27.0.
  The Simulator build passed with the two existing codec-setter warnings.
- A native Simulator UI test passed two Home/reopen cycles, verifying a new
  session ID and advancing frames each time. It then pressed Stop, went Home,
  reopened, and verified that Stop persisted with no active session.
- A separate UI test passed expiry in the background using a 30-second host
  lifetime. Reopening reported expiry and no active session.
- The first expiry test started after its 30-second lease had already elapsed
  and failed its initial Receiving check. Its evidence is retained. The passing
  repeat chained fresh setup directly into the already-built UI test.
- The updated app was installed on the authorized iPhone 18 Pro Max; its fresh
  captured-stream baseline passed. Diagnostics observed a second Receiving session
  and then a stopped state, with video hidden and normal idle behavior restored.
  The operator subsequently reported that it stopped on its own; the earlier
  attribution to an intentional Stop action is withdrawn.
  Operator foreground and Wi-Fi observations remain pending; an actual Wi-Fi
  outage must not be inferred from background/foreground transitions.
- The required repository validator was rerun. It again stopped at
  `validate_platform_mac_assessment.py` because its fixed Xcode-beta stapler
  path is absent. Repository material validation passed. The tool-path issue
  remains separate from the successful experiment builds and UI tests.

The two earlier Wi-Fi setup attempts ended when the receiver backgrounded
before a requested Wi-Fi toggle began. They establish neither a Wi-Fi failure
nor a Wi-Fi recovery pass. Their status logs and setup audits are retained.

Exact source hashes, build/test result paths, and current manual acceptance are
in the [JSON record](2026-09-22-webrtc-foreground-reconnect.json). The earlier
[streaming checkpoint](2026-09-22-webrtc-streaming-probe.md) describes the older
receiver's intentionally stopped-on-background behavior; this checkpoint
supersedes that behavior without changing those historical test outcomes.

Production targets, independent grants, pairing, and input remain unchanged.
The next hands-on check is Home/reopen followed by about ten seconds of Wi-Fi
disconnection and restoration. Record visible video clearing and whether
current frames resume, separately from any fresh-session foreground recovery.

The operator reported that the second physical reconnect failed and stopped
on its own. The initial Simulator result does not establish physical repeat
reliability. See the [retry follow-up](2026-09-22-webrtc-reconnect-retry.md).
