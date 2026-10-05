# Saved Mac library

The iOS remote desktop product supports up to the existing paired-host store
limit of 64 Macs. Every Mac retains its own exact host pin, device identity,
session key, approval key, and configured-route catalog. No authentication,
pairing transcript, grant, or signing input changes in this profile.

Startup validates the complete inventory for installation identity and reused
host/device/key references. It registers each complete identity with custody.
A single Mac keeps the existing startup flow; multiple Macs open My Macs and
do not dial until the user selects a Mac. A missing route catalog requires
setup for that Mac alone. Route records without a paired identity cannot dial.

Pair Another Mac drains the existing connection before preparing pairing. The
verified completion's host ID selects route setup; inventory order is never
used to infer which pairing just completed. Selecting a Mac uses exact host-ID
lookup for both the primary owner and the native session signer. Late failure
callbacks from a retired owner cannot invalidate a newer workspace.

Names are local presentation metadata, bounded to 80 non-control characters.
They neither identify a peer nor change authority. Existing unnamed records
receive distinct fallback names in the library.

Forget This Mac is local removal, not host-side revocation. Drain all owned
products before removal. Durably record a pending removal before deleting
keys, routes, or the paired-host record. Pending removals are never selectable
or eligible to reconnect. Remove only that host's exact key pair, then its
route catalog and exact public identity. Retry interrupted removals on startup;
retain the tombstone on failure. Other Macs remain usable. Removing the final
Mac returns to pairing. Pairing that Mac again requires a new local approval.

The indexed `client-mac-library-v0.1.json` records inventory and removal cases.
