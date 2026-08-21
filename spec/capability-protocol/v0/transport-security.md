# v0.1 Pinned TLS Admission Profile

Status: normative for the bundle-independent TLS admission boundary. Host key/certificate semantics are frozen in [`host-identity-lifecycle.md`](host-identity-lifecycle.md); exact X.509/Security.framework custody, strict host TLS parameter construction, client pinned-leaf evaluation, exact accepted-connection host metadata/handoff composition, role-safe first-frame ingress, and injectable host/client primary and pairing frame pumps are compile-tested. Final signed custody, physical live-metadata execution, listener/interface policy, and route evidence remain platform work.

## Host pin

The host fingerprint is exactly `SHA256(leafCertificate.subjectPublicKeyInfoDER)`. The input is the complete DER SubjectPublicKeyInfo object, including its algorithm identifier and BIT STRING wrapper; it is not the raw ANSI X9.63 point, the entire certificate, a DNS name, a public-key description, or a trust-chain digest. v0.1 bounds this input to 1–4,096 bytes before hashing.

`spec/fixtures/crypto/tls-spki-v0.1.json` contains one conformance-only P-256 SubjectPublicKeyInfo value, its exact fingerprint, and a mismatched pin. These values are public test material and must never ship as a product identity.

## TLS evidence

Before admitting any application byte, the platform adapter supplies evidence from the live TLS verification callback that:

- the negotiated version is exactly TLS 1.3;
- early data was not accepted;
- the adapter accepted the leaf under the Mac Companion pinned-leaf policy, including strict certificate parsing/profile checks, handshake proof of the private key, and current validity;
- the exact leaf SubjectPublicKeyInfo DER bytes are available for independent hashing; and
- the recomputed fingerprint exactly equals the pairing QR or stored device pin.

The pinned-leaf policy is intentionally independent of route and public Web PKI naming. Bonjour hints, IP literals, private DNS, VPN identity, tailnet names, and system-default CA success cannot replace the Mac Companion pin. Conversely, a pin comparison alone cannot replace live TLS proof of the corresponding private key or platform certificate validation.

TLS session resumption may be evaluated later, but v0.1 never accepts 0-RTT. Resumption cannot skip live peer evidence, application authentication, current authorization-epoch validation, or Interactive Control channel authentication.

Host and client frame pumps consume one-use verified-connection authorities and replay the same evidence through their bundle-independent session authorities. On the host, the sealed listener owner creates an accepted-connection authority that starts and evaluates negotiated metadata on that exact object, constructs the binding from the configured served identity, and transfers the same connection to the pump without restarting it. Arbitrary caller-provided connection-plus-binding construction is not public API. Physical execution must still prove that Network.framework supplies the expected live metadata and that the real socket handoff behaves as compiled.

## Admission phases and roles

Every connection moves only through:

```text
awaitingTCP -> awaitingPinnedTLS -> awaitingRoleAuthentication -> ready -> closed
```

The phase cannot move backward. Close is terminal. Before `awaitingRoleAuthentication`, no pairing, application-authentication, Interactive Control credential, command, event, input, or media bytes are admitted.

| Connection role | Before ready | After ready |
| --- | --- | --- |
| Pairing primary | Closed pairing handshake only | No general command/event authority; reconnect through application authentication after pairing |
| Application primary | Closed application-authentication handshake only | Capability command and event frames |
| Interactive input | Closed role-bound channel handshake only | Reliable input frames only |
| Interactive media | Closed role-bound channel handshake only | Binary media records only |

The host-owned pairing, application-authentication, or Interactive Control credential authority decides when role authentication succeeds. TLS admission does not grant a device, validate an authorization epoch, consume a pairing secret, or consume a channel credential.

Wrong TLS version, accepted early data, failed pinned-leaf platform validation, malformed SPKI, pin mismatch, premature traffic, role-crossed traffic, replayed authentication after ready, or an invalid phase transition closes the connection. A failed route cannot create or update application authorization state.

## Adapter acceptance evidence

The Network.framework adapter is not accepted by construction alone. Disposable and then release-shaped tests must prove the same pin across Bonjour, canonical private IP, private DNS, and a user-managed overlay route; reject a different key and a terminating proxy; show 0-RTT disabled; and demonstrate that input/media bytes cannot arrive before their respective credential proof. Certificate expiry, rotation, loss, reinstall, migration, and compromise recovery must conform to the locally confirmed host-identity lifecycle profile before external distribution.
