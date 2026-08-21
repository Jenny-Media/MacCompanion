# Unified Agent network-product startup evidence — 2026-08-20

## Claim

The release-shaped Agent network entry point now accepts one required-audit
root, one host Keychain configuration, and platform/product inputs. It uses the
root's exact private security store and one wall-time sample to:

1. run recoverable host-identity startup;
2. return closed first-unlock, established-key-loss, or recovery-fenced states
   without constructing providers, TLS, pairing, QR, or listener authority;
3. build sealed TLS parameters only from the exact issued identity and durable
   fingerprint;
4. bootstrap the provider publication, restart reconciliation, root-bound
   status, required-audit Interactive authority, authentication, and local
   service graph; and
5. consume the TLS configuration through the existing pairing/listener product
   factory, whose current certificate and fingerprint comparison is the final
   stale/cross-wire fence.

Raw host-startup injection is package/test-only. The public entry point creates
the concrete Security.framework coordinator itself. Failure at any gate starts
no listener.

## Automated evidence

Three focused tests prove:

- a ready durable/issued identity produces one product whose retained primary
  host identity is exact and whose listener service remains unconstructed;
- first-unlock waiting does not call the provider loader and returns no product;
- a startup identity that differs from the root's current durable identity is
  rejected by the final product factory before listener consumption.

The complete unsigned repository gate validates 60 indexed fixtures, 675
repository files, dependency/privacy/SBOM/release policies, 918 Swift tests,
both platform cross-compiles, and three no-network/no-prompt probes.

## Deliberate limits

This is a bundle-independent construction proof. It does not start a listener,
touch the real final-tag Keychain/Secure Enclave, authenticate an XPC peer,
capture/post input, or prove physical network behavior. Permanent targets,
final identity values, signed custody, and physical execution remain external
release gates.
