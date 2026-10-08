# Native client TLS, launch adapter and Control startup hook

Started: 2026-09-26; verification completed 2026-09-27. This advances the client adapter and normal UIKit startup seam.
It is not a completed normal-app native video journey or signed installation.

## Implemented

- A disposable OpenSSL adapter creates an ephemeral RSA-2048 self-signed native
  client identity entirely in memory. Its complete public DER is attested through
  the existing primary enrollment/session-signature profile. The private key is
  never exported, persisted, or imported into Keychain.
- Native TLS validates canonical complete DER, current validity, self-signature,
  RSA size and explicit client/server certificate purpose. It connects only to a
  supplied verified-primary IP address and enrolled port base, requires TLS 1.2
  or newer, pins the exact enrolled host leaf, and proves client-key possession.
  There is no HTTP/system-trust fallback, redirect or PIN pairing.
- Requests are serial, limited to the four managed native operations, bounded to
  five seconds and 1 MiB, and interrupted on retirement. Closed response parsing
  rejects unsupported HTTP status/framing, duplicate lengths, oversized bodies,
  XML errors, duplicate fields, DTD/entities and excessive nesting/text.
- The launch adapter owns identity generation, normal Control enrollment through
  existing session-key custody, serverinfo and sole-Desktop lookup, a fresh stream
  key/key ID, fixed bounded geometry/settings, HTTPS launch and exact encrypted
  RTSP route validation. It rechecks Control between transitions and the measured
  primary route after launch. Native playback requests ENCFLG_ALL, with input and
  audio outside this adapter. Retirement joins pending TLS, closes enrollment,
  drains video, releases native keys and clears owned mutable transport material.
- The normal UIKit Desktop product accepts an admitted preparation adapter and
  starts it once after the existing initial Desktop acknowledgement. It disables
  input while preparing, rejects a late prepared result after Stop/surface change,
  and joins adapter cleanup on close. Driver retirement also closes the adapter
  so a video failure cannot retain native enrollment indefinitely.

The local normative launch profile and its indexed admission fixture preceded
implementation. The sole fixture manifest now indexes 101 JSON fixtures. Existing
application-authentication, approval and signing vectors are unchanged. The native
OpenSSL implementation remains under `Experiments/`; permanent targets do not
link it or supply the new UIKit preparation adapter.

## Verified

Selected stable Xcode: `/Applications/Xcode.app/Contents/Developer`, Xcode 27.0.

- Fifteen native engine/owner/launch tests passed on the dedicated Simulator:
  four engine lifecycle checks, eight normal native owner checks, and three new
  identity/XML/encrypted-route checks.
- Eight real loopback TLS cases passed: admitted client, wrong host pin,
  unregistered client, Stop during request, oversized body, mismatched content
  length, expired host certificate, and wrong certificate purpose.
- The actual isolated Sunshine backend accepted the in-memory identity after
  production enrollment attestation and served HTTPS serverinfo and Desktop
  inventory. An unrelated certificate was rejected. Existing busy-port, invalid
  DER/proof, revocation and credential-cleanup checks passed again. This probe
  uses synthetic Control authority; it does not launch or display a stream.
- Normal Control Simulator regression passed all three UI journeys, followed
  by five pairing reliability checks (exit 0). This exercises the existing media
  path with simulated authority, not the complete native launch path. Evidence:
  `/private/tmp/maccompanion-feature-tests.IvmUT0`.
- Simulator and iPhone native frameworks built. All six framework records and
  both real TLS/host probes match the same source-input hash below.
- Full `bash scripts/validate.sh` exited 0 on the selected stable toolchain;
  `git diff --check` passed. The final experimental pin comparison refinement
  was checked with all eight TLS cases, the actual host probe and both SDK builds.
- Validation found an existing asynchronous test race: a test observed primary
  construction beginning before primary activation was published. Its final
  assertion now waits for the actual active state using the existing bounded
  helper. The focused test passed; no production listener behavior changed.

Source-input SHA-256:
`388863fc3972878580bfdfbfedd8896498f3dda506e785088c24580d5850bce6`.
In-memory TLS probe executable SHA-256:
`5f3fa33a2b1733169c4c0f26ae6d2fd7e2fd63aff9e861c4fcb6c0fe54f0a768`.
Managed host probe executable SHA-256:
`8810a542f32e92e2a9f6a8bcc7749b852890888f37f614859edfa62e0d81fa9e`.

Diagnostic reports and private generated test credentials stay outside Git under
`/private/tmp/maccompanion-sunshine-moonlight-20260926`. TLS tests delete their
private directories, and the managed backend removes its credentials after exit.

## Remaining

1. Implement the concrete authenticated Mac runtime snapshot/backend provider,
   joining the acknowledged display/generation/original deadline to managed host
   startup. Seal upstream management/pairing routes before phone-facing use.
2. Admit source-built dependencies, corresponding-source packaging, managed
   process identity and capture/TCC ownership. The current OpenSSL framework is
   still the pinned experimental binary, and the host uses development libraries.
3. Configure the admitted adapter in the normal app composition and prove the
   complete primary enrollment → native TLS launch → decoded frame → Stop flow.
   The new hook still begins after the legacy acknowledged initial Desktop;
   native first-frame replacement and presentation receipts remain unfinished.
4. Preserve presentation/coordinate authority before enabling native video with
   the existing touch, keyboard/modifier and focus input path, then build signed
   Mac/iPhone candidates for installation and device acceptance.

No new normal app was installed. Native input remains disabled, and the normal
apps still do not automatically select this experimental adapter.
