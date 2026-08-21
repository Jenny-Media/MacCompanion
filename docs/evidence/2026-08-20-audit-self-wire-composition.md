# Self-audit wire composition evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

The v0.1 closed registry now includes `audit.list.request` and
`audit.list.response`. Three authoritative fixtures cover a first-page request,
a self plus privacy-safe host response, and rejection of a host row containing
device-scoped fields.

The host dispatcher derives the requester from the authenticated principal,
re-reads the current device, authorization/grant/policy fences and exact grant
set, requires `audit.readSelf`, and asks the detailed store only for that
device's scoped page. It maps no subject-device field to the wire. Missing or
stale grants return only a closed `policy.denied`; store failures return only a
closed local-repair error. The authenticated primary session owns replay and
routes the request with its revalidated principal.

The client pager constructs exact first/continuation requests, correlates each
response, enforces exclusive descending cursors across pages, preserves each
page's explicit gap metadata, and never accumulates an unbounded history or
infers completeness from an empty page.

## Result

The public validation gate passed with 54 authoritative fixtures and 604 Swift
tests. Focused additions comprise five wire tests, two host mapping/grant tests,
one primary-session routing test, and four client pager tests. The gate also
compile-checked macOS/iOS UI/platform targets, both Network targets, and three
no-prompt/no-network probes.

## Boundary not claimed

No live socket, signed Agent, local administration adapter, or audit producer
was exercised. A later package-level history UI now consumes this shape, but
physical authorization changes during page loads, disk repair, localization,
accessibility, and seven-day retention/rate measurements remain release-shaped
evidence.
