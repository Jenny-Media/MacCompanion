# Native menu app privacy attribution

Date: 2026-09-27. Measured development process ownership; permanent integration remains open.

## Why earlier playback was insufficient

A historical `log show` query returned no retained attribution records. Fresh bounded `log stream --level debug` observations during the signed native host lane showed Sunshine's requests attributed to `com.openai.codex` when the menu was started as a command-line child. The native run passed, but those results did not prove the menu app's own Screen Recording authority. The retained CLI trace does not contain its actual ScreenCapture decision records; it proves responsibility, not a specific grant decision.

The native probe now accepts `--native-host-package` and verifies the package before and after execution. Its report hashes the actual packaged host, packaged supervisor and source-built TLS libraries rather than the historical reference host/Homebrew inputs. Native enrollment, authenticated launch, two lease renewals, Stop and Observe pass through this package.

## Three observed arrangements

| Arrangement | Sunshine's responsible identity in TCC trace | ScreenCapture observations for the menu | Native outcome |
| --- | --- | --- | --- |
| Signed command-line menu started by Codex | Codex | No retained service decision records | Launch/renewal/Stop passed; not menu permission evidence |
| Signed app launched by LaunchServices, Developer ID requirement | MacCompanion | Three unmatched existing requirements and three unknown decisions | Native HTTPS launch did not pass; cleanup passed |
| Signed app launched by LaunchServices, installed development requirement | MacCompanion | Eleven allowed records, no unmatched or unknown decisions | Launch/renewal/Stop and cleanup passed |

The installed app uses an Apple Development designated requirement. Reusing only its signing identifier under a Developer ID requirement was insufficient. The matching probe verifies the existing app's signature, reads its exact requirement, signs the disposable app accordingly and checks exact requirement equality. It rechecks the installed executable, requirement and strict signature after the run. The installed app is never rewritten; privacy settings are not reset or changed by the probe.

The temporary app wraps the existing signed test menu, retains the permanent menu identity already admitted by the repository, and starts via macOS LaunchServices. It introduces no permanent target identifier, Keychain group or SMAppService registration. Parent/lease/capture and authenticated enrollment checks remain the existing ones. No new wire or authentication semantics are introduced.

## Source-bound evidence

- Three-lane public-fact summary: `/private/tmp/maccompanion-native-tcc-attribution-20260927/attribution-summary.json`, SHA-256 `a051580cc38afb25a023398ac709bf282094e58d4b8ead9895fe2762e4bc3f62`.
- CLI lane: `/private/tmp/maccompanion-agent-xpc-evidence.xckl59pc/native-report.json`.
- Different-requirement app lane: `/private/tmp/maccompanion-agent-xpc-evidence.f2g192hg/native-report.json` (failed, retained).
- Matching app with live TCC trace: `/private/tmp/maccompanion-agent-xpc-evidence.rp2x_h_g/native-report.json`.
- Final matching-app runner: `/private/tmp/maccompanion-agent-xpc-evidence.rqxdcs21/native-report.json`, SHA-256 `35216d38a335cc711e57ad0fe2c80e84432e9b636e265eda2821244259e61987`; all four bounded cases and cleanup passed.
- Final runner SHA-256: `9e341e63473cac33bbd85bd0daf29cc68c2eda16e12b714a7a1658781bda2ba3`.
- Native source-input SHA-256 remains `7c73601ea632c247fdf7b0a34f876584a0603887bf481ed91096bbe8d65de5e4`; native client artifacts were not changed.
- Installed designated-requirement output SHA-256: `a77d9642e988cfa93a8e5a81684a565dbf5330eade2bc87c15d0d366ffcc308b`.
- Portable host manifest SHA-256: `57c2da8f82672ff585f2c541a5f21414c9e7c618ccd32632ee311bb633ed0056`; actual executed host SHA-256 `6affffcac3feffcb9009dfb3cbe2a90d285c7b0966a495b8855badace55cce2b`.
- Invalid reference was rejected before process construction; empty case list and owned-state cleanup passed at `/private/tmp/maccompanion-agent-xpc-evidence.9c2dl9xg/native-report.json`.

Raw permission diagnostics and signer details remain outside the repository. All diagnostic streams were stopped. The normalized summary retains identities/counts and evidence hashes rather than certificates, private signer details, credentials or input. The final matching runner repeats the same app arrangement after tightening reference-validation cleanup; its explicit execution/source hashes are separate from the earlier live trace.

## Development process decision and remaining scope

[ADR-0003](../adr/0003-managed-native-video-process.md) now records the measured arrangement: the normal visible menu app owns a finite subordinate host, launched under its intended signing requirement; the Agent does not become a capture owner. Code identity and macOS responsibility are checked independently.

The probe still uses disposable test custody/local consent, generated bootstrap and a test menu implementation. This is not native playback in the installed normal app or physical iPhone. No real input is posted. Permanent source/dependency/signature/privacy inventories, normal Mac/iOS factory selection, installed lifecycle, LAN, actual input and physical acceptance remain open. The traces also include audio/microphone policy queries during upstream startup; audio-stream acceptance and the final privacy inventory are not claimed.

Stable repository handoff validation is recorded in `/private/tmp/maccompanion-native-tcc-attribution-handoff-validation.log` after the final runner and documents. Release admission remains false.
