# Agent LAN route evidence — 2026-08-20

Status: bundle-independent construction and injected test evidence under Xcode
27 beta. This is not a live Bonjour registration, Local Network permission,
final signing, authenticated XPC, or physical-device result.

Apple documents listener readiness and Bonjour service registration as
distinct facts: a ready listener may not yet have registered its service, and
`NWListener.ServiceRegistrationChange` reports advertisement endpoint adds and
removes. Mac Companion therefore does not equate `.ready` with LAN discovery.
See [Apple's listener-ready semantics](https://developer.apple.com/documentation/network/networklistener/state/ready)
and [service-registration changes](https://developer.apple.com/documentation/network/nwlistener/serviceregistrationchange).

The sealed TLS listener constructor now configures exactly one
`_maccompanion._tcp` service in `local.` before returning the unstarted owner.
Its lowercase instance is derived only from the already permitted untrusted
64-bit fingerprint hint, and its TXT record contains only `v=0` and that hint.
The platform IO privately tracks registered endpoints only to collapse add and
remove callbacks into a Boolean; endpoint values never cross into the Agent,
local status, fixtures, or evidence.

The local-service root now exposes a source-specific
`AgentLocalLANRouteEvidenceAuthorityV1`, not the raw route mutator. It publishes
`lan` only when the exact listener callback and exact service-registration
callback are both ready. Either loss withdraws only `lan`, preserving future
independently authenticated route kinds. Listener and advertisement generations
are separate, delayed older generations fail closed, freshness remains bounded,
and root stop permanently prevents callback resurrection.

The listener service forwards registration and listener facts independently.
Route-publication failure is reduced to a closed local failure and cannot start,
accept, retain, or cancel transport differently. Injected end-to-end tests prove
listener-only and advertisement-only states remain non-LAN, both facts publish
LAN, either loss withdraws it, delayed callbacks cannot restore it, other route
kinds survive LAN withdrawal, invalid publication does not commit a source
generation, and stop is terminal.

The public validation gate passed 54 indexed fixtures, all 698 Swift tests
including 85 `CompanionAgent` tests, Network and Mac UI builds, iOS Simulator
client-platform and client-UI builds, all three no-network probe builds, and
`git diff --check`. SwiftPM user-cache warnings are expected in the restricted
environment. Stable Xcode 26.6, final identities, responsible-code attribution,
and signed physical Local Network grant/deny/recovery plus Bonjour
advertise/browse/resolve evidence remain required for acceptance.
