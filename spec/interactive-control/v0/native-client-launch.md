# Native client TLS and launch candidate v0.1

Status: local adapter construction; no permanent dependency or product admission.
The primary enrollment/signing profiles remain authoritative. This adapter has
no pairing, approval, discovery, input, or audio authority.

One enrollment owns one ephemeral RSA-2048 self-signed client TLS certificate
and private key, generated in memory with clientAuth usage and a random serial.
Its complete canonical DER is attested using the existing session-key profile.
The private key is never exported or written to disk/Keychain. Retirement fences
new work, interrupts sockets, joins pending launch work, and releases the key.

TLS requires the exact complete host certificate DER from the correlated enrolled
challenge. Require canonical DER, a current self-signed RSA certificate of at
least 2048 bits, and the appropriate client/server extended key usage. Reject a
mismatched leaf, malformed/trailing DER, expired certificate, or substituted key.
Use TLS 1.2 or newer with peer verification. No system-trust fallback, unpinned
request, HTTP fallback, redirect, upstream PIN pairing, or external entity access.

Connect only to the IP address obtained from the selected verified primary's
current route, with native portBase supplied by the ready reply. Validate the
exact primary ID before and after suspensions. Do not accept an arbitrary address
from UI, discovery, native server metadata, or an RTSP URL. The selected
primary's numeric authenticated endpoint may supply this address while its exact
connection ID remains current. DNS/Bonjour endpoints require separately measured
numeric-route evidence; unresolved names are unavailable to this adapter. The native HTTPS port
is portBase minus five. Endpoint construction itself grants no Control.

Only bounded serverinfo, applist, launch, and cancel operations are allowed.
Require successful closed XML response fields; reject duplicate required values,
DTD/entities, unbounded responses and unsuccessful HTTP/native status. Launch
requires a sole Desktop application and immutable approved encoded geometry.
Generate a fresh 16-byte stream key and key ID; do not use the application session
signing key as transport material. Require an encrypted `rtspenc` session URL at
this exact host IP and the port selected by the enrolled native port base. Native
video requests ENCFLG_ALL. Do not accept resume, arbitrary application IDs,
controllers, microphone, HDR, or alternate endpoint/port metadata.

Each request is bounded to five seconds and 1 MiB; every launch transition checks
current Control before and after work. Stop fences first and discards a late
result, drains native rendering and enrollment, interrupts TLS, and erases owned
transport material. A successful launch neither acknowledges presentation nor
permits input. The original Control deadline is never extended. The acknowledged
surface remains subject to its active session/epoch/revision fences; descriptor
freshness at admission is not an additional lifetime for that active surface.

The indexed local admission fixture records positive and denial cases. It uses
public test descriptions only; real certificate/secret generation stays outside
the fixture corpus. Existing cryptographic enrollment vectors continue to bind
both complete certificate hashes and the original primary/session/surface.


## Normal development composition

First-party launch, TLS and video wrappers are production sources under
`Native/Client`. Normal iOS development composition may select their adapter only
through an explicit locally admitted native development build with the verified
source-built engine. Module availability alone is insufficient. Reference-only
surface probes are excluded from the normal engine/adapter build. Release does
not select this development authority. Existing pairing/signature, current-primary
route, presentation, background retirement and input admission remain unchanged.
