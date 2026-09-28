# Source-built client OpenSSL dependency

## Change

The extracted Moonlight engine now uses an OpenSSL framework built from the
checksum-pinned official OpenSSL 3.5.8 source release. The source archive checksum
was read from the release asset linked by the official downloads page:
`a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2`.
Upstream lists 3.5 as the supported long-term series:
[official downloads](https://openssl-library.org/source/).

`openssl_build.py` verifies the archive and extracted source files, builds arm64
for iPhone and Simulator using upstream's platform targets, assembles a dynamic
framework for each SDK, and creates the XCFramework consumed by `engine_build.py`.
It preserves the Apache-2.0 license, source archive, build logs and file-bound
provenance. Disposable objects are reclaimed after each successful framework.
Framework reuse requires matching source/builder/toolchain/SDK inputs and hashes.
The existing reference application may still use its older pinned upstream
binary; the extracted MacCompanion engine uses the source-built dependency.

The inventory now requires matching source build provenance and exact OpenSSL
binary identity for both SDK candidates. It retains release admission false and
complete corresponding-source admission false while host/transitive work remains.
Authentication, enrollment vectors, wire behavior and independent grants are unchanged.
No experiment has been linked into a permanent target.

## Build verification

Full `bash scripts/validate.sh` passes on stable Xcode 27.0 with 109 indexed
fixtures, golden vectors and package/platform/policy checks. Both SDK engine builds
and sixteen Simulator component tests also pass. The first engine build exposed the difference between ordinary C
`openssl/...` includes and framework imports; the selected SDK's verified framework
header directory is now explicit in the generated project.

Candidate source input SHA-256:
`3d88c40f461e57dbbe2ac2daae5aa92b15aa396639a3cff2c7e003d76ba1a0e7`.
The refreshed six-framework inventory matches both SDK binaries. The source-built
OpenSSL framework has only its own install name and `/usr/lib/libSystem.B.dylib`
in its dynamic dependency list. It has no Homebrew or downloaded runtime library.

OpenSSL iPhone binary SHA-256:
`7031a11ed0b01ca818b0837fc3a2932d7945bbf25fa559161fe7fb1f49e0a62e`.
OpenSSL Simulator binary SHA-256:
`ff0578ff8b33369c7c767d445b6a250fa8c5c685deab7243963230040f692dfb`.

Private evidence:

- `/private/tmp/maccompanion-source-openssl-build.log`
- `/private/tmp/maccompanion-source-openssl-iphoneos.log`
- `/private/tmp/maccompanion-source-openssl-simulator.log`
- `/private/tmp/maccompanion-source-openssl-validation.log`
- `/private/tmp/maccompanion-source-openssl-handoff-validation.log`
- `/private/tmp/maccompanion-sunshine-moonlight-20260926/source-openssl/`
- `/private/tmp/maccompanion-sunshine-moonlight-20260926/native-video-candidate-inventory.json`

## Live acceptance

The final signed journey passes from
`/private/tmp/maccompanion-agent-xpc-evidence.zi1exud1`: one test, zero failures,
four native video sessions, keyboard/modifiers/shortcuts/pointer delivery,
background revocation, route-loss recovery, Stop/restart and fresh Observe.
Cleanup is verified. The report binds the SDK source hash above and combined
source/helper/harness SHA-256 `cc0144cfa14a9b728aabfa706fcd253977f12a30cd699a47dd645c59aa20fdf4`.
Elapsed runner time is 240.304 seconds. The final full stable validation also
passes after the pairing diagnostic changes.

An initial attempt failed while signing the temporary menu helper under severe
disk pressure; a second completed signing but timed out during pre-native pairing.
The client TLS handshake completed in that failed trial. Payload-free pairing
stage markers and phase/saved-count diagnostics were added; the final run completes
every pairing stage and the full journey. The earlier pairing failure's cause
remains unverified; this checkpoint does not claim a pairing reliability repair.

Completed historical debug products were compressed into recoverable archives;
every regular file was checked against the archive before its original generated
product directory was removed. Logs, reports and result bundles remain unchanged.
Compiler caches were reclaimed only for completed runs. No installed app was modified.

Additional private evidence:

- `/private/tmp/maccompanion-source-openssl-live-simulator-diagnostic.log`
- `/private/tmp/maccompanion-agent-xpc-evidence.zi1exud1/signed-simulator-report.json`
- `/private/tmp/maccompanion-source-openssl-pair-diagnostic.log`

## Remaining work

Live acceptance uses a synthetic final host input sink and loopback networking.
The Mac host still links six external Homebrew dylibs. Host/transitive source and
build provenance, portable packaging, permanent process/signature/capture/TCC
admission, normal installed-app composition and signed physical installation
remain incomplete. Synthetic input evidence does not prove actual CGEvent posting
or physical iPhone behavior. Native App/Window capture and visible-area bitrate
remain pending.
