# SQLite storage-path hardening evidence

Date: 2026-08-21

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

Both `SQLiteSecurityStore` and `SQLiteBoundedAuditStoreV0` now cross one shared
filesystem boundary before SQLite receives a path.

The boundary requires an absolute path and an existing parent owned by the
effective user with owner read/write/search permission and no group/other write
permission. It resolves that already-validated parent once with `realpath` so
macOS system aliases such as `/var` do not weaken the subsequent no-follow
open. The final database component is never resolved through a symlink.

An absent database is created first with `O_EXCL | O_NOFOLLOW`, forced to 0600,
and verified through `fstat`. An existing database must already be one
owner-owned, single-link regular file with exact 0600 permissions. Existing
WAL, shared-memory, and rollback-journal sidecars must satisfy the same
contract before open. SQLite then receives the canonical path with
`SQLITE_OPEN_NOFOLLOW`; database and any live sidecars are revalidated after
configuration and migration.

Unexpected modes, ownership, file types, link counts, writable parent
directories, final database symlinks, and pre-planted sidecar symlinks fail as
closed store-specific `insecureStoragePath` errors. The store does not chmod an
unexpected existing directory or database on the caller's behalf.

## Proof

Two focused tests cover both stores. They prove secure creation from a missing
database, exact 0600 database/WAL/SHM modes after real writes, a 0700 dedicated
test directory, rejection of a 0644 database, rejection of a group/other
writable parent, rejection of final database symlinks, rejection of a
pre-planted WAL symlink, and correct store-specific error mapping. The complete
63-test persistence target also proves that schema migrations, corrupt/future
database rejection, pager-full recovery, and all existing transaction behavior
remain intact.

## Reproduction

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/maccompanion-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/maccompanion-swiftpm-cache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --disable-sandbox \
  --package-path Packages/MacCompanionKit \
  --filter CompanionPersistenceTests
```

## Result

All 63 `CompanionPersistenceTests` passed. The repository-wide hardened gate
subsequently passed with 63 authoritative fixtures, 764 repository files, and
1,034 Swift tests.

## Boundary not claimed

The final Agent composition must create its dedicated storage directory as
0700 and prove the installed paths, owner, sandbox/container policy, backup
exclusion where required, and Data Protection behavior in signed bundles. This
construction does not claim resistance to the already-authorized local account
after compromise, ACL policy beyond the enforced ownership/mode boundary,
physical full-volume behavior, or torn-write recovery.
