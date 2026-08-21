# v0.1 Host Identity and Certificate Lifecycle

Status: normative for key custody, P-256 SubjectPublicKeyInfo bytes, certificate renewal, and recovery decisions. The exact X.509 encoder, strict inspector, SQLite bootstrap/recovery transactions, and a compile-tested Security.framework startup coordinator and custody/listener-identity constructor are implemented. Final signed access-group behavior, real Secure Enclave/Keychain mutation and recovery, live TLS use, and physical first-unlock/lock evidence remain implementation gates.

## Durable identity

One enabled Mac user owns one random host UUID and one P-256 signing key. The LaunchAgent creates the key in the Secure Enclave with a permanent application tag, `AfterFirstUnlockThisDeviceOnly`, and private-key usage access control without user-presence prompts. The key is non-synchronizing and non-exportable. It is unavailable before the first user unlock after reboot; this condition waits locally and never generates a replacement.

The final access group, application tag prefix, and designated-requirement access are release-identity values and remain blocked on the final bundle prefix and signed-target topology. Only the authenticated LaunchAgent receives private-key access. The menu app receives the public host ID/fingerprint and bounded recovery state over authenticated IPC, never the private key or Keychain reference.

The P-256 public key is the validated 65-byte ANSI X9.63 uncompressed point. Its DER SubjectPublicKeyInfo is exactly:

```text
30 59
  30 13
    06 07 2A 86 48 CE 3D 02 01
    06 08 2A 86 48 CE 3D 03 01 07
  03 42 00
    <65-byte X9.63 public key>
```

The host fingerprint remains `SHA256(completeSubjectPublicKeyInfoDER)`. `CompanionSecurityV0` and `spec/fixtures/crypto/tls-spki-v0.1.json` freeze both constructions. Reissuing a certificate around the same key preserves every client pin.

## Certificate profile

The TLS leaf is a self-signed X.509 v3 certificate over the host identity key:

- serial number: 16 random bytes, positive DER INTEGER, nonzero;
- inner and outer signature algorithm: ECDSA with SHA-256, parameters absent;
- issuer and subject: one UTF8String common name exactly `Mac Companion Host`, with no user, device, DNS, organization, or route metadata;
- validity: UTCTime at whole-second precision, `notBefore = issuance time - 5 minutes`, `notAfter = issuance time + 90 days`;
- SubjectPublicKeyInfo: the exact P-256 construction above;
- critical Basic Constraints: CA false;
- critical Key Usage: digitalSignature only;
- noncritical Extended Key Usage: serverAuth only;
- no Subject Alternative Name and no route-derived name;
- certificate signature: DER ECDSA `SEQUENCE(INTEGER r, INTEGER s)` as required by X.509, distinct from the protocol's raw `r || s` signatures.

The client parses the presented leaf under a Mac Companion pinned-leaf policy rather than a DNS-name policy, validates its current profile and validity, confirms TLS 1.3 private-key possession, independently extracts the exact SPKI, and then matches the QR/stored fingerprint. The presented self-signed leaf is not required to be a CA trust anchor. A public CA, hostname, IP address, Bonjour record, or overlay certificate cannot substitute.

## Renewal and startup

The Agent recommends renewal with 30 days remaining and may keep serving the still-valid certificate while atomically installing a verified same-key replacement. Missing, malformed, wrong-key, not-yet-valid, expired, or out-of-profile certificates never cause key rotation: the Agent issues a replacement over the established key and preserves the pin. An expired certificate blocks new TLS admission until replacement succeeds; eligible already-authorized local work is unaffected.

The durable `established identity` marker distinguishes a fresh install from identity loss:

| Inventory | Required disposition |
| --- | --- |
| No marker, no key | Bootstrap a new host UUID/key/certificate |
| No marker, valid pending key, no certificate | Continue bootstrap with a certificate over that key |
| Key temporarily unavailable before first unlock | Wait; do not listen and do not rotate |
| Established key plus valid certificate | Serve; renew at the 30-day window |
| Established key plus missing/invalid/wrong-key certificate | Issue a same-key replacement; preserve pin |
| Established marker plus missing/invalid key | Stop remote service and require explicit local recovery |

Initial bootstrap uses a recoverable sequence. Before Keychain mutation, the
Agent durably inserts one bootstrap singleton containing the candidate host UUID,
the exact bounded Keychain application tag, and its start time. A restart adopts
that existing singleton instead of generating another candidate. The Agent then
creates or resumes only the key at that exact tag, issues and self-verifies its
certificate/SPKI/fingerprint, and atomically inserts the established identity,
deletes the matching bootstrap singleton, and records the minimal establishment
event before enabling the listener. A mismatched host UUID or key tag cannot
complete bootstrap. A crash before the final transaction therefore resumes the
same pending key; rollback preserves the bootstrap singleton and publishes no
established identity.

## Identity loss, compromise, and migration

Established-key loss or invalidity is never treated as first install. The Agent closes listeners, invalidates boot-scoped sessions/challenges/channel credentials, enters remote denial, and asks through authenticated local UI for recovery. Recovery copy states that every phone pin and pairing will stop working.

After local confirmation, a pre-armed durable recovery intent fences all existing devices/grants before a new host UUID/key/certificate is established. Only after the new identity and the invalidation audit commit are recoverably linked may the listener restart. A crash at any point resumes denial and the recorded recovery workflow; it never restores an old grant under a new key. Suspected compromise uses the same path. Backup, migration, reinstall, or Time Machine restore never silently transfers or replaces the private key; a successfully preserved same-device Secure Enclave key may renew its certificate, while loss requires recovery and re-pairing.

The confirmed recovery coordinator uses the durable recovery UUID as the new
key-tag reference. Its exact cross-store order is:

1. atomically fence the current identity, every device/grant, and admitted work;
2. create or resume only the new recovery-tagged key and self-verify its leaf;
3. delete the old tagged private key idempotently while the durable row remains
   fenced; and
4. atomically replace the fenced row with a different host UUID/tag/fingerprint
   plus the `hostIdentity.recovered` event and one last-recovery receipt binding
   the recovery UUID and both old and new public identities.

New-key or deletion failure leaves the durable fence and old identity record in
place. A crash after old-key deletion but before replacement resumes the same
recovery UUID/new key, repeats old-key deletion safely, and completes the same
fenced workflow. Replacement never precedes old-key deletion, because losing
the old tag from durable state would make orphan cleanup ambiguous. No listener,
pairing, authentication, or grant authority is available while fenced.
An exact retry matching the last recovery UUID and old host UUID/fingerprint
returns the completed replacement and does not fence or rotate it again. A
different expected identity conflicts before mutation.

The release Agent obtains this coordinator only from the Network-platform
recovery product factory, which binds it to the required-audit root's exact
private security store and concrete host Keychain configuration. The final
authenticated local-XPC handler accepts only an exact, unexpired Agent-issued
review bound to the current host UUID and fingerprint, then supplies its
already-confirmed durable recovery UUID to the coordinator. Remote traffic and
the menu presentation model never receive a recovery coordinator or Keychain
reference, and the command cannot choose replacement identity material.

Uninstall removes service registration and the app bundle but retains identity/grants only when the documented uninstall choice explicitly says settings will be preserved. A destructive identity reset is a separate locally confirmed action and must report that prior pairings cannot be recovered.
