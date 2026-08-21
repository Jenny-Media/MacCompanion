# Interactive audit-producer construction evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

`BoundedInteractiveAuditWriterV0` maps authenticated request, verified approval,
and installed-start facts into closed scoped records with stable phase-specific
event IDs. `InteractiveSessionWireDispatcherV0` requires the approval record
after cryptographic bootstrap creation but before active reservation and menu
runtime installation. A failed required write returns only a closed local-repair
error.

Runtime-install failure publishes a closed failed terminal without a started
event. Primary-session disconnect performs runtime termination first, then uses
an injected host wall clock to publish a cancelled stopped terminal; neither
terminal record participates in or delays safety authority removal.

`BoundedLocalInteractiveStopAuditWriterV0` observes the final local stop receipt
after remote authority has ended and complete runtime safety teardown is proven.
It uses the durable local command ID and never delays or changes that receipt.

## Result

Seven focused tests prove requested/required-approved/started ordering, exact
importance and privacy bindings, zero runtime installs under an injected
required-write fault, idempotent local-stop publication, and completed safety
teardown plus degraded audit health under an injected stop-write fault. They
also prove disconnect-after-termination timing and failed-without-started
runtime-install reporting, plus durable started/stop drop accounting without
undoing runtime installation or teardown. The full repository result is
recorded after the public validation gate: 54 authoritative fixtures and 652 Swift tests, both UI
compile gates, and three no-prompt/no-network probes passed.

## Boundary not claimed

Permanent Agent/menu composition, signed XPC, physical TCC/capture/input
execution, real disk-full loops, repair UI, and stable-toolchain evidence remain
open. The release composition must supply both writers and surface their
degraded health.
