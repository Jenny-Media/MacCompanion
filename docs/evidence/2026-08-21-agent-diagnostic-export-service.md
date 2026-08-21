# Agent sanitized diagnostic export evidence — 2026-08-21

## Claim

The dashboard and diagnostic CLI now have a real bundle-independent Agent
source for `exportDiagnostics`, rather than only payload models and UI/CLI
intents.

`AgentSanitizedDiagnosticsAuthorityV1` owns one boot-scoped, in-memory ring of
the newest 256 events. It assigns every sequence itself, records only closed
component, severity, and code values with a validated safe-integer time, and
uses occurrence count one. Invalid time and sequence exhaustion fail before
mutation. The write-only publisher facet cannot read history, choose a
sequence, add arbitrary detail, or change retention.

`AgentLocalDiagnosticExportServiceV1` receives the existing coherent local
status reader and the ring's read facet. It constructs and revalidates one
`LocalDiagnosticExport`; any status, event, or construction failure maps to the
single closed `sourceUnavailable` error and emits no partial payload. The Agent
local-service root constructs and shares these exact capabilities.

The closed local-IPC matrix now permits `exportDiagnostics` from both the menu
app and diagnostic CLI to the Agent. The service itself receives no caller
role, audit token, endpoint string, or authorization flag. A final signed XPC
adapter must authenticate the peer and authorize the exact method before
receiving the capability.

## Automated evidence

Nine focused tests prove:

- strict event sequencing and content-free construction;
- newest-256 retention and oldest-first eviction;
- invalid-time and sequence-exhaustion failure without mutation;
- exact validated status/event export and omission assertions;
- closed mapping of status and event-source failures;
- root-issued publisher/exporter composition; and
- the exact menu-app and CLI authorization matrix plus safe-integer time
  rejection at the shared payload boundary.

The final hardened unsigned gate passed with 63 indexed JSON fixtures, 775
repository files, 34 historical blob paths, 14 repository-material fixtures, 4
manifests, 12 dependency fixtures, 3 privacy manifests, 12 privacy fixtures, 9
required-reason source records, 10 SBOM fixtures, 16 release-evidence fixtures,
1,061 listed Swift tests, both platform cross-compiles including the macOS
SwiftUI target, and all three construction probes. Only the expected read-only
user SwiftPM cache warnings appeared.

## Deliberate limits

This ring is not durable security audit history, a crash report, telemetry, or
an upload channel. It starts empty on each Agent launch and no code in this
slice writes an export to disk. A user-selected menu/CLI save path, final signed
peer authentication, target wiring, and physical clean-user evidence remain
separate gates.
