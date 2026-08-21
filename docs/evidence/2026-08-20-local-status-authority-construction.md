# Coherent Agent local-status authority evidence — 2026-08-20

Status: bundle-independent construction and test evidence under Xcode 27 beta.
This is not authenticated XPC, a signed Agent/menu app, a physical route
monitor, or release evidence.

`AgentLocalStatusAuthorityV1` owns one content-free cached status version. The
snapshot path does not independently read lifecycle, networking, persistence,
security, or provider authorities, so it cannot assemble fields from different
published Agent versions. Accepted updates are atomic at the status actor; a
rejected count, warning, or read time preserves both prior facts and the next
diagnostic sequence.

The construction now has typed product adapters for:

- completed lifecycle transitions from the existing Agent lifecycle owner;
- exact listener state, `routeUnavailable`, and a zero-or-one active-primary
  count from the sealed Network listener service;
- active non-revoked paired-device count from `SQLiteSecurityStore`, exposed
  through a count-only protocol rather than device records;
- immutable live-provider count from `AgentCapabilityAuthorityV1`, exposed
  without provider IDs, names, versions, or errors;
- emergency deny-latch health, with active mapped to `denyLatched` and corrupt
  or unreadable state mapped to `storageUnavailable`; and
- detailed-audit producer health as only `auditHistoryDegraded`.

Route kinds now arrive through a separate generation-fenced, freshness-bounded
[route authority](2026-08-20-local-route-monitor-authority.md). It does not
infer them from local addresses, listener endpoints, paired identities, or
provider data. The v0.1 product status narrows paired devices and active primary
sessions to one each and providers to 128. A storage failure changes only the
closed security posture and warning while preserving the last inventory.

Focused tests prove unique sequences across 32 concurrent readers, no mutation
or sequence consumption after invalid updates, exact derived-warning sets,
network-field ownership, bounded inventory publication, sanitized storage
failure, corruption fail-closed behavior, real SQLite/capability-authority
composition, lifecycle publication only after a valid completed transition,
and audit-health projection. The SQLite persistence tests also prove active
paired count changes from zero to one after pairing and back to zero after
durable host-recovery revocation.

The public repository gate passed:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/maccompanion-swiftpm-cache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1 \
bash scripts/validate.sh
```

That run validated 54 indexed fixtures, all 687 Swift tests including 74
`CompanionAgent` tests, the macOS Network and Mac UI targets, iOS Simulator
client-platform and client-UI targets, all three no-network experiment builds,
and `git diff --check`. User SwiftPM cache warnings were expected in the
restricted environment. Acceptance remains gated on stable Xcode 26.6, final
signed identities, authenticated XPC peer admission, and physical route and
lifecycle evidence.
