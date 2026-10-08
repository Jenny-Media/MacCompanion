# Authenticated native runtime snapshot

Date: 2026-09-27. This checkpoint connects the acknowledged Mac menu runtime to
the existing store-bound native composition. It does not start native video in
the normal apps or install a new app.

## Implementation

The normative local native runtime snapshot profile and its authoritative
manifest fixture preceded wire implementation. The sole manifest now indexes
103 JSON fixtures. Existing application-authentication, approval and golden
signature semantics are unchanged.

The menu runtime exposes an atomic projection only for an active acknowledged
Desktop, with an unexpired current lease and original session deadline. It
rejects wrong surface/epoch/session/revisions, unacknowledged configuration,
focus pause and non-Desktop surfaces. The projection contains no physical display
identifier, device name, credential, key, content or pixel. Renewal keeps the
original install generation and original session deadline.

Canonical bounded snapshot request/receipt codecs and the C/Swift local XPC
transport use the existing authenticated generation, endpoint token, authorization
method, single-flight gate and deadlines. Exact correlation/fence validation and
malformed-reply cleanup are preserved through the concrete endpoint and route.
The live Simulator menu wrapper explicitly forwards the new protocol witness.

The concrete Mac route projects opaque acknowledged display/surface/menu facts
into the native runtime provider. It obtains host pin, client ID, primary ID,
epoch and durable revisions from the trusted primary command context. The Agent
runtime binding checks its active primary/session and authenticated menu generation
before and after snapshot/backend suspensions; retired results cannot be used.
Stop, exact menu invalidation and terminal teardown also retire native admission
before waiting on serialized or platform cleanup. A deliberately suspended Stop
cannot authorize either a snapshot or an inert backend construction.
Normal Mac bootstrap binds this route and provides its runtime authority to the
existing same-store native composition. Explicitly injected providers remain
supported. The optional inert backend factory currently fails closed when absent.

## Verification

Selected stable Xcode 27.0: `/Applications/Xcode.app/Contents/Developer`.

- Nine focused authority/codec/route/gate checks passed, including acknowledged
  Desktop, wrong fence/correlation, unknown fields, expiry, original deadline and
  generation across renewal, non-Desktop/focus pause, menu/primary retirement,
  and immediate native admission fencing while Stop cleanup remains suspended.
- The normal Control Simulator regression passed all three UI journeys in
  162.62 seconds, followed by five pairing reliability checks. Report:
  `/private/tmp/maccompanion-feature-tests.TA2LIG/report.json`. This run preceded
  the final native-only early-Stop fence; that final fence is covered by the
  suspended-Stop check and final repository validation. The UI journeys use the
  existing media path, loopback transport, software test keys and synthetic local
  consent; they do not exercise complete native enrollment or new snapshot RPCs.
- Fifteen native engine/UIKit owner/launch tests passed on the dedicated
  MacCompanion Simulator at the final frozen state. Simulator and iPhone native
  components built unsigned.
- Eight real TLS cases and the actual isolated managed Sunshine admission,
  forbidden-route/listener, invalid proof/material, port-conflict, revocation and
  private-state cleanup checks passed again. These use synthetic Control
  authority, not the normal primary native journey.
- All six framework records and both real probes match the final source-input
  hash below; the managed host probe also matches the rebuilt Sunshine binary.
- Full final `bash scripts/validate.sh` exited 0 on stable Xcode; normal Mac
  product and C/Swift local transport compilation passed. `git diff --check`
  passed. Snapshot dispatch is compiled and its codec/generation gates are tested;
  fresh end-to-end native snapshot/enrollment over local XPC remains to be proved.

Source-input SHA-256:
`f6c988ef1ce52c9953dc1802fa592ee444e6b5a2e4e666fbae88b3fbc62c83be`.
Managed Sunshine binary SHA-256:
`0d84ac61a653f61237b60f927bbec7228d7bdc2e3f00a54ec705447584e837d2`.

Final validation log:
`/private/tmp/maccompanion-native-runtime-validation-final.log`.
Focused check log: `/private/tmp/maccompanion-native-snapshot-tests.log`.
Probe/inventory diagnostics remain outside Git under
`/private/tmp/maccompanion-sunshine-moonlight-20260926`.
No new normal app was installed. Native input remains disabled, and the default
backend factory is absent. This is an integration checkpoint, not usable native
streaming in the normal apps.

## Remaining

Connect menu-owned native prepare/activate/health/retire through the authenticated
local route, resolve the opaque approved display inside the menu process and wire
the managed backend. Admit source/dependency/process/TCC packaging, configure the
normal client adapter, prove live primary enrollment → launch → frame → Stop,
and add native presentation admission before enabling existing input. Signed
installation and physical acceptance remain open.
