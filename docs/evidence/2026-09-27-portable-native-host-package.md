# Portable native host development package

## Construction

`scripts/package_native_host.py` constructs a new development bundle without
replacing an existing candidate. It requires the pinned source-built Sunshine
artifact, collects the complete linked non-system library graph from the host
and certificate tool, rejects unresolved locations and colliding library names,
and rewrites references to package-local loader-relative paths. Existing ICU
loader-relative references are resolved before copying. All six runtime dylibs,
OpenSSL CLI and the process supervisor travel inside the package.

The package retains Sunshine and runtime dependency licenses and the installed
Homebrew formula records. It records original artifact hashes, installed formula,
receipt and license hashes, builder/toolchain information, package file hashes
and symlink targets. Escaping symlinks, changed package files, invalid binary
paths, external linked dependencies and changed construction provenance are
rejected. Nested binaries and the outer app receive ad-hoc development signatures;
strict signature verification follows. Non-code OpenSSL configuration belongs
under Resources, rather than Helpers, to satisfy nested-code signing layout.

The CLI smoke lane uses a package-owned empty OpenSSL configuration and refuses
external provider module lookup. Temporary certificate/key material is cleaned
with its owned temporary directory. It is never a repository artifact.

## Verified package

Final package: `/private/tmp/maccompanion-portable-host-20260927-v4`.
There are nine packaged Mach-O files: Sunshine, the supervisor, OpenSSL CLI,
libssl, libcrypto, miniupnpc and three ICU libraries. Every linked dependency is
an Apple system library or resolves to a file inside the bundle. Host startup and
certificate generation/self-signature verification pass. A separate disposable
copy relocated into a path containing spaces passes the same probes; altering a
copied library makes package verification fail. The initial tamper probe needed
owner write permission on its disposable copy; the final probe includes that step.

Original source-built host SHA-256:
`c48a6824dea93f0157bc1bcbd3819201da671610895a2c5c7885173c9044582d`.
Relocated/signed host SHA-256:
`2a392832563f0b8df50a7f29a2a03d73f468fe943078469fc3e85b413030618e`.
Package manifest SHA-256:
`1085d684218d8faa695360465af07990c99161948f0b3af72f042420b1f10d01`.

## Live composition

The Debug-only native probe can explicitly select a verified host package. It
uses that package's host, supervisor and certificate CLI; OpenSSL configuration
and provider lookup stay package-owned. Original permission, deadline, process,
capture/sample and presentation fences remain intact. No normal permanent target
or default application composition is changed. Wire/security semantics, independent
grants and cryptographic vectors are unchanged.

The signed Simulator runner checks the package before launch and again after
acceptance, binds its exact manifest hash, and reports portable host verification
only after the entire journey succeeds.

Final live evidence root:
`/private/tmp/maccompanion-agent-xpc-evidence.9fzf7zfc`.
One test passes with zero failures: four visible native sessions, keyboard,
modifiers, shortcuts and pointer delivery, background revocation, route-loss
recovery, Stop/restart and fresh Observe. Cleanup and portable host verification
are true. Elapsed runner time is 254.463 seconds.
Combined source/helper/harness SHA-256:
`1ce1cf6449a1e98a4992b4a0372744e41627931e0d7d9ab57f635b27060397fe`.
Client SDK candidate source input SHA-256 remains
`3d88c40f461e57dbbe2ac2daae5aa92b15aa396639a3cff2c7e003d76ba1a0e7`; the extracted engine and source-built
client OpenSSL are unchanged by this host packaging/probe work.

Private evidence:

- `/private/tmp/maccompanion-portable-host-build-v4.log`
- `/private/tmp/maccompanion-portable-host-20260927-v4/host-package.json`
- `/private/tmp/maccompanion-portable-host-live-simulator.log`
- `/private/tmp/maccompanion-agent-xpc-evidence.9fzf7zfc/signed-simulator-report.json`
- `/private/tmp/maccompanion-portable-host-validation.log`

Stable Xcode 27.0 full `bash scripts/validate.sh` passes after the packaging and
probe integration changes, including all 109 indexed fixtures, golden crypto
vectors, package/platform checks and repository policy validation.

## Remaining work

This establishes linked-library portability and the isolated live composition,
not release admission. Host/transitive corresponding source and reproducible
build provenance remain incomplete: the package carries existing Homebrew
runtime binaries with retained formula/license records. Ad-hoc signatures do not
establish permanent process identity or TCC attribution. The live journey remains
loopback-only with a synthetic final host input sink. Actual system input, LAN,
normal-app composition and Mac/iPhone installation need their own verification.
Native focused App/Window capture and visible-area bitrate remain pending.
