# Prepared Agent product bootstrap evidence

Date: 2026-08-21

## Scope

The ready-path Agent bootstrap is now split at the local authorization
boundary. `AgentNetworkPrimaryStartupFactoryV1` performs durable host-identity
startup, exact TLS identity construction, provider publication, revocation and
operation restart reconciliation, and primary/local-service construction. It
returns a one-use `AgentPreparedPrimaryStartupV1` without constructing a
listener, pairing authority, QR context, lifecycle observation root, XPC
server, or visible review delivery.

The existing V0 network startup delegates to this preparation and immediately
consumes it with its compatibility caller-supplied authorized surface. This
preserves existing behavior while giving the release product a safe ordering:
authenticate a menu generation locally before authorizing and consuming the
surface that creates pairing and remote ingress.

## Top-layer ownership

`CompanionAgentProductPlatform` is a separate SwiftPM product above
`CompanionAgentPlatform` and `CompanionAgentNetworkPlatform`. This avoids
pulling remote/network/native-provider authority into the menu-linked platform
module and avoids pulling storage, local XPC, and `SMAppService` concerns into
the network layer.

`MacAgentProductBootstrapV1` constructs one inert
`MacAgentPreparedProductV1` only from:

- one retained `MacAgentReleaseStorageV1` and its exact required-audit root;
- one exact TLS-bound, startup-reconciled prepared primary root; and
- one local-XPC lifecycle/status product built from those same primary
  services.

The ready product exposes only its host ID, diagnostic storage paths, a closed
snapshot, and idempotent terminal `finish()`. Raw stores, the TLS
configuration, primary services, listener construction, and pairing-review
surfaces do not cross the public boundary. Finish retires the unstarted XPC
product and permanently discards the one-use preparation.

## Fail-closed outcomes

First-unlock waiting, required local recovery, and recovery fencing propagate
without loading providers or constructing local XPC, lifecycle readiness,
pairing, or remote ingress. Failure while constructing local XPC permanently
consumes the prepared primary root and publishes no partial top-level product.
Host recovery still requires a separate recovery-only authenticated XPC
profile and a fresh full bootstrap after completion.

The lifecycle state represented as Agent ready remains the existing
service-graph readiness fact. This checkpoint deliberately does not claim that
the XPC listener has started; coordinated start, rollback, and process-exit
publication remain part of the runtime-owner gate.

## Permanent-target guard

The product is not linked in `project.yml` or either permanent target. The
permanent-target validator recursively scans both target source trees and now
rejects imports or references to `CompanionAgentProductPlatform`,
`MacAgentProductBootstrapV1`, and `MacAgentPreparedProductV1`. Negative
self-tests inject the wrapper bootstrap symbol into both targets, preventing a
future caller from bypassing the earlier storage-symbol guard.

The permanent Agent therefore remains `.authenticationOnly`, and the menu app
continues to present its truthful `.unavailable` source.

## Verification

Focused verification passed under Xcode 27 beta:

- four network-startup tests cover listener-free one-use preparation, every
  non-ready identity result, V0 delegation, and stale identity rejection; and
- four product-platform tests cover exact root retention, all non-ready
  branches, a suspended concurrent finish barrier, and fail-closed XPC
  construction failure.

The full repository gate passes across 898 repository files, 293 Swift source
files, 1,243 unique package tests with zero duplicate names, 8 platform-probe
tests, 14 privacy source records, all policy validators, and the supported iOS
and macOS cross-builds. An unsigned Xcode 27 beta build of the macOS app and
embedded Agent also completed with `BUILD SUCCEEDED`; its dependency graph did
not include `CompanionAgentProductPlatform`.

## Remaining boundary

This is construction evidence only. The injected verification path and
permanent targets do not invoke the public real-custody factory, start local XPC
or a network listener, register login items, authorize a pairing/recovery
surface, exercise signed peer verification, or prove physical network
behavior. When a future product owner explicitly invokes the public `prepare`,
it intentionally creates the release storage and may inspect or create the
prompt-free Keychain/Secure Enclave host identity. The later authenticated
menu presentation-surface router now provides generation-bound pairing-review
and recovery-only facets without adding XPC presentation messages. Strict
bounded messages, a concrete generation-owned endpoint, and coordinated
activation/rollback remain the next gates before permanent-target integration.
