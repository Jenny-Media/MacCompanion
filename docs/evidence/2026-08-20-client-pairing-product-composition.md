# Client pairing product composition evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

The public iOS pairing path is now
`NetworkClientPairingApplicationCompositionV0.makeOwner`. It accepts only the
stable client ID, client key custody, atomic paired-host persistence, platform
queues, and a presentation callback.

The factory constructs:

- the application-global pairing owner with system wall/monotonic time,
  random bytes, and message UUIDs;
- the immutable-pin route-racing Network.framework connection factory;
- the strict single-leaf Security.framework evaluator using the connection
  factory's same wall clock; and
- one owner that retains the exact returned connection across TCP, TLS,
  framing, completion, and close.

Generic connection factories and application-owner clock/randomness injection
are package-only. Trust-evaluator and route-attempter injection remain package
or module-internal test seams. A release application cannot construct the
pairing owner around fabricated TLS evidence through public API.

## Verification

The new product-composition test proves that construction starts in the
closed `scanning` presentation state and performs no network work. Existing
pairing-owner, route-racing, pinned-leaf, framing, deadline, cancellation, and
durable-publication tests continue through the same underlying authorities.

The complete public validation gate passed with:

- 60 indexed protocol/product fixtures;
- 670 repository files, 34 historical paths, and 14 repository-material
  fixtures;
- 4 package manifests and 12 dependency-policy fixtures;
- 3 privacy manifests, 12 privacy fixtures, and 6 required-reason API records;
- 10 source-SBOM and 16 release-evidence fixtures;
- 901 Swift tests, including 31 `CompanionClientNetworkPlatform` tests;
- all iOS Simulator client-platform/client-UI and macOS local-authority compile
  gates; and
- all three no-prompt/no-network platform probes.

Only expected read-only SwiftPM user-cache warnings were emitted.

## Boundary not claimed

This proof does not access physical client keys, scan a camera code, execute a
live pinned TLS callback, race real LAN/private routes, or publish a signed iOS
record. Final access groups, Data Protection/backup configuration, radio and
background behavior, and physical-device pairing remain release gates.
