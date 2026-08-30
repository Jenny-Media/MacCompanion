# Signed Act cancellation and interrupted-operation recovery — 2026-08-28

The pre-physical goal remains active. This checkpoint extends the prior
52-case signed Agent/XPC matrix to 55 cases. No installed product, production
Keychain, TCC, system audio, Simulator or physical iPhone was used.

## Reproduced defect and fix

The primary frame pump waited for a provider's complete result before reading
another command. An authenticated operation status request therefore timed out
while an Act operation was still running; cancellation could not reach it on the
same primary. This was reproduced with the real signed Agent/network composition
and a test-only wrapper pausing native-provider result delivery after its fake
audio effect. It was not inferred from a mock-only test.

The pump now retains at most 31 authenticated invoke/approve response handlers,
leaving ordinary commands serialized and responsive. Authentication stays
sequential, all response writes stay serialized, and excess execution closes
the connection rather than building an unbounded queue. Terminal teardown
cancels retained response tasks and discards late results. It does not claim
that task cancellation undoes an effect. Semantic revalidation checks the same
ready connection after suspension; authenticated liveness cannot regress when
revalidation finishes out of order.

The normative primary-session profile and indexed
`host-primary-act-concurrency-v0.1.json` fixture were added before changing the
production scheduler. Wire envelopes, signatures and operation digests did not
change. Unit tests cover same-primary status/cancel, execution overflow,
late-result suppression, exactly-once close, fixture bounds, and revalidation
across closure or out-of-order completion.

## New signed journeys

1. A raw test client uses genuine certificate pinning and application
   authentication but bypasses its UI/catalog guard. The Agent denies ungranted
   invoke, leaves zero durable operations/grants, and calls no provider. Unknown
   status/cancel targets return the same opaque not-found error. This does not
   claim a second foreign device's operation was tested.
2. After a real signed Act grant, the native provider runs with the in-memory
   audio controller. A Debug-only wrapper pauses result delivery. The same
   primary returns running status, then cancelRequested twice. The provider's
   cancellation hook runs once and declines cancellation; releasing the result
   returns succeeded rather than falsely claiming cancelled.
3. The runner kills only its UUID-scoped Agent after that test effect and while
   SQLite still says running. The client observes actual primary termination.
   On restart, real startup reconciliation records outcomeUnknown. Status and
   exact invoke replay return that state with no new provider execution.

The pause is bounded to twelve seconds and returns unknown on timeout or task
cancellation. It is an explicit result-delivery fault, not a simulated hardware
mute or proof of an external provider being terminated. It lives only in the
experiment executable, outside the release graph. The raw client changes no
production authentication path.

## Evidence

Three consecutive final signed matrices passed **55/55**, each with verified
cleanup and the identical current-source fingerprint
`b18c8a76a388659ead319bdd2f4325e9dcc6aea6b5f38d3dc48f9eb74acea7fd`:

- `/private/tmp/maccompanion-agent-xpc-evidence.jocilthd/report.json` — 51.688s.
- `/private/tmp/maccompanion-agent-xpc-evidence.c7pc3_5i/report.json` — 43.532s.
- `/private/tmp/maccompanion-agent-xpc-evidence.f6sb9pxq/report.json` — 44.767s.

The runner fingerprints package sources, experiment sources/manifests and the
runner itself, including uncommitted contents. An independent post-run check
compared all 55 exact case names and the live fingerprint, confirmed every UUID
job absent through `launchctl print`, and verified temporary state, helper
binaries, plist and helper processes absent. Evidence logs remain in private
temporary directories; disposable state/keys/helper copies were removed.

Commands (all with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`):

```sh
python3 scripts/verify_agent_xpc.py
swift test --package-path Packages/MacCompanionKit --filter 'primaryConcurrentRevalidation|hostPump'
bash scripts/validate.sh
swift build --package-path Packages/MacCompanionKit -c release --target CompanionAgentApplicationPlatform
```

- Full `validate.sh`: exit 0, **1,769 tests across 42 runners**, 78 indexed JSON
  fixtures and all policy/platform/source/C checks. Log:
  `/private/tmp/maccompanion-act-concurrency-full-validation.log`.
- Release target build: exit 0. Log:
  `/private/tmp/maccompanion-act-concurrency-release.log`.
- Defined-symbol inspection with `nm -U` on the same eight startup/transport/
  listener/renewal object files as the previous checkpoint found **411 Debug
  test-seam symbols and zero Release test-seam symbols**. Matcher:
  `Isolated|isolatedTestID|isolatedLoopback|makeUnstartedLoopbackListener|startForInstalledTestRuntime`.
  The raw client and paused provider are experiment-only types, not dependencies
  of a Release target; source-graph guards also pass.
- `git diff --check` passes. Post-checkpoint edits are documentation only.

Reproduction and development records (not final green evidence):

- `/private/tmp/maccompanion-agent-xpc-evidence.q122wycc/report.json`: 53/53
  before the paused-provider cases; demonstrated the remote host denial.
- `/private/tmp/maccompanion-agent-xpc-evidence.syv9jw6e/report.json`: harness
  compilation failed on a missing `try`; corrected before runtime testing.
- `/private/tmp/maccompanion-agent-xpc-evidence.9_tsvexm/report.json`: 44 earlier
  cases passed, then cancellation journey failed. Client observed the test
  effect, then status timed out; Agent log confirms paused result delivery.
  Cleanup passed. This is the pre-fix runtime reproduction.
- `/private/tmp/maccompanion-act-concurrency-tests.log`: 10 focused pump tests
  passed after the fix.
- `/private/tmp/maccompanion-act-fences-tests.log`: 11 focused tests across two
  runners passed, including two parameterized session-revalidation cases.

## Remaining work

Broader provider/lifecycle and storage-fault paths, visible Act administration,
other administration operations and combined signed-Agent Simulator UI/media/
input remain required. Earlier startup/handshake stalls, UX/performance,
compatibility, real elapsed-duration soak and final consolidated physical
acceptance preparation are not closed by this checkpoint. This is provisional
Xcode 27 beta evidence, not stable-toolchain or physical acceptance.
