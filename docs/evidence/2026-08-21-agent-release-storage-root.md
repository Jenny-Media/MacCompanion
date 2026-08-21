# Agent release storage root evidence

Date: 2026-08-21

Status: bundle-independent construction passed; permanent Agent activation is
still intentionally deferred.

## Result

The public `MacAgentReleaseStorageV1.systemDefault()` release factory resolves
one canonical per-user Application Support root:

```text
media.jenny.maccompanion/Agent/v1
```

The composition creates and retains the exact three durable authorities needed
by the required-audit Agent bootstrap:

- `security-v1.sqlite3`, limited to 16,384 SQLite pages;
- `audit-v1.sqlite3`, limited to 8,192 SQLite pages; and
- `emergency-deny-v1.latch`, using the preallocated two-slot deny record.

The factory does not return the retained raw stores or latch. It returns their
`AgentRequiredAuditCompositionV0` plus non-secret diagnostic paths. This is an
API composition boundary, not a sandbox against other trusted same-UID code,
which can independently name per-user files.

## Path and recovery boundary

- Production callers can use only the user-domain system-default factory with
  its fixed page ceilings. A package-only initializer supplies temporary roots,
  quota variants, and a construction-race hook to tests.
- Existing base and product directories must be real, owner-controlled
  directories. The versioned product components are exact mode `0700`.
- Symlinked base, nested-directory, database, WAL, shared-memory, journal, and
  latch paths fail closed through the storage composition and existing store
  validators.
- Security, audit, and latch files are exact mode `0600`; the composition
  revalidates the root device/inode and every primary artifact after all three
  objects exist.
- Each SQLite handle must still be bound to its approved main-file path after
  construction. The retained latch descriptor must still match its visible
  path before and after every coherently locked read or transaction.
- Emergency-latch reads take a shared file lock and the complete
  read-modify-write-fsync-verify transaction takes an exclusive file lock, so
  separate actors and processes cannot derive and overwrite the same
  generation.
- Construction never deletes visible state after an error. A later launch must
  inspect and recover the same path instead of silently creating a second
  security authority.
- Reopening preserves an already-active emergency deny latch.

The covered `stat`/`lstat` use is now included in the privacy-manifest source
inventory. It is macOS-only and does not become reachable from the iOS target
closure.

## Verification

Ten focused tests pass:

- private root and artifact construction;
- exact-authority reopen with active-latch preservation;
- symlinked base rejection;
- broad existing-directory rejection;
- nested-component symlink rejection;
- preexisting database-symlink rejection;
- post-open security and audit SQLite pathname-substitution rejection;
- post-open latch pathname-substitution rejection; and
- 100 concurrent updates through two independently opened latch actors with no
  lost generations.

The permanent-target validator scans every Swift source in both the Agent and
menu-app target. Two injected negative fixtures prove that either target would
fail validation if it instantiated `MacAgentReleaseStorageV1` before the final
bootstrap composition is ready.

Final gate execution also exposed a pre-existing zero-delay race in the
capture/encode platform-probe test seam: an immediate mock terminal fact was
queued in an untracked task and could lose to the injected timeout. The
injected graph callback is now async and the mock awaits immediate publication
before returning from `start()`. The production synchronous framework callback
remains task-bridged, so live terminal ordering remains part of physical
capture evidence. The eight-probe suite then passed 20 consecutive no-rebuild
runs.

The complete repository gate passes across 892 files, 291 Swift source files,
1,217 unique MacCompanionKit Swift tests, 8 platform-probe tests, all policy
validators, and every supported cross-build. The privacy validator records 14
covered macOS source records. An unsigned Xcode 27 beta Mac application build also succeeds.

## Remaining boundary

This proves stable storage construction, not host-identity/Keychain bootstrap,
process-start recovery, live `SMAppService` registration, or signed local XPC.
The permanent Agent remains authentication-only and the menu app remains
unavailable until those dependencies are composed and verified together.
