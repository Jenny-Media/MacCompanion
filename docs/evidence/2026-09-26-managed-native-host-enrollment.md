# Managed native host enrollment checkpoint

Date: 2026-09-26. This advances enrollment and host startup. It is not normal-app
engine replacement, a signed installation, or physical-device acceptance.

## Implemented

- A production local host coordinator reserves one preparation/proof operation,
  hashes complete certificate DER itself, consumes one challenge, and checks
  exact current primary/Control/surface/session-key authority after every await.
  Stop, invalid proof, expiry, replacement, and late startup results retire it.
- Public preparation material carries the actual host DER and bounded challenge
  fields. The private verifier remains on the host.
- A production client attestation owner reconstructs the normative signing input
  from trusted local session/surface facts and exact client/host DER. It validates
  certificates through an injected platform validator and uses the existing
  session-key custody seam. It rejects changed material before custody, checks
  the returned signature, and discards late signing results after Stop,
  revocation, clock rollback, or its signing budget expires. No approval key is used.
- The experimental Mac backend validates canonical self-signed client DER,
  prepares private native credentials, and registers only the attested client in
  isolated Sunshine state after proof. It selects the supplied approved Desktop
  display explicitly, disables upstream input/audio/UPnP, and launches under the
  original finite Control deadline and parent-death supervisor.
- Readiness checks the exact prepared server certificate. A busy port cannot
  impersonate the new operation. Backend health loss retires the coordinator.
  Retirement joins one drain and removes only its owned credentials after exit.

The normative local enrollment profile and independently constructed golden
coordinator vector were updated before implementation. The sole fixture manifest
now indexes 94 JSON fixtures. The added public byte samples are deliberately not
certificates; only fake test backends accept them. No real certificate or key is
stored in the repository.

## Verified

Selected stable Xcode: `/Applications/Xcode.app/Contents/Developer`, Xcode 27.0.

Focused package coverage passed: 3 signing-vector tests, 4 single-use challenge
checks, 10 host coordinator tests, and 4 client attestation tests (21 total).
Full `bash scripts/validate.sh` exited 0 on the selected stable toolchain, and
`git diff --check` passed. Simulator and iPhone SDK native components rebuilt
successfully. Their inventory includes Engine, Adapter, and OpenSSL for each SDK
and matches the same source-input hash below. They remain unsigned components;
no new normal-app playback or installation acceptance is inferred.

The actual backend probe passed with both production enrollment owners, generated
private native certificates, a temporary session signer, and synthetic Control
facts. It verifies proof-before-registration, successful enrolled-client HTTPS
access, rejection of another certificate, occupied-port rejection, malformed
certificate rejection, invalid-proof rejection, revocation, and private-state
cleanup. It does not request a streamed frame or send input.

Reproduce with:

```
python3 Experiments/SunshineMoonlightIntegration/test_managed_host.py \
  --root /private/tmp/maccompanion-sunshine-moonlight-20260926
swift test --package-path Packages/MacCompanionKit \
  --filter 'NativeVideo(Enrollment|Attestation)'
bash scripts/validate.sh
```

The disposable package manifest and build are generated outside the repository;
no admitted package or dependency-policy exception was added. Fixed diagnostic
reports remain outside Git. Source-bound probe report:
`/private/tmp/maccompanion-sunshine-moonlight-20260926/managed-host-probe-report.json`.

Probe source-input SHA-256:
`46b0e95cffed3db02cd9a3bb0963a0ec224608e1cc08d60150a55a33d1db3ec0`.
Sunshine executable SHA-256:
`e03e5015c9fd1c8f70c5d0c4078cb2e4f8516cc4c928276c78d14e0c8fa19dcf`.
OpenSSL executable SHA-256:
`103fc7706cf6646f226d96f29242d81890363499afc730e7ef1fadd64b3a123c`.
Probe executable SHA-256:
`8af4d847f786a0b6b7a96482eaa9e4b0101d47d75c0fc6ff47d52635618add5d`.

## Remaining normal-app integration

1. Admit indexed authenticated primary request/challenge/proof/ready records and
   implement correlation, cancellation, and session-close dispatch on both ends.
   Obtain the exact registered session key from durable authenticated admission
   and the acknowledged Desktop/display/deadline from the current runtime owner.
2. Build the native client credential/TLS/HTTPS launch adapter with certificate
   possession and exact host pinning, then compose it with the normal UIKit owner.
   The current real probe uses local certificate files and temporary custody.
3. Admit presentation receipts before enabling the existing authenticated input
   path. Native first-frame callbacks still cannot authorize input. App/window
   capture replacement needs a separate exact capture profile.
4. Complete corresponding-source/dependency, process/TCC, signing, and packaging
   gates. The current host backend and Homebrew OpenSSL tool are experimental,
   loopback-only, and not linked into release targets. The upstream management
   listener remains local in this probe and needs a restricted product profile.
5. Verify the normal Simulator Control journey, then install signed candidates
   and test on the connected, unlocked phone.

Final cleanup check found zero owned probe processes and zero private probe
directories. The user's installed Sunshine service/configuration and physical phone were not
changed. No commit, push, publication, or release was performed.
