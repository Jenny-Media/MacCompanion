# Client pairing network construction evidence

Date: 2026-08-20

## Claim

`CompanionClientNetworkPlatform` now supplies the application pairing owner's
concrete no-relay Network.framework connection factory. One connection actor
races the QR's bounded route set with 250-millisecond staggering, passes the
same immutable 32-byte QR pin to every TLS attempt, accepts only a candidate
whose exact connection produced the verified TLS handoff, and closes every
loser or late winner.

The selected connection owns length-prefixed send/receive serialization and
close. The first post-TLS application call admits the pairing session's
monotonic deadline; every later call must carry that exact value. Send and
receive race against that byte-independent deadline, and timeout, malformed
framing, I/O failure, remote close, cancellation, or deadline substitution
closes the underlying connection. QR wall expiry separately bounds initial
route construction. Constructing the public factory or returned connection
starts no network or trust evaluation.

## Verification

Seven focused tests use injected route, stagger, clock, and framed-I/O seams.
They prove every QR route receives one pin and its remaining stagger-adjusted
timeout; the first verified winner is retained; fragmented frames converge;
deadline substitution, already-expired deadlines, and malformed lengths fail
closed; an expired QR starts no attempt; close cancels a suspended route race;
and factory construction is inert. The full unsigned validation gate passes
831 Swift tests, validates 629 current repository files and all 60 indexed
protocol/product fixtures, cross-compiles the client platform package, and
passes all three no-prompt/no-network probes.

## Boundary

This is deterministic construction evidence, not a live LAN or physical-device
claim. It does not prove Local Network permission attribution, Bonjour or
private-route reachability, real TLS callback timing, radio changes, app
backgrounding, certificate custody, latency, or QR exchange. Those remain
signed physical-device acceptance work. Application bytes are still admitted
only by the existing pairing authority after it revalidates the returned TLS
evidence against the QR fingerprint.
