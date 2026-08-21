# Exact listener and pairing-context factory evidence

Date: 2026-08-20

## Claim

`AgentNetworkListenerPairingCompositionFactoryV0` consumes one
`NetworkHostTLSListenerConfigurationV0` and returns its unstarted sealed
listener together with the initially unavailable pairing-context authority.
The QR fingerprint comes directly from that TLS configuration. The factory
derives the only Bonjour endpoint from the configuration's instance name,
service type, domain, and the exact listener port.

Additional private-route endpoints are bounded to seven, cannot claim Bonjour
provenance, and must use the same port. Invalid zero ports, caller-authored
Bonjour candidates, and mismatched route ports fail before listener creation,
so they do not consume the single-use configuration. A second valid factory
call is rejected by the underlying sealed-listener owner.

## Verification

Three tests construct a real in-memory Security.framework host identity and
TLS 1.3 listener configuration. They prove exact fingerprint, derived Bonjour
value, common port, accepted additional IPv4 route, pre-consumption rejection,
and single-use preservation. The hardened unsigned gate passes 806 Swift tests
and validates 619 current repository files plus 34 historical blob paths.

## Boundary

The factory proves construction identity, not route-policy correctness or live
network behavior. Permanent composition must supply only approved current
private-route candidates and must still pass the returned listener, context,
and pairing handler into the same Agent listener service. Signed identity
custody, interface selection, Bonjour registration, authenticated XPC, physical
scan, and pinned live TLS remain release evidence.
