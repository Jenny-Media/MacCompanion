# Interactive Control product composition evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

The public `AgentRequiredAuditCompositionV0.bootstrapPrimaryServices` release
path no longer accepts an already constructed Interactive dispatcher. It
accepts `AgentInteractivePlatformServicesV1`, whose inputs are limited to the
authenticated visible-menu-app snapshot source, cryptographic material
generator, runtime owner, and optional surface executor.

The composition constructs `SQLiteInteractiveSessionAdmissionReaderV0` from
the exact private `SQLiteSecurityStore` already used for application
authentication, pairing, grants, operations, and audit-self. It also installs
the composition's non-optional `BoundedInteractiveAuditWriterV0`. Raw
Interactive dispatcher, raw authenticated primary-session, alternate complete
dispatcher bootstrap, and store-bound admission constructors are package-only
test seams, so an external app target cannot substitute another durable
admission authority or omit required Interactive approval audit.

The durable-plus-visible admission implementation now lives with the
bundle-independent Interactive host contract. `CompanionHostPlatform`
re-exports it for source compatibility while the Agent can construct it
without depending on platform-effect adapters.

The later initial-runtime slice retains both the exact signature-bound
approval effects and the stable visible-menu generation/revision instead of
discarding them; see [initial runtime preparation](2026-08-20-initial-runtime-preparation.md).

## Verification

Twenty-two focused tests cover the public product bootstrap, stable/torn
durable-plus-visible admission joins, required approval audit, runtime
installation, concurrent teardown, and disconnect compensation. The complete
public validation gate passed with:

- 60 indexed protocol/product fixtures;
- 659 repository files, 34 historical paths, and 14 repository-material
  fixtures;
- 4 package manifests and 12 dependency-policy fixtures;
- 3 privacy manifests, 12 privacy fixtures, and 6 required-reason API records;
- 10 source-SBOM and 16 release-evidence fixtures;
- 891 Swift tests, including 158 `CompanionAgent` tests;
- iOS Simulator client-platform/client-UI and macOS local-authority compile
  gates; and
- three no-prompt/no-network platform probes.

Only expected read-only SwiftPM user-cache warnings were emitted.

## Boundary not claimed

`InteractiveSessionRuntimeOwningV0` remains a platform seam because atomic
authenticated-XPC installation and the final durable/visible revalidation are
not yet implemented in a signed target. This composition prevents preflight
store and required-audit drift; it does not claim physical TCC, capture, input,
indicator, post-event verification, or final runtime-store identity evidence.
