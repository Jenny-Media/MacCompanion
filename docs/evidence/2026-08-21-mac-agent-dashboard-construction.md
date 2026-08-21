# Mac Agent administration dashboard evidence — 2026-08-21

## Claim

The bundle-independent Mac menu application now has a coherent, content-free
administration entry surface rather than only disconnected pairing, grant,
audit, recovery, and Interactive-warning views.

`MacAgentDashboardApplicationOwnerV0` owns the local status connection
generation. Each new candidate receives a strictly increasing local token and
retires its predecessor. A validated status may publish only through the exact
current token, with a strictly increasing diagnostic sequence and
non-regressing generation time. Connection loss and application invalidation
publish unavailable and prevent a delayed old reply from restoring stale
facts. This token does not authenticate XPC; final peer verification remains a
separate platform gate.

`MacAgentDashboardProjectionV0` revalidates every snapshot and renders only
closed enabled, lifecycle, listener, route-kind, security, count, and sanitized
warning facts. Loading and unavailable retain no old facts. Ready requires the
Agent, visible menu app, and listener to be ready with nominal storage. Locked
copy permits only the genuine macOS lock surface when supported. No endpoint,
address, path, device name, provider identity, arbitrary message, or remote
content can enter the projection.

`MacAgentDashboardViewV0` is a first-party macOS SwiftUI shell. It emits only
typed enable, disable, retry, pairing, device-administration, activity-history,
and diagnostics intents. Pairing is disabled unless the whole local readiness
boundary is satisfied and the one-device MVP slot is empty. The view does not
own IPC or treat an emitted intent as completion.

## Automated evidence

Fourteen focused tests prove:

- loading/unavailable never retain or invent Agent facts;
- disabled, starting, ready, locked, paired, and degraded projections have
  distinct truthful actions and copy;
- all closed sanitized warning codes receive host-authored presentation;
- malformed decoded snapshots fail before presentation;
- current status admits equal wall time only with a strictly newer sequence;
- sequence replay and wall-time regression preserve the prior value;
- replacement connections fence every old reply; and
- connection/application invalidation cannot be resurrected by late status.

The final hardened unsigned gate passed with 63 indexed JSON fixtures, 773
repository files, 34 historical blob paths, 14 repository-material fixtures, 4
manifests, 12 dependency fixtures, 3 privacy manifests, 12 privacy fixtures, 9
required-reason source records, 10 SBOM fixtures, 16 release-evidence fixtures,
1,052 listed Swift tests, both platform cross-compiles including the macOS
SwiftUI target, and all three construction probes. Only the expected read-only
user SwiftPM cache warnings appeared.

## Deliberate limits

This is identity-neutral application state and UI construction. It does not
create permanent app targets, authenticate an XPC audit token or code
requirement, register login services, request TCC permissions, or execute a
lifecycle/pairing/device/audit/diagnostics command. Those effects remain behind
the final-identity signed adapter and physical clean-user matrices.
