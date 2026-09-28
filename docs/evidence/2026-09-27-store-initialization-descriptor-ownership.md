# Failed storage initialization owns its descriptor once

The selected-stream final validation stopped with a Swift Testing target failure
and no assertion in `CompanionAgentPlatformTests`. The owned test helper's
2026-09-27 17:50:14 crash report identifies `EXC_GUARD`, a CLOSE violation, in
`AtomicFileMacUpdateAgentReactivationStoreV0.deinit`, reached through the throwing
initializer in `updateReceiptStoreRejectsSymlinksAndUnexpectedEntries`.

The source assigned its lock descriptor before directory validation. The catch
closed it, then the fully initialized actor's destructor closed it again. Under
concurrent descriptor reuse, that second close can affect an unrelated resource;
the observed descriptor was guarded. The isolated 131-test group passed before
repair, so a passing retry alone did not resolve the source defect.

The update receipt store and the remote access intent store had the same pattern.
Both now keep the opened descriptor local during validation and transfer it to
the actor only on success. Validation closures use local directory/destination
values and do not require early full actor initialization. A throwing initializer
has one local cleanup owner; a successful actor has one destructor cleanup owner.
Storage validation, canonical records, file modes, locks, persistence and remote
authorization semantics are unchanged. No installed storage or real database
was opened or modified.

The complete 131-test Agent platform group passes after repair, including unsafe
storage rejection, concurrent insertion and store reopening. Private log:
`/private/tmp/maccompanion-agent-platform-descriptor-fix-20260927.log`, SHA-256
`826711ea519455cfa31838e3654dcdb74269b899a6e2090110611affc78f9ce1`.
Failed full validation log:
`/private/tmp/maccompanion-selected-stream-final-validation-20260927.log`, SHA-256
`b8caaa8750397e0eb2580d00e4a99e4e887f339c13139fa98af83c98487c8546`.

Final required full stable `bash scripts/validate.sh` after repair passes with
114 indexed fixtures, all package/lab tests and platform builds, including all
131 Agent platform tests. Private log:
`/private/tmp/maccompanion-selected-stream-storage-final-validation-20260927.log`.
SHA-256 `718ff617c47c45aa9abb5e99d03fad7aebf9f92ac3d80f0804d5ba17345863e2`.
