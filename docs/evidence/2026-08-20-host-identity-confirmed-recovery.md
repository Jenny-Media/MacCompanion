# Host-identity confirmed recovery evidence — 2026-08-20

## Claim

The bundle-independent macOS platform now composes crash-safe destructive host
identity recovery after local confirmation.

The coordinator first atomically fences the current identity, every device and
grant, and admitted work. It uses the durable recovery UUID as the exact new
Keychain-tag reference, creates or resumes that key, issues and strictly
verifies its leaf, and validates a different host UUID/tag/fingerprint before
any destructive cleanup. Only then does it idempotently delete the old tagged
private key while SQLite still retains the old tag in the fenced row. Finally,
it atomically installs the replacement identity and
`hostIdentity.recovered` event.

This order makes the hard crash window recoverable: if completion fails after
old-key deletion, the fenced row still identifies the old tag and recovery
resumes the same new key. Schema v6 now also commits one last-recovery receipt
atomically with replacement so response loss after commit returns the completed
result instead of rotating the replacement identity. No listener or prior
pairing can become active while the row is fenced.

The public Agent Network-platform factory binds the local recovery service and
coordinator to the exact private security store owned by the required-audit
root and to the concrete host Keychain configuration. It does not expose
recovery to remote traffic.

## Automated evidence

The original four focused tests plus the local-recovery composition tests prove:

- successful recovery observes `fencedForReplacement` at old-key deletion and
  publishes a different host ID, tag, fingerprint, and exact event sequence;
- injected replacement-commit failure after old-key deletion leaves the old
  row fenced, and retry repeats deletion safely and completes with the same
  recovery-tagged key;
- Keychain deletion failure leaves the durable fence and old tag/reference in
  place with no replacement event; and
- a different recovery UUID conflicts before preparing, issuing, or deleting a
  second key; and
- stale reviewed identity cannot fence, while exact post-commit replay performs
  no second issuance, deletion, event, or recovery execution.

The complete unsigned repository gate validates 60 indexed fixtures, 691
repository files, dependency/privacy/SBOM/release policies, 954 Swift tests,
both platform cross-compiles, and three no-network/no-prompt probes.

## Deliberate limits

The coordinator's caller must be the future designated-requirement-authenticated
local administration path after explicit destructive confirmation. This is not
signed XPC, final Keychain access-group, Secure Enclave, first-unlock, physical
key deletion, UI copy, or live listener-restart evidence. Those remain final
identity and physical gates.
