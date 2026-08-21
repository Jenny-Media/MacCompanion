# Required Agent audit composition evidence

Date: 2026-08-20

## Claim

`AgentRequiredAuditCompositionV0` is an identity-neutral construction root that
cannot create operation execution without a concrete
`BoundedOperationAuditWriterV0`. It also creates the lifecycle and primary
session, pairing, Interactive, local-stop, and registry-publication writers from
the same separately bounded detailed-audit store. Lower-level optional injection
remains available for narrow package tests, but the eventual Agent target has a
single explicit production-style path to the required authorities.

The producer set now also distinguishes a recorded best-effort row from the
store's durable rate/quota drop results. A drop preserves the primary pairing,
operation, Interactive runtime, lifecycle, teardown, or completed registry
publication result and its gap
counter, while degrading audit health for local repair.

## Evidence

- The composition initializer requires both the security database and detailed
  audit database and exposes no unaudited operation-execution product.
- One composition test constructs all non-optional writers and operation
  execution from the shared bounded store.
- One health test names only the degraded producer and maps it to the existing
  content-free local status warning without changing security posture.
- Five producer tests force durable rate drops and prove degraded health while
  preserving pairing commit, successful operation, installed Interactive
  runtime, completed local teardown, and completed registry swap respectively.
- The current full validation gate passed with 54 indexed fixtures and 652 Swift tests,
  both UI compile gates, all three no-prompt/no-network probes, and
  `git diff --check`.

## Boundary not claimed

The permanent signed Agent target does not yet exist because final bundle
identity, stable Xcode, and signing custody remain external gates. That target
must instantiate this root, bind lifecycle observation after safety/recovery
effects, and expose degraded health through authenticated local IPC. This
construction does not claim physical process, disk-full, or XPC evidence.
