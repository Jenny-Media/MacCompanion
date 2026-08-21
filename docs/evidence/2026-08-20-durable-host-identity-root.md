# Durable host-identity release-root evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

The public Agent bootstrap no longer accepts a caller-authored host UUID. It
reads the singleton `StoredHostIdentityRecord` from its exact private
`SQLiteSecurityStore` and constructs no service root unless that record exists
in `ready` state.

The resulting `AgentPrimaryServicesV1` retains that complete identity binding:
host UUID, 32-byte SPKI fingerprint, and certificate DER. The public
listener/pairing factory compares both public TLS identity fields to the exact
retained record before it constructs or consumes the one-use listener
configuration. A missing, recovery-fenced, different-key, or different-
certificate identity therefore creates no listener, pairing context, QR
authority, or primary ingress.

The package-only lower construction seam accepts a complete ready stored
identity for focused tests. It cannot represent a release service root with
only a free UUID.

## Verification

Two new focused tests prove that:

- public bootstrap rejects both absent and recovery-fenced durable identity;
- a ready record supplies the exact root host UUID;
- a listener configuration with another key/certificate is rejected with the
  closed `hostIdentityMismatch` result; and
- mismatch rejection happens before listener construction, so no partial
  product graph is returned.

The complete public validation gate passed with:

- 60 indexed protocol/product fixtures;
- 666 repository files, 34 historical paths, and 14 repository-material
  fixtures;
- 4 package manifests and 12 dependency-policy fixtures;
- 3 privacy manifests, 12 privacy fixtures, and 6 required-reason API records;
- 10 source-SBOM and 16 release-evidence fixtures;
- 898 Swift tests, including 165 `CompanionAgent` tests;
- all iOS Simulator client-platform/client-UI and macOS local-authority compile
  gates; and
- all three no-prompt/no-network platform probes.

Only expected read-only SwiftPM user-cache warnings were emitted.

## Boundary not claimed

This composition proof does not create or retrieve the private key on a signed
Mac, validate a live Network.framework callback, run a listener, or prove
certificate renewal/recovery on a release identity. Those remain stable-Xcode,
final-identity, signing, and physical-device gates.
