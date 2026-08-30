# Isolated Agent startup and signed-XPC checkpoint — 2026-08-28

## Outcome

The new 24-check multi-process integration matrix passed three consecutive
runs. The final source-fingerprinted run completed in 16.982 seconds including
incremental build/signing/cleanup. No installed Mac app, persistent Agent,
physical iPhone, Simulator, privacy setting, or production pairing/Keychain
data was changed. Disposable helper signing used an existing local identity;
no identity was created or exported.

Repository validation passed with **1,742 Swift tests** across its package,
lab, and platform-probe runners, plus policy/fixture/isolation validators and
platform compilation checks. The Agent application module compiled in Release
on the installed Xcode beta. Defined-symbol inspection found 60 matching
isolated-test symbols in Debug and **zero in Release** across the transport,
bootstrap client, startup seam, and startup coordinator objects. This remains
beta-toolchain evidence, not stable-Xcode or distribution certification.

## What is exercised

The production startup coordinator selects the disabled bootstrap or enabled
local service from a disposable atomic intent store. The enabled product
handle and content-free status source are injected. Production XPC server and
clients run in separate signed processes, with the original same-team/exact
identifier requirements and closed handshake. Only the Mach service address
is changed by a UUID-only Debug factory; it cannot select the installed label.

The required matrix covers:

1. First-unlock deferral, preparation failure, invalid initial revision, and
   listener construction validation without fallback.
2. Disabled readiness rejection, exact durable enable receipt, restart-request
   latching, fresh-process enabled intent loading, and rejection of bootstrap
   commands by an enabled service.
3. Repeated status, pre-readiness rejection, duplicate readiness, same-client
   reconnect, and a new menu connection retiring the old generation.
4. Wrong menu identifier, wrong Agent identifier, ad-hoc signer rejected by
   the server, unsupported hello version, and an extra hello field.
5. Repeated source-unavailable replies without losing the connection, status
   timeout with a deliberately late completion that cannot revive the client,
   Agent death while a status read is pending, and fresh-process recovery.
6. Concurrent finish calls, exact job removal, child/Agent process exit, and
   deletion of disposable state and signed helper copies.

Timeouts/nonzero commands are failures, never successful negative-test evidence.
The report also rejects an incomplete/duplicate case set or source changes
during the run. Source guards and two new address/profile tests are included
in `scripts/validate.sh`; signed integration remains an opt-in host lane.

Two initial harness assumptions were corrected before the passing runs: use
POSIX canonical paths for the private temporary-directory guard (Foundation
path normalization was unsuitable here), and respect the existing contract
that explicit client cancellation is silent. No production wire/authentication
behavior was relaxed to make a test pass.

## Reproduce and inspect

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
python3 scripts/verify_agent_xpc.py

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
bash scripts/validate.sh
```

See [the runbook](../../Experiments/LiveControlLab/AGENT-XPC.md) for signing
requirements, isolation guarantees, and exceptional hard-kill cleanup.

Local evidence (not committed artifacts):

- First passing run: `/private/tmp/maccompanion-agent-xpc-evidence.f36j8k6p/report.json`.
- Second passing run: `/private/tmp/maccompanion-agent-xpc-evidence.0xf9_egr/report.json`.
- Final passing run: `/private/tmp/maccompanion-agent-xpc-evidence.jw3zb5an/report.json`.
  It records the UUID label, source fingerprint, all 24 outcomes, elapsed time,
  and verified cleanup. Earlier reports predate the provenance fields.
- Repository validation: `/private/tmp/maccompanion-agent-xpc-validation.log`;
  final rerun: `/private/tmp/maccompanion-agent-xpc-validation-final.log`.
- Release build: `/private/tmp/maccompanion-agent-xpc-release.log`.

Independent post-run inspection also found no final test launchd service, no
remaining disposable helper process, and no final disposable state directory.

## Still not proven

This is startup-coordinator and bootstrap/status-XPC evidence, **not complete
shipping Agent startup**. Host identity/Keychain preparation, the full enabled
Agent composition, durable status-sequence persistence, lease issuance and
admission rereads, menu presentation and Interactive XPC routes, SMAppService
registration, TCC, Secure Enclave/Face ID, and physical LAN/Bonjour remain
separate gaps. No Simulator UI/media suite was rerun for these macOS-only
test seams; its previous 16/16 evidence remains a separate checkpoint.

The next isolated integration slice is the enabled Agent's authenticated menu
presentation and Interactive lease/admission XPC path, still using disposable
state and an owned test window before proposing any physical checkpoint.
