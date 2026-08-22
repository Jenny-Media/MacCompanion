# Permanent enabled-Agent network activation

Date: 2026-08-22

## Claim

Canonical enabled startup now selects the complete prepared Agent product
instead of the earlier status-only preparation. The permanent executable still
receives one opaque application-platform owner and cannot select an XPC
profile, listener, port, pairing authority, request context, or provider.

The package-owned activation order is fixed:

1. start the conservative public-session request-context observer;
2. start authenticated lifecycle/readiness/status XPC with the presentation
   profile;
3. wait for one authenticated and ready menu generation;
4. consume the one-use prepared TLS/primary root into one pairing/network
   product;
5. construct and start its sole shared listener using the same retained
   primary and pairing request-context authority.

The v0.1 listener uses TCP port `59653`, which is in
[IANA's dynamic/private range](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml).
Startup fails closed on a bind conflict rather than selecting a new port that
would silently invalidate a saved private route. The initial pairing
policy revision is exactly one. Pairing wall and monotonic times come from a
live system source and remain validated by the existing bounded pairing-time
type.

Composition, listener start, cancellation, or request-context failure retires
the complete prepared product. Repeated finish joins one barrier. Disabled
startup still constructs only the one-use durable enablement profile;
first-unlock constructs no service; recovery constructs authentication-only.

## Verification

`MacAgentEnabledProductRuntimeV1Tests` proves the exact fixed port and policy,
context startup before selected-product start, composition-before-listener
ordering, valid live clock samples, duplicate-start denial, composition and
listener failure cleanup, and exactly-once product finish.

The complete `CompanionAgentProductPlatformTests` target passes 38 tests. The
permanent-target validator now requires the full inert factory, enabled-product
selection, fixed profile, production product/listener calls, terminal cleanup,
and exact order. Its adversarial fixtures reject a status-only substitution,
presentation authority in the executable-facing layer, and reordered runtime
activation.

The complete repository validation gate passes with 1,393 listed
`MacCompanionKit` Swift tests, all cross-target compile checks, eight
platform-probe tests, and the static fixture, privacy, dependency, SBOM,
signing, notarization-construction, packaging, and release-evidence validators.

The permanent Xcode scheme also builds both unsigned and with the locally
installed Apple Development identity. Strict deep verification passes for the
containing app, strict verification passes for the separately signed embedded
Agent, and both executable roles contain `arm64` and `x86_64` slices. Neither
artifact was launched or registered.

No Agent, login role, listener, Bonjour advertisement, or network connection
was started for this checkpoint.

## Non-claims and next gate

The permanent menu target still constructs the presentation-inert dashboard
client. It can complete readiness and status, but it does not yet install the
pairing-review and host-recovery presentation receiver. If the Agent attempted
to publish either surface, the client would invalidate the connection and the
network product would fail closed.

The next construction gate is therefore the permanent menu presentation
composition plus the closed menu-to-Agent commands for pairing-session
creation/dismissal and pairing-decision resolution. Only after those paths are
bound may a signed physical QR round trip claim LAN pairing. Host-identity
recovery command transport remains a separate destructive gate.
