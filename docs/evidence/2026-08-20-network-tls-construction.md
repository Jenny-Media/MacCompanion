# Network TLS construction evidence — 2026-08-20

Status: provisional construction evidence under Xcode 27 beta. This is not a live handshake, certificate, pin, route, signing, or release result.

The disposable `Experiments/NetworkTLSProbe` compiled and ran without starting a listener or connection. It constructed `NWProtocolTLS.Options`, fixed the minimum and maximum protocol to TLS 1.3, disabled TLS resumption for the v0 no-early-data baseline, installed a Security-framework verification callback, and compile-checked access to negotiated TLS version, early-data acceptance, and the live `SecTrust` handle.

The standalone probe callback deliberately calls completion with `false` for every peer. The package now also compile-checks a one-shot client callback context that can accept only after its synchronous pinned-leaf evaluator returns an SPKI and the callback independently matches it to the immutable saved pin. The concrete evaluator requires one `SecTrust` leaf and uses a pure bounded DER inspector that reconstructs the exact Mac Companion profile, verifies the self-signature and validity window, and returns only the canonical SPKI. Construction and synthetic `SecTrust` tests pass. A separate host constructor compiles the exact Secure Enclave/Keychain profile and proves certificate-to-`SecIdentity` composition with an ephemeral in-memory key. `CompanionNetworkPlatform` then strictly reinspects that identity's current leaf and fingerprint before installing its `sec_identity_t` into sealed TLS 1.3-only, resumption-disabled, no-local-reuse listener parameters. The boundary exposes only a one-shot unstarted listener owner, never the mutable parameters or raw listener. That owner wraps each accepted connection immediately, starts and inspects that exact object, requires negotiated TLS 1.3 with no accepted early data, and transfers it to the public frame-pump constructor through a one-use verified-ready authority. Six host-listener/accepted-connection tests prove construction, exact-object evaluation, unsafe-TLS rejection, missing-metadata separation, one-shot ownership, and terminal teardown without starting a real listener. Final signed custody, physical execution of live accepted-connection metadata extraction, wrong-key/proxy rejection, and crash-safe cross-store recovery remain unproven, so this is not live acceptance evidence.

Command:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift run --disable-sandbox \
  --scratch-path /private/tmp/maccompanion-tls-probe-build \
  --package-path Experiments/NetworkTLSProbe \
  network-tls-probe
```

Reported facts:

```json
{
  "experimentOnly": true,
  "startedNetworkActivity": false,
  "tlsMaximum": "1.3",
  "tlsMinimum": "1.3",
  "tlsResumptionEnabled": false,
  "verifyBlockAcceptsPeers": false,
  "verifyBlockInstalled": true
}
```

Acceptance still requires a stable Xcode 26.6 build, final signed identities, fixture-conformant live SPKI extraction, pinned-leaf trust, a real client/server handshake, wrong-key and terminating-proxy rejection, and the physical Bonjour/private-IP/private-DNS/user-overlay route matrix.
