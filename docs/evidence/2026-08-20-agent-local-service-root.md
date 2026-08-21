# Agent local-service root evidence — 2026-08-20

Status: bundle-independent construction and test evidence under Xcode 27 beta.
This is not authenticated XPC, final signing, a concrete route classifier, or
physical process-lifecycle evidence.

`AgentRequiredAuditCompositionV0.bootstrapPrimaryServices` now constructs and
returns one `AgentLocalServiceRootV1` after provider validation and durable
operation restart reconciliation. The composition requires the same security
store, detailed audit store, and emergency deny latch used by product
authorities. No local reader or source publisher is returned on provider,
reconciliation, or bounded-inventory failure.

Before issuing a reader, the root initializes one coherent status actor and
projects emergency-latch posture, current detailed-audit health, active
non-revoked paired-device count, and live-provider count. Listener and route
sources begin stopped. Storage/corruption failure remains locally diagnosable:
the root returns a closed sorted degradation report plus
`storageUnavailable`; an out-of-bounds count returns no root.

The raw status initializer, mutations, and snapshot are package-only. Product
bootstrap exposes an already-authorized reader, a network-only publisher, the
route authority, inventory refresh, security refresh, and narrow transient
stop. Lifecycle and audit facets stay package-owned by their coordinators. The
old optional raw-status injection and post-hoc audit-warning reconstruction
were removed.

Three root tests prove complete initial projection before the first reader,
readable and content-free multi-source degradation, no root on bounded
invariant failure, six concurrent source updates without cross-field loss, and
narrow route/listener teardown that preserves durable inventory, security,
lifecycle, audit health, and reads. Existing Agent bootstrap tests now consume
only the returned root and prove valid lifecycle publication and audit-health
refresh.

The public validation gate passed 54 indexed fixtures, all 687 Swift tests
including 74 `CompanionAgent` tests, Network and Mac UI builds, iOS Simulator
client-platform and client-UI builds, all three no-network probe builds, and
`git diff --check`. SwiftPM user-cache warnings are expected in the restricted
environment. Stable Xcode 26.6 and final signed-process/device evidence remain
required for acceptance.
