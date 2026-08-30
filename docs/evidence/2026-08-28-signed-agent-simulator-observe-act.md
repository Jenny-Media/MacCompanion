# Signed Agent + Simulator end-to-end checkpoint

Date: 2026-08-28 through 2026-08-29
Status: complete for the disposable pre-physical boundary; physical and
installed-product claims remain explicitly excluded.

## What now runs together

The journey crosses the iOS Simulator UI, production client pairing/custody
formats, configured-route application owner and workspace, pinned TLS and
application authentication, a UUID-scoped disposable signed Agent, signed Mac
XPC, production Observe and Act routing, Control grant/lease/final admission,
role authentication, media decode/render and input.

One run proves:

- fresh QR pairing and exact saved-client reconnect;
- verified Observe before and after Control;
- signed Act grant and `setAudioMuted` through `NativeAudioMuteProviderV1`
  with an in-memory test audio controller;
- client-process termination/relaunch with durable production-format custody;
- signed Control approval, lease issuance and role proofs;
- visible non-black video, pointer delivery, verified focus replacement and
  automatic Smart Zoom;
- native composed text and ordinary direct iOS keyboard input;
- Stop with keyboard visible while retaining the Observe primary;
- background/foreground retirement and fresh explicit Control;
- route offline/online recovery that retains pairing, selects a new primary,
  restores Observe and never restores Control implicitly.

The local test bridge substitutes the Mac user's consent interaction. It is
Debug-only, loopback-only, token protected and bounded to the exact pairing,
Act/Control grant and sanitized status commands required by the journey. It
does not weaken signing or peer identity checks and is excluded from Release.

## Final exact-source repetitions

All three final reports bind the same source fingerprint:

`7e10132d98004124bdb13cc176edfda9ab708abbc5b3363fd67c4092b40e192c`

| Report | Elapsed | XCTest | Cleanup |
| --- | ---: | ---: | --- |
| `/private/tmp/maccompanion-agent-xpc-evidence.p42m8qcx/signed-simulator-report.json` | 113.582 s | 1/1 passed | verified |
| `/private/tmp/maccompanion-agent-xpc-evidence.7k6z6yva/signed-simulator-report.json` | 112.485 s | 1/1 passed | verified |
| `/private/tmp/maccompanion-agent-xpc-evidence.9g53m0fj/signed-simulator-report.json` | 115.060 s | 1/1 passed | verified |

Every report records zero failures, skips and expected failures. The runner
re-hashes source after the test, owns a per-Simulator lock, terminates only its
UUID-scoped Agent/menu jobs and app, removes disposable software keys/stores,
and refuses a pass if cleanup cannot be confirmed.

The exact-current complementary Agent/XPC matrix is:

`/private/tmp/maccompanion-agent-xpc-evidence.jyt7hr9l/report.json`

It passes 55/55 signed multi-process checks with verified cleanup. That matrix
separately proves graceful and abrupt Agent process restart, malformed and
wrong-identity rejection, menu replacement, real pairing/reconnect, signed Act
cancellation/outcome-unknown behavior, signed Control final-admission races,
menu loss, reviewed revocation, revoked reconnect and revocation during paused
preparation.

## Broader Simulator and real-window evidence

- Three generated live executions passed in
  `/private/tmp/maccompanion-feature-tests.HxwajT/report.json` (229.209 s).
- Three signed test-owned real-window executions passed in
  `/private/tmp/maccompanion-feature-tests.Rpz6dW/report.json` (228.223 s).
- The final full suite passed 16/16 with zero skips in
  `/private/tmp/maccompanion-feature-tests.Yk4HLp/report.json` (910.204 s),
  followed by the separate pairing reliability gate.
- Day 1 of the source-bound daily soak passed for 198.649 seconds and is
  retained in `prephysical-soak-ledger.json` plus its hash-bound report.

The full gate exposed two additional defects before passing. A decoded frame
queued before renewal-fault teardown could arrive after the activation was
terminal and incorrectly surface `invalidPhase`; terminal render receipts are
now inert and a focused package regression covers the race. Xcode 27 could also
wait one minute for system-keyboard animation idleness after every XCUI key
element tap; the semantic test now uses bounded XCTest text transactions while
retaining exact event/scalar/whitespace assertions.

## Claims deliberately not made

No evidence here uses or certifies:

- a physical iPhone, Face ID, Secure Enclave or release client custody;
- the installed Mac app/Agent, production Keychain, final TCC attribution,
  login/logout/user switching, lock/sleep or clean-user lifecycle;
- a user-owned app/window, system audio mutation, LAN/Bonjour, Local Network
  permission, private DNS/Tailscale, or device-specific latency/energy;
- stable Xcode 26.6 distribution compilation, Developer ID/App Store signing,
  notarization, stapling, TestFlight, publication or market acceptance.

Those items remain on the consolidated physical/external checklist. They do
not reopen this completed disposable signed integration boundary.
