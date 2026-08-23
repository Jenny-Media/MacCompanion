# Stage 3 authenticated route and final local review

Date: 2026-08-23

## Outcome

The permanent iOS product now completes the local Stage 3 capture loop for
authenticated route provenance, tester-confirmed Observe jobs, physical-return
reasons, comprehension, safety incidents, and recovery confusion. Final review
ends the active study session and permanently locks the report before preview
or export.

These additions remain optional and local-only. They do not change connection,
Observe, Act, or Control authority and they do not introduce telemetry.

## Authenticated route boundary

The exact winning product candidate projects one content-free route class only
after its pinned-TLS and application-authenticated session is selected as the
primary route:

- explicit local-discovery provenance becomes `lan`;
- explicit configured private-DNS provenance becomes `privateDNS`; and
- explicit configured private-network provenance becomes `privateNetwork`.

The projection carries no endpoint, address, DNS name, route record, configured
route identifier, interface, VPN process, or network identity. A direct private
IP address remains unclassified because its address cannot prove whether the
traffic used a LAN or user-managed private network. Losing, unauthenticated,
and terminated candidates publish no route evidence. A route-class change on a
later selected authenticated primary is recorded without duplicating an
already used class.

## Explicit Observe jobs

The fresh Observe screen offers a separate study action only while its status
is `live`. The tester must choose one predeclared Observe job category and
confirm a real completed job. Opening the screen, viewing cached status, or
refreshing for the study does not qualify. The product records no status values
or content, and this path neither starts nor counts Remote Control.

## Physical return and final review

During an explicitly active study day, the tester may record a physical return
using one closed reason. The report stores only that reason and day index.

Final review requires three separate acknowledgements: the safety incident
list was reviewed, misleading recovery presentation was reviewed, and the
tester understands the report will be locked. The four comprehension answers
may remain false; they are retained as incorrect answers rather than converted
to success or omission. Empty incident/confusion selections mean the explicit
review confirmed none, not that the UI silently defaulted them away.

Completion is a serialized durable mutation. On success the product ends the
study session. A reviewed report rejects a new session and every later product
or review mutation. In-flight review and physical-return actions cannot be
submitted twice or dismissed midway.

## Verification

Focused tests prove:

- only exact configured local-discovery/private-DNS/private-network provenance
  maps to a report class, while direct private address and absent records do
  not;
- the selected authenticated candidate and immutable product snapshot retain
  the closed class and clear it on termination;
- the workspace records route class only from its connected projection;
- Observe admission accepts only fresh live state plus an Observe category;
- the final report remains immutable and cannot begin another session; and
- the composed local report contains explicit Observe and Control jobs plus
  the authenticated route class.

The focused tests and iOS client-UI cross-build pass on Xcode 27 beta. The
permanent `MacCompanionIOS` generic-Simulator target also builds with signing
disabled. The complete repository gate passes 1,642 MacCompanionKit Swift
tests, eight platform-probe tests, all policy/release fixtures and supported
cross-builds, 1,222 current repository files, and the exact historical count
of 2,280 blob paths reported by the repository-material gate.

## Non-claims and next gate

This is construction evidence, not physical or market evidence. It does not
prove route correctness on a device, a real Observe/Act/Control job, tester
understanding, safety, lock behavior, Data Protection, physical-return recall,
or successful export. Calibration and confirmatory enrollment remain disabled.

The next independent slice is signed physical dogfood: compare the report to
visible same-LAN and configured-private-route truth across pairing, fresh
Observe, mute Act, Desktop/adaptive Control, Stop, lock/reconnect, and report
preview/export. External cohorts still require the participant disclosure and
retention policy plus the unresolved distribution gates.
