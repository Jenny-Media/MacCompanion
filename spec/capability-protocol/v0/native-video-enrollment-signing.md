# Native video enrollment signing input v0.1

Status: normative candidate signing construction with golden vectors. This does
not admit a remote message, native listener, credential store, or release engine.

The proposed bridge uses the existing authenticated primary and already approved
Control session. A client session key attests the exact ephemeral engine client
certificate and host engine certificate, both committed as SHA-256 of complete
DER bytes. These are distinct from the pinned application-host SPKI fingerprint.
The attestation cannot create Control or change any Observe/Act/Control grant.
No automatic substitution of MacCompanion keys into a Moonlight certificate is
permitted. Native certificate proof of possession remains the native TLS handshake.

The signing input is the ASCII domain `MacCompanion/NativeVideoEnrollment/v0.1`
followed by these fields in order. `LP` is unsigned 32-bit big-endian byte length
and exact bytes; UUID bytes use the existing sixteen-byte UUID convention.

1. LP host UUID; LP application host SPKI fingerprint (32 bytes).
2. LP client UUID; LP authenticated primary connection ID (16 bytes).
3. LP Interactive session UUID.
4. Authorization epoch, grant revision, policy revision: each unsigned 64-bit
   big-endian, positive and no larger than the JSON safe integer maximum.
5. LP native stream generation UUID; LP surface UUID.
6. Surface revision and coordinate-space revision: unsigned 64-bit big-endian,
   positive and no larger than the JSON safe integer maximum.
7. Encoded width and height: unsigned 16-bit big-endian; width 320…8192,
   height 240…8192.
8. LP engine client certificate SHA-256 (32 bytes), LP engine host certificate
   SHA-256 (32 bytes), LP host challenge (32 bytes).
9. Issued and expiry Unix milliseconds: unsigned 64-bit big-endian, positive,
   JSON-safe; expiry strictly after issuance and at most 15 seconds later.
10. Selected major/minor version: unsigned 16-bit big-endian values 0 and 1.

Sign with the existing P-256 session key and SHA-256 profile; raw signatures are
64-byte r||s using the existing signature verifier. Future host admission must
fetch the public session key from the exact authenticated client and revalidate
all identity/session/revision fields before and after every suspension. The
challenge must be single-use and scoped to that connection/generation. Its
expiry must also be within the original Control deadline; the signing constructor
cannot establish that runtime fact. A valid signature alone is never admission.

The bridge profile is acknowledged Desktop, App, or Window H.264/HEVC with
upstream input and audio disabled. Dimensions and surface identity must refer
to the same immutable approved capture. Surface kind is a trusted local
descriptor fact; it does not change the indexed signing bytes or golden
cryptographic vector. Native first-frame presentation and input acknowledgement
still require a separate normative contract before input can be enabled.

`spec/fixtures/crypto/native-video-enrollment-v0.1.json`, indexed only by
`spec/fixtures/manifest.json`, contains public conformance-only keys, certificate
digest stand-ins, exact signing bytes/hash, and a verifiable P-256 signature.
It contains no certificate, production key, pairing secret, or private app data.
The local challenge verifier follows the runtime profile below. Its acceptance
only verifies this attestation; it does not register a certificate or open a
listener.

## Local single-use challenge owner

The host creates one challenge object from its current authenticated primary,
approved Control binding, immutable current surface descriptor, and that client's
authenticated session public key. Both certificate digests are obtained from
the proposed complete DER certificates before challenge issuance. The object
generates 32 random bytes using the system cryptographic random generator;
conformance tests may supply the indexed vector nonce explicitly. Remote
payloads cannot choose the expected binding, key, surface, nonce, or deadlines.

At creation, sample wall and monotonic clocks once. Set the monotonic challenge
deadline to issuance plus the smaller of 15 seconds and the remaining original
Control duration. Encode that same duration in the signed Unix expiry. Reject
issuance at or after the Control deadline, invalid signing fields, and invalid
session keys. Subsequent wall-clock changes cannot extend the challenge.

Every verification attempt consumes the object before checking the signature,
including malformed, mismatched, expired, and rejected attempts. Cancellation
also consumes it. Copies or concurrent requests cannot reuse the object. Only
the exact current binding, surface, and authenticated session key may verify;
absence of any authority rejects. Monotonic time must be at least issuance and
strictly before both deadlines. An unchanged signing input with a valid golden
P-256 signature can then pass once. No asynchronous work occurs in verification.

The host must retain this single owner and revalidate current Control after any
later suspension before credential registration or launch. A new object always
requires a fresh host nonce; replaying an old signature on another object fails.
The companion runtime fixture `valid/native-video-enrollment-admission.json`
references the existing crypto vector through the sole fixture manifest.
`scripts/generate_native_video_enrollment_vectors.swift` independently constructs
the public vector. Regeneration can produce another valid ECDSA signature; the
fixture's canonical manifest digest must be updated intentionally with its bytes.

## Local enrollment and activation coordinator

This local profile admits a coordinator with an injected backend; it does not
admit remote message kinds or a release-target Sunshine dependency. The trusted
Control composition constructs an immutable binding, approved surface, and
registered client's session public key, plus a reader of current authority.
One coordinator owns one random operation ID. It cannot be restarted after
failure, cancellation, invalid proof, or retirement. Backend preparation may
validate the bounded client DER and create a private host key/certificate but
must not register a client, open listeners, launch capture, or enable input.
Both complete DER digests are computed by the coordinator, never accepted as
client-reported hashes. Certificates are bounded to 1…4096 bytes and must be
validated by the backend before it returns preparation material.

Reserve the preparation phase before any suspension. Check exact current
binding, surface, and session key and the original monotonic Control deadline
before preparation and after every suspension. Issue the existing single-use
challenge only after preparation and a fresh authority check. Consume the proof
phase before awaiting authority; parallel proofs must fail without affecting
the one reserved proof. Invalid proofs retire the backend. The original
challenge deadline applies through activation, including the final authority
read before returning an endpoint. A late successful activation after Stop or
authority loss must be retired and cannot be returned to the client.

Activation may register only the attested certificate in isolated state and
start the helper under the original Control deadline. Its endpoint identifies
only a bounded local port base; the authenticated primary transport remains
responsible for choosing the peer address. The backend must fence retirement
before its first suspension, cancel any pending work, wait for process exit,
and destroy its owned private credentials. It must not touch an installed
Sunshine service or another session's state. Repeated retirement joins one drain;
no replacement can overlap that drain. Input and audio remain disabled.

An active coordinator also checks that its exact backend operation remains
ready and running. A helper exit retires the coordinator even if Control remains
valid. Backend health reads are suspensions and require a fresh authority check.
An active coordinator checks authority and monotonic expiry at least every
50 ms, retiring on loss. The process backend independently enforces the finite
original deadline and parent death. A trusted caller also retires the coordinator
on primary disconnect, surface replacement, or explicit Stop. Clock rollback
below initial observation rejects preparation, proof, or activation. Remote
messages cannot set the conformance nonce used by tests.

The indexed `crypto/native-video-enrollment-coordinator-v0.1.json` independently
constructs exact signing bytes, hashes of explicitly non-certificate public
conformance bytes, and a matching session signature. Tests inject a fake backend
for those bytes. No production certificate validator may accept that fixture
as X.509. This complements the original signing vector without changing it.

## Client attestation owner

A local client owner binds the current authenticated primary, approved surface,
original client monotonic Control deadline, and custodied session public key.
It owns the exact generated client certificate DER. Before signing, validate
both native certificates through the platform validator and reconstruct the
normative signing input from these trusted local facts, the returned complete
host DER, nonce, and bounded signed Unix times. Require byte equality with the
proposed signing input. Never sign arbitrary host-provided bytes directly.
Start a local signing budget at receipt, bounded by the signed duration and the
original client Control deadline; it cannot extend the host challenge deadline.
Reserve one signing attempt before suspension, re-read exact current authority
before and after certificate validation and key custody, and verify the returned
signature with the expected session public key. Stop, expiry, authority loss,
or any failed attempt is terminal; a late custody result cannot be returned.
This creates no approval and uses no approval key. Remote message correlation
and native TLS certificate possession/pinning remain separate required gates.
