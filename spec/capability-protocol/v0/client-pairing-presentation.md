# Client pairing presentation v0.1

Status: normative bundle-independent presentation state. This profile defines what an iOS pairing UI may claim and when. It does not define camera capture, SwiftUI layout, sockets, Keychain custody, or durable-storage implementation.

## Closed progression

The presentation reducer has this closed progression:

```text
scanning
  -> preview
  -> starting
  -> securing
  -> compareOnMac
  -> saving
  -> paired
```

Any nonterminal attempt may instead become `failed`; reset returns to `scanning`. Request ID and pairing ID mismatches cannot advance the reducer.

Strict QR decoding produces only a preview. The preview contains pairing ID, expiry, a display-formatted host fingerprint, route kinds, and candidate count. It contains no QR text, one-time secret, endpoint value, or port. The fingerprint is explicitly `unverifiedScan`. Scanning alone cannot produce a transport-start intent.

Only explicit user acceptance of that exact preview produces the one security-sensitive start intent containing the decoded QR payload. The caller passes that value directly to `ClientPairingSessionV0` and never logs or persists it. The presentation reducer immediately drops its retained QR payload.

## Trust claims

`starting` and initial `securing` state keep the fingerprint marked unverified. Only notification that the pairing authority accepted the live QR-pinned TLS peer changes the visible fingerprint state to `pinnedTLSVerified`. Endpoint candidates remain routing hints and never become identity evidence.

The six-hex-digit authentication string is absent while connecting, pinning, or building the proof. It becomes visible only from `ClientPairingApprovalV0`, which the pairing authority publishes after it verifies response correlation, transcript digest, derived authentication string, QR expiry, and the pinned connection. The UI labels this state for comparison with the Mac; it does not describe the string itself as prior proof and it does not claim that a grant exists.

## Durable completion

A verified `ClientPairedHostV0` completion is not immediately presented as paired. It must match the accepted pairing and verified approval and must still prove `activeMonitorOnly`, authorization epoch 1, and grant revision 1. The reducer then emits one commit intent containing the verified public host record and enters `saving`.

Only an exactly correlated persistence success for the same complete host record enters `paired`. A mismatched receipt or storage failure publishes no usable paired host. Private keys are outside this intent and remain under the client Keychain owner.

## Acceptance boundary

Bundle-independent tests cover explicit acceptance, invalid/expired scans, unverified-to-pinned fingerprint transition, impossible early SAS display, stale request and pairing rejection, durable-before-paired publication, exact stored-record correlation, and secret/SAS cleanup on failure. Camera capture, accessibility copy, Keychain-backed keys, atomic client storage, live pinned transport, and physical-device exchange remain release evidence.
