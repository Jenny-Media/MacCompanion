# Production supervisor package — 2026-09-27

## Construction

`scripts/package_production_native_host.py` compiles the promoted production
`Native/Host/companion-supervisor.c` with stable Xcode's compiler and explicit
macOS SDK, C11 warnings-as-errors and macOS 26 deployment target. It constructs
fresh private staging and a new portable host package. It preserves the existing
source-built host, runtime dependencies and historical tested packages.

The supplemental closed `production-supervisor.json` record binds the source,
compiler, SDK version, flags, compiled supervisor, actual signed packaged binary,
packager and host manifest. Verification joins the record to the host's selected
supervisor origin, checks the actual binary's macOS deployment target, and repeats
existing closed file/dependency and strict code-signature checks. This record is
construction evidence for trusted local selection; it does not authenticate itself
or admit an arbitrary package supplied remotely. Normal selection still needs its
protected local artifact authority and signature/dependency admission.

The initial direct compiler invocation lacked an SDK header search path. The final
builder supplies the SDK explicitly. The first development candidate is historical
because the final builder also enforces the exact record schema. The final candidate
is `/private/tmp/maccompanion-production-portable-host-20260927-v2`.

## Bindings

- Production C source SHA256:
  `e7b60e1e4d070a95d525d4c95a558cf4bd61e11bd54ad218c2d850efcc88935d`.
- Final packager SHA256:
  `e7a5e97f77f2deb3a9633bc42280581fc291436facb8621af9ee5a93edc08bf8`.
- Original compiled supervisor SHA256:
  `5bdc3cb7d7f0e7718e36bd8a8a8b2756c2a7d0e9e27a86fc139b7b8d5750456a`.
- Actual signed packaged supervisor SHA256:
  `e09dd43ace9e04d6fa1dbe6dfd642f07cee564be6cb87c2c6bf23e12ef75a483`.
- Host manifest SHA256:
  `ea719c8ec6830a838eb97f66c6b0b661031e4f79ff18ae4a9720a73c952a3e2e`.
- Production supervisor record SHA256:
  `1297714fc20847e316dd2c4e922ef0ecf97ed47a4c24102e03b4ea563e877dc0`.

## Acceptance

Construction, deployment inspection, all nested signatures and the closed ten-binary
host dependency inventory pass. A disposable copy rejects a changed source binding,
a different selected supervisor digest, an unexpected authority field and a modified
packaged supervisor. The original candidate remains valid after these checks.

Signed app-owned native launch, two renewals, Stop/Observe and cleanup pass through
the exact new package. The temporary app uses the installed development requirement;
the installed app and its privacy settings are unchanged.
Report: `/private/tmp/maccompanion-agent-xpc-evidence.2kci5fu2/native-report.json`.
SHA256: `bec60bfaa278d04bdfdfed9af92afd21e909f1c1b32916ef68a4a480e7dacf6e`.

The first Simulator attempt failed during local Agent startup before pairing or native
video. Its report is retained at
`/private/tmp/maccompanion-agent-xpc-evidence.2zl_758w/signed-simulator-report.json`,
with cleanup verified. The signed Mac test had passed concurrently; shared-port live
tests are subsequently run sequentially. The exact cause of the Agent startup
termination is not established by that failed report.

The sequential dedicated Simulator rerun passed one XCTest with four visible native
sessions: direct keyboard, modifiers, shortcuts and pointer; background revocation;
route-loss recovery; explicit restart; Stop/Observe and cleanup. Final input effects
remain synthetic. It selected the same new host manifest and both the host verifier
and production-supervisor verifier pass again after the run. No source patch was
needed for this successful rerun. This establishes sequential acceptance without
proving the cause of the earlier Agent startup failure.

Report: `/private/tmp/maccompanion-agent-xpc-evidence.gjt2vcq0/signed-simulator-report.json`.
SHA256: `4de882f884d7ac742c69870bb3aedbc69949431ed6049134db59795a960c7cb6`.
Simulator: `8FF65ABB-572E-4EE4-9A9F-F61AA302A586` (MacCompanion WebRTC QA, iOS 27.0).
Stable `bash scripts/validate.sh` also passed:
`/private/tmp/maccompanion-production-supervisor-package-validation.log`.

## Remaining

This closes production-supervisor construction, not normal-app activation or release
admission. The foreign source graph and final signed containing-app inventory,
normal Mac/iOS factory selection, installation, actual system input, LAN/physical
acceptance, App/Window capture and visible-area bitrate remain open. Historical
source-delivery snapshots do not automatically describe this new package.
