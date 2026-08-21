# Listener-owned pairing-context composition evidence

Date: 2026-08-20

## Claim

The Agent's sealed network-listener owner now controls whether host pairing QR
creation is available. `AgentNetworkPairingContextAuthorityV0` retains the
validated host fingerprint and canonical endpoint set but releases them only
while the exact listener and its Bonjour advertisement are both ready. Each
callback source has its own strictly increasing generation, and terminal stop
is nonthrowing and irreversible.

`AgentNetworkListenerServiceV1` publishes the same listener and advertisement
callbacks into this authority that it uses for route evidence. Advertisement
withdrawal invalidates and tombstones the active pairing QR without making the
handler terminal, allowing a fresh code only after advertisement recovery.
Listener cancellation, failure, or start failure first makes context
unavailable, permanently terminates the pairing handler, and invalidates its
active session. A create suspended inside the pairing authority observes the
terminal fence after resuming and compensates its newly created secret before
returning failure.

## Verification

Two context-authority tests prove both-readiness admission, independent stale
generation rejection, and terminal resurrection denial. One complete listener
composition test proves pre-ready denial, ready-plus-advertisement creation,
withdrawal tombstoning, recovery with a new code, terminal tombstoning, and
post-terminal denial. A separate handler race test suspends creation across
terminal loss and verifies its authority tombstone. The hardened unsigned gate
passes 794 Swift tests and validates 610 current repository files plus 34
historical blob paths.

## Boundary

The subsequent listener-pairing factory now derives the fingerprint, Bonjour
candidate, and port from the exact consumed TLS listener configuration. It
does not decide which additional private routes are approved or prove that an
authenticated XPC menu app displayed and discarded the response. Permanent
composition must supply only current approved private-route candidates and pass
the resulting authority and handler to the listener service. Signed listener,
Bonjour, XPC, QR-display, physical scan, and pinned-TLS exchange remain release
evidence.
