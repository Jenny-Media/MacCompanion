# Client reconnect security composition evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

The public configured-reconnect runtime no longer accepts a preconstructed
authentication signer, nonce generator, message-ID generator, or pinned-leaf
trust evaluator. It accepts the client key-custody boundary and platform
timing/queue seams.

For every immutable `ClientReconnectConfigurationV1`, the composition now:

- reads client, host, device, fingerprint, and routes from the same durable
  paired-host/configured-route snapshot;
- constructs `ClientCustodiedSessionSignerV0` from that record's exact opaque
  session-key reference;
- provides no reconnect path to the approval-key reference;
- creates 32-byte nonces with `SecRandomCopyBytes` and fresh message UUIDs;
- installs the strict single-leaf Security.framework evaluator using the same
  runtime wall clock; and
- keeps raw session, route-attempt, signer, randomness, and evaluator
  construction package-only.

## Verification

Two focused tests prove exact client/host/device/route projection, exact
session-key-reference custody delegation, approval-key exclusion, 64-byte
signature return fencing, and public system nonce/message-ID construction.

The complete public validation gate passed with:

- 60 indexed protocol/product fixtures;
- 668 repository files, 34 historical paths, and 14 repository-material
  fixtures;
- 4 package manifests and 12 dependency-policy fixtures;
- 3 privacy manifests, 12 privacy fixtures, and 6 required-reason API records;
- 10 source-SBOM and 16 release-evidence fixtures;
- 900 Swift tests, including 30 `CompanionClientNetworkPlatform` tests;
- all iOS Simulator client-platform/client-UI and macOS local-authority compile
  gates; and
- all three no-prompt/no-network platform probes.

Only expected read-only SwiftPM user-cache warnings were emitted.

## Boundary not claimed

The custody implementation remains final-access-group dependent. This evidence
does not exercise a physical Keychain/Secure Enclave session key, a live
`SecTrust` callback, a network route, background radio behavior, or a signed
iOS target.
