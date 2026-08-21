# Durable lifecycle intent and restart reconciliation evidence — 2026-08-21

## Claim

Mac Companion now has a final-identity-neutral durable source of truth for the
user's remote-access enabled choice and a startup boundary that restores only
that intent, never stale process readiness.

`AtomicFileMacRemoteAccessIntentStoreV1` stores one strict canonical record:
schema version, positive safe-integer revision, desired-enabled Boolean, random
command UUID, and safe-integer wall time. It bounds the record to 1,024 bytes,
uses a 0700 non-symlink directory, 0600 no-follow files, a process-shared lock,
expected-revision compare-and-set, file `fsync`, same-directory rename, and
directory `fsync`. Unknown directory state and noncanonical, broadened, unsafe,
or wrongly permissioned records fail closed. A post-rename failure is resolved
only through exact read-back.

`MacDashboardLifecycleProductAdapterV1` records desired intent before live
mutation. Enable keeps durable enabled intent across registration or process
start failure so retry/restart can converge it. Disable records disabled first,
then completes remote teardown, then removes both roles. The startup loader
defaults an absent record to disabled and constructs fresh `starting` process
states only for enabled eligible sessions, with stopped states otherwise; it
never restores `ready`. `reconcileAfterRestart()` converges the reducer and roles before a final
target may expose readiness; an enabled logged-out state registers recovery
roles but does not request process starts.

## Automated evidence

Thirteen new tests prove:

- strict canonical encoding, exact decoding, and unknown-field rejection;
- safe-integer revision and time bounds;
- insert, idempotent exact replay, revision-fenced replacement, and reopen;
- stale-revision rejection without mutation;
- pre-rename failure publishing no record;
- post-rename failure converging through exact read-back;
- rejection of unknown visible directory state;
- absent-record safe-disabled startup and no restoration of ready processes;
- persisted enable and disable convergence after restart;
- absent-record reconciliation disabling an inconsistent live state;
- enabled logged-out registration without process-start requests; and
- durable enabled intent surviving partial registration failure.

The focused `CompanionAgentPlatformTests` target passes all 26 tests. The final
hardened unsigned gate passed with 63 indexed JSON fixtures, 785 repository
files, 34 historical blob paths, 14 repository-material fixtures, 4 package
manifests, 12 dependency-policy fixtures, 3 privacy manifests, 12 privacy
fixtures, 11 required-reason API source records, 10 SBOM fixtures, 16 release-
evidence fixtures, 1,098 listed Swift tests, both platform cross-compiles, and
all three construction probes. Only the expected read-only user SwiftPM cache
warnings appeared.

## Deliberate limits

The containing app still must choose its final Application Support location and
instantiate the exact Agent/menu `SMAppService` objects and process-start
adapter. This evidence does not claim signed XPC authentication, process
observation, final labels, login-item approval UX, or physical restart/update/
uninstall behavior. Those remain final-identity and physical-system gates.
