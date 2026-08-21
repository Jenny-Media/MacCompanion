# Provider-neutral private access guidance — 2026-08-21

Status: bundle-independent contract, package UI, fixture migration, focused
tests, and disposable Simulator accessibility evidence passed under Xcode 27
beta. Signed-target Local Network permission behavior and physical LAN/private
network routes remain open.

## Protocol correction

The route profile previously encoded `tailscale` as a persisted provenance,
wire route class, and local diagnostic kind even though the product supports a
private network the user already manages, including but not limited to
Tailscale. Before v0.1 ships, that provider-specific value is replaced by
`privateNetwork` across the normative schema, indexed fixtures, Swift wire and
storage types, Agent status projection, diagnostic CLI corpus, and conformance
tests.

Tailscale, ZeroTier, and WireGuard remain setup examples. None is a protocol
identity, authorization source, dependency, SDK, process probe, interface
probe, status ingestion source, or network-management API. No compatibility
alias is retained because no released v0.1 state exists.

## Client guidance

`ClientPrivateRouteGuidanceProjectionV1` consumes either one immutable
configured-route snapshot plus a closed explicit connection fact, or the exact
route lifecycle carried by the application-binding snapshot. It cannot inspect an
`NWPath`, interface, DNS result, installed app, provider account, peer, socket,
or credential. It distinguishes:

- foreground/network scheduling waits;
- ready, dialing, and bounded-backoff route states;
- an authenticated endpoint that matches the exact saved catalog;
- route/configuration mismatch;
- Mac Companion authentication or authorization denial;
- manual disconnection; and
- closed lifecycle ownership; or
- a contradictory/transitional snapshot whose status is deliberately
  withheld.

Before lifecycle mapping, the projection requires coherent binding, lifecycle,
reconnect-owner, and controller state: exact host and catalog revision,
candidate order, host fingerprint, foreground and reachability facts,
transition flags, and closed/shutdown ownership. It does not merge a route-store
read with a later connection read. Every `ReconnectPhase` has an explicit
mapping, and invalid backoff state is unavailable rather than invented.

The connected state says the route completed identity pinning and application
authentication while granting no capability by itself. Authorization denial
directs the user to pairing/device access instead of disguising it as a network
problem. Coarse reachability is labeled only as a scheduling signal.

`ClientPrivateRouteGuidanceViewV1` renders two setup methods: the same trusted
local network, and a user-managed private network. It states that Mac Companion
operates no relay, VPN account, or public port-forwarding service and that
pairing, authenticated sessions, grants, and separate Remote Control approval
still apply. The existing route editor links to the guidance without giving it
edit, discovery, dial, or command authority.

## Verification

The focused `CompanionClientUITests` run passes 36 tests. Three tests cover
every guidance-state class and reconnect phase, exact authenticated-catalog
matching, provider examples remaining outside authorization, the no-relay
boundary, invalid backoff rejection, and the separation between route
exhaustion and authorization denial. A focused binding test also proves the
same snapshot carries initial background and fully closed lifecycle ownership.
A transport test proves controller-internal dialing, authenticated completion,
and shutdown each publish a content-free wakeup. The UIKit bridge consumes a
latest-one stream through its existing serialized event tail and always
re-reads the complete binding snapshot before presentation.

The complete Swift package suite passes after the provider-neutral fixture and
type migration. The authoritative fixture validator accepts all 63 indexed
JSON fixtures with updated canonical hashes.

The disposable unsigned iPhone 17 Pro Max Simulator harness compiles the real
package view and runs six XCTest UI tests with zero failures; the latest full
invocation completed in 106.144 seconds.
The Private Access test reaches the setup screen, verifies both setup methods,
finds Tailscale only inside provider-example copy, scrolls to the no-relay
boundary, and confirms that neither Connect nor Remote Control authority exists
on the screen. Both that screen and Application Lifecycle render the real
binding's `No usable network path` state from injected scheduling-only
reachability.

The complete hardened gate validates 63 indexed protocol/product fixtures,
760 repository files plus 34 historical blob paths and 14 repository-material
fixtures, four Swift package manifests and 12 dependency-policy fixtures, three
privacy manifests with 12 fixtures and six required-reason API source records,
10 source-SBOM fixtures, 16 release-evidence fixtures, and 1,030 Swift tests.
Every macOS/iOS package cross-compile and all three no-prompt/no-network probes
pass. Only the expected read-only user SwiftPM cache warnings appear.

## Remaining gates

- Instantiate the already-bound lifecycle projection in the permanent signed
  client target.
- Provide Local Network denial/recovery affordances after final identifiers and
  privacy strings exist.
- Prove clean-install Local Network grant, denial, Settings recovery, and
  revocation on physical iOS devices.
- Prove at least one authenticated LAN route and one authenticated
  user-managed private-network route on signed physical Mac/iPhone builds.
- Keep provider instructions externally maintainable; they are guidance and
  must never become a substitute for Mac Companion authentication.
