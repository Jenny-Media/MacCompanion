# Authenticated capability discovery v0.1

Status: normative privacy-limited discovery profile.

The remote client receives only capabilities that are both present in the
host's current registry and durably granted to the authenticated device. The
host never exposes ungranted capability IDs, unavailable grant remnants, raw
provider inventory, provider IDs, provider versions, provider generations, or
execution revisions through this response. Discovery grants no authority;
invoke, approval, durable admission, and execution claim repeat their own exact
checks.

Responses are sorted by exact capability ID and contain at most four
descriptors. Each encoded descriptor is at most 12,000 bytes and every complete
wire envelope remains within the 65,536-byte frame bound. A descriptor contains
only its public ID, schema version, bounded English fallback presentation,
closed parameter and result schemas, and closed effect facts used for honest
client presentation.

The first request has all three cursor fields null. If `nextAfterCapabilityID`
is nonnull, it equals the last returned capability ID. A continuation repeats
the response's registry generation and grant revision and supplies that exact
last ID. All three continuation fields are present or all are null. The server
requires the cursor ID to remain in the current visible ordered set.

A provider-registry generation or grant-revision change returns the closed
`capability.registryChanged` error with `afterReconnect` and no arguments. A
client discards every accumulated page before requesting a new first page. A
device, authorization epoch, active state, grant revision, or policy revision
change is an authenticated-session failure and closes the primary session
before further inventory disclosure.

The client publishes no partial catalog. It accumulates pages only while the
registry generation, grant revision, policy revision, cursor order, and global
256-capability bound remain exact. Any mismatch discards every accumulated
descriptor. Only the final page atomically publishes a catalog for input and
result presentation.

For a successful operation with a live result, the client validates the result
against the invoked catalog descriptor's exact result schema before rendering
it. A capability-ID mismatch or schema mismatch produces no provider content.
Unknown terminal identifiers map to a generic failure presentation; raw
unregistered provider text is never shown. `outcomeUnknown` remains distinct
from success and failure.
