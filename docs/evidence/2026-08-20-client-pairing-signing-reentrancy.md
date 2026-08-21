# Client pairing signing-reentrancy evidence

Date: 2026-08-20

## Claim

`ClientPairingSessionV0.receiveChallenge` delegates the exact transcript-bound
signature input to opaque key custody. That call is asynchronous because
Secure Enclave or Keychain execution can wait for platform work. The session
now marks proof signing in flight before suspension, denies any second proof
call, and revalidates both the in-flight fence and the exact
`awaitingChallenge` phase after the signer returns.

Every terminal path clears the signing fence. Closing or expiring the session
while signing therefore makes the resumed call fail closed instead of
publishing a proof or restoring a later phase. A concurrent second proof call
also terminates the attempt; it cannot race the first signer result or select a
different proof message.

## Verification

Two actor-reentrancy tests suspend the signer deterministically. One closes the
session before releasing the signature and proves that the original call
returns `invalidPhase(.closed)` with no deadline or approval left. The other
issues a second proof call during the suspension and proves both calls fail and
the session remains closed. The hardened unsigned gate passes 818 Swift tests.

## Boundary

This proves bundle-independent actor serialization with an injected signer. It
does not claim physical Secure Enclave execution, user-presence prompting,
live socket cancellation, or a complete iOS application pairing owner. Those
remain separate platform and composition evidence.
