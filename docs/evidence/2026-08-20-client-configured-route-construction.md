# Client configured-route construction — 2026-08-20

Status: fixture-backed bundle-independent client model, atomic file
persistence, exact reconnect-attempt binding, concrete authenticated frame
pump, and [durable configuration/UI composition](2026-08-20-client-configured-reconnect-composition.md)
under Xcode 27 beta. App-lifecycle orchestration, rendered/signed UI evidence,
and physical routes remain open.

The indexed client-route fixture defines four explicit provenances bound to one
opaque 16-byte configured-route ID and one exact canonical endpoint. Bonjour is
`localDiscovery`; only RFC 1918 IPv4 and IPv6 ULA literals may be
`directPrivateAddress`; ordinary private DNS requires a DNS endpoint; and
Tailscale may be a DNS, IPv4, or IPv6 endpoint.
Catalog construction rejects mismatched pairs, duplicate IDs, duplicate
endpoints, more than eight records, and a winning endpoint absent from the
catalog. Only `privateDNS` and provider-neutral `privateNetwork` map to wire
observations.

`ClientPrimarySessionV0` retains the authentication-issued connection ID only
after the exact correlated session description succeeds. It then constructs
sequence one and later strict-sequence heartbeats from the configured record,
admits only one pending observation, and requires the acknowledgement to match
the request correlation, connection, opaque route ID, class, and sequence.
Mismatch closes only that offending primary session. A successful ack exposes
the exact 15-second next-heartbeat deadline.

`AtomicFileClientConfiguredRouteStoreV1` persists one canonical catalog per
host in an app-owned 0700 directory. Each 0600 record is bounded to 16 KiB;
the inventory is bounded to 64 hosts and rejects unknown, symlinked,
noncanonical, corrupt, or mismatched sibling state. Updates require an exact
monotonic revision, write and `fsync` a same-directory temporary file, rename
atomically, then `fsync` the directory. A 0600 advisory lock serializes
independent store instances. Restart recovery removes only correctly named,
bounded, regular `.pending-<uuid>` remnants; every other unknown hidden entry
fails closed.

The concrete route attempter resolves only the exact candidate endpoint from
the immutable catalog and passes that record into the new client session. A
catalog mismatch is terminal configuration denial rather than provenance
inference. After the correlated session description authenticates identity,
the frame pump publishes that identity, writes the initial observation when
required, and only then marks the connection usable by the dial winner. This
separation prevents a failed metadata write from returning a dead winning
route while keeping the observation and its ack non-authorizing. The pump
accepts unrelated authenticated traffic while an ack is pending, requires the
exact ack through the session authority, owns the 15-second heartbeat, closes
on the bounded 30-second ack deadline, and cancels both timers on teardown.

Focused tests cover all fixture records and mismatches, exact winning-endpoint
lookup, duplicate ID/endpoint denial, canonical/revision/restart behavior,
every rename boundary, independent-store serialization, owned-remnant cleanup,
unknown-sibling denial, request construction, ack correlation, heartbeat
sequencing, unrelated traffic while awaiting ack, failed-write winner fencing,
and mismatch teardown. The repository gate passes 60 indexed fixtures and 744
Swift tests including 90 `CompanionAgent` tests, both UI compile gates, and all
three no-network probes.
