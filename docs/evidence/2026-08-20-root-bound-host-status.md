# Root-bound Observe status evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

The public release-Agent bootstrap no longer accepts a preconstructed status
provider. It accepts only platform measurement seams: a sampler, clock,
initial generation, and bounded freshness interval.

`AgentRootBoundHostStatusProviderV1` constructs `HostStatusAuthority` with:

- the exact host ID supplied to the release composition root;
- the root's same private `SQLiteSecurityStore` sequence committer;
- the supplied platform sampler and monotonic clock; and
- a source-owned generation and bounded freshness interval.

Construction is lazy. If provider loading, registry validation, startup
reconciliation, or another earlier bootstrap gate fails, status composition
does not create or advance durable sequence state.

Raw status-provider injection remains package-only for tests. External release
targets cannot substitute another host identity or independent revision store
through the public Agent root.

## Verification

The focused composition tests prove that the public root accepts platform
status and Interactive seams, and that the status authority:

- creates no sequence row before the first successful read;
- returns the exact root host ID and configured generation;
- starts at revision zero and advances monotonically;
- persists the next revision in the root security store; and
- preserves the requested closed host state and freshness bound.

The complete public validation gate passed with:

- 60 indexed protocol/product fixtures;
- 665 repository files, 34 historical paths, and 14 repository-material
  fixtures;
- 4 package manifests and 12 dependency-policy fixtures;
- 3 privacy manifests, 12 privacy fixtures, and 6 required-reason API records;
- 10 source-SBOM and 16 release-evidence fixtures;
- 896 Swift tests, including 163 `CompanionAgent` tests;
- all iOS Simulator client-platform/client-UI and macOS local-authority compile
  gates; and
- all three no-prompt/no-network platform probes.

Only expected read-only SwiftPM user-cache warnings were emitted.

## Boundary not claimed

This evidence does not instantiate a signed Agent target, exercise live system
sampling on a physical release identity, prove authenticated local XPC, or
complete a physical paired exchange. Those remain final-identity and
release-environment gates.
