# v0.1 Cryptographic Encoding Profile

This file is normative. Implementations must verify the golden vectors before enabling application authentication or pairing.

## Primitive encodings

- Domain labels are the exact case-sensitive ASCII bytes shown, without a terminator.
- `U16BE` and `U32BE` are unsigned big-endian integers of exactly two and four bytes.
- `LP(bytes)` is `U32BE(bytes.count) || bytes`.
- UUID transcript values are the 16 RFC 4122 network-order bytes, not their JSON text.
- JSON UUIDs are lowercase canonical text with hyphens.
- `connectionID` is 16 uniformly random bytes and is JSON base64url without padding.
- Nonces and the pairing secret are 32 uniformly random bytes and are JSON base64url without padding.
- A P-256 public key is the 65-byte ANSI X9.63 uncompressed point `0x04 || X || Y`. JSON uses unpadded base64url of those bytes.
- A host fingerprint is 32 raw SHA-256 bytes. JSON uses lowercase hexadecimal.
- Text included in a transcript is NFC-normalized UTF-8 before `LP` encoding. v0.1 transcript identifiers are UUID bytes rather than text.
- SHA-256 and HMAC-SHA256 outputs are raw 32-byte values.

## ECDSA profile

Signatures use ECDSA P-256 with SHA-256. The signing algorithm hashes the complete signing-input bytes exactly once; callers do not prehash before invoking ECDSA-SHA256. Signatures are encoded as exactly 64 raw bytes `r || s`, each a 32-byte big-endian integer, and JSON uses unpadded base64url.

The verifier requires `1 <= r,s < n` and a mathematically valid signature. Low-S normalization is not required because signature bytes are never used as an identifier, cache key, digest input, or replay token; single-use challenge/transcript identity is independent of signature encoding. Implementations may emit low-S but must accept either valid S form.

## Application authentication

`authSigningInput` is:

```text
ASCII("MacCompanion/Auth/v0.1") ||
LP(clientID.uuidBytes) ||
LP(connectionID.16Bytes) ||
LP(clientNonce.32Bytes) ||
LP(serverNonce.32Bytes) ||
LP(hostFingerprint.32Bytes) ||
U16BE(selectedMajor) || U16BE(selectedMinor)
```

The client session identity key signs `authSigningInput` directly with ECDSA-P256-SHA256. `auth.proof.signature` is the raw 64-byte signature.

## Pairing flow and transcript

Message order is fixed:

1. `pairing.begin`: pairing ID, client ID, session public key, approval public key, client nonce.
2. `pairing.challenge`: host nonce, selected version, host fingerprint.
3. `pairing.prove`: secret proof and session-key signature.
4. `pairing.pendingApproval`: authentication string and transcript digest.
5. Local authenticated approval bound to the same transcript digest.
6. `pairing.complete` only after atomic pairing-session consumption and device/grant/epoch/audit commit.

`pairingTranscriptInput` is:

```text
ASCII("MacCompanion/Pairing/v0.1") ||
LP(pairingID.uuidBytes) ||
LP(hostFingerprint.32Bytes) ||
LP(clientID.uuidBytes) ||
LP(sessionPublicKey.x963Bytes) ||
LP(approvalPublicKey.x963Bytes) ||
LP(clientNonce.32Bytes) ||
LP(hostNonce.32Bytes) ||
U16BE(selectedMajor) || U16BE(selectedMinor)
```

`transcriptDigest = SHA256(pairingTranscriptInput)`.

`secretProof = HMAC-SHA256(oneTimeSecret, ASCII("MacCompanion/PairingProof/v0.1") || transcriptDigest)`.

`pairingSignatureInput = ASCII("MacCompanion/PairingSignature/v0.1") || transcriptDigest`.

The client session identity key signs `pairingSignatureInput` directly with ECDSA-P256-SHA256. `pairing.prove.signature` is the raw 64-byte signature.

`sasBytes = HMAC-SHA256(oneTimeSecret, ASCII("MacCompanion/SAS/v0.1") || transcriptDigest)`.

The authentication string is the first three bytes of `sasBytes`, rendered as six uppercase hexadecimal characters grouped `XXX-XXX`. Both devices compare the same value; it is display-only and is never accepted as a protocol proof.

## Pairing completion recovery

`pairingRecoveryTranscriptInput` is:

```text
ASCII("MacCompanion/PairingRecovery/v0.1") ||
LP(pairingID.uuidBytes) ||
LP(hostFingerprint.32Bytes) ||
LP(clientID.uuidBytes) ||
LP(sessionPublicKey.x963Bytes) ||
LP(approvalPublicKey.x963Bytes) ||
LP(clientNonce.32Bytes) ||
LP(hostNonce.32Bytes) ||
U16BE(selectedMajor) || U16BE(selectedMinor)
```

`recoveryTranscriptDigest = SHA256(pairingRecoveryTranscriptInput)`.

`pairingRecoverySignatureInput = ASCII("MacCompanion/PairingRecoverySignature/v0.1") || recoveryTranscriptDigest`.

The original client session identity key signs
`pairingRecoverySignatureInput` directly with ECDSA-P256-SHA256.
`pairing.resumeProve.signature` is the raw 64-byte signature. Both nonces are
fresh for every recovery connection. The Mac verifies the signature only
after locating the pairing consumption and comparing the complete stored
client/key tuple; a cryptographically valid signature for any different tuple
does not authorize recovery.

## Golden vectors

`spec/fixtures/crypto/v0.1.json` supplies fixed private keys, public keys, inputs, digests, proofs, recovery inputs, and example signatures. Fixed private keys exist only as public conformance data and must never be used by a product build. Cross-implementation conformance requires exact input/digest/HMAC parity and successful verification of the supplied signatures; ECDSA signers need not reproduce identical randomized signature bytes.
