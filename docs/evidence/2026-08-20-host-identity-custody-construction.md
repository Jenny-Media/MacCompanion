# Host identity custody construction evidence — 2026-08-20

Status: provisional construction evidence under Xcode 27 beta. This is not a signed-Agent Keychain mutation, Secure Enclave access-control inspection, live listener, TLS handshake, first-unlock result, or release result.

`CompanionHostPlatform` now contains a Security.framework host-identity custody constructor. Its configuration derives one lowercase role-scoped application tag from a caller-owned bootstrap or recovery UUID and caps the complete tag at the persistence profile's 128-byte limit. Foreign, uppercase, malformed, and overlong tags fail before a Keychain lookup.

The production constructor:

- creates or resumes only the exact pending application tag selected by the durable bootstrap/recovery owner;
- requests a permanent P-256 Secure Enclave key with `AfterFirstUnlockThisDeviceOnly` and private-key-usage access control, with no user-presence flag;
- returns only public X9.63, exact SPKI, fingerprint, and opaque tag material;
- distinguishes missing from pre-first-unlock unavailability and never regenerates an established identity implicitly;
- signs the exact v0.1 self-signed certificate input with ECDSA/SHA-256, strictly reinspects the complete certificate, and requires the inspected key/SPKI to match; and
- builds an in-memory `SecIdentity` from that exact certificate and private-key reference without exporting private bytes.

Four no-prompt tests cover the frozen creation profile, exact tag grammar and cross-store bound, foreign/noncanonical pre-query rejection, and an ephemeral in-memory Security.framework path from P-256 key through certificate signing, strict inspection, and `SecIdentity` private-key association. They do not invoke the production permanent-key creation, lookup, or deletion methods.

Acceptance still requires the final signed Agent and access group, real Secure Enclave token/accessibility inspection, reboot/first-unlock/lock behavior, pending-key crash reconciliation with SQLite, key-loss recovery, renewal/expiry faults, live Network.framework identity installation, and stable Xcode 26.6 evidence.
