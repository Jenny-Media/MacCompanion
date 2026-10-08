# Native reliability implementation and acceptance

This is local development evidence. No public release, production admission or
physical acceptance follows from these results. Pairing/signing identities are
preserved; no credentials, pictures or typed content belong in this document.

## Findings

- The installed full-reconnection candidate completed 22 normal Simulator
  switches, with real Mac capture and synthetic final input. Median latency was
  3,047 ms, p95 4,658 ms; native preparation accounted for a 3,060 ms stage p95.
  Recreating enrollment, host and transport explains most of the measured cost.
- The retained-connection candidate connects the normal client, Agent, Mac,
  capture child and encoder. Capture/input pause precedes fresh logical proof;
  only the new independently decodable frame epoch admits input. Ordinary
  switches preserve the host, TLS identity, transport and encoded canvas.
- Its first live run failed before video because the Desktop scope compared
  native Retina pixels with Core Graphics logical dimensions. The native
  display mode supplies the correct 5120×2134 pixels for 2560×1067 points.
  Strict native geometry and lifecycle regressions pass after that repair.
- The second run passed geometry but cold native encoder startup occupied the
  serialized XPC lane for four seconds. Receiver expiry invalidated the menu,
  ended Control and closed media. Polled activation now leaves that lane free
  for execution-lease renewals. One worker has a 15-second budget capped by the
  original approval; individual XPC deadlines remain four/five seconds.
- The third run kept the XPC lane alive but exhausted an internal readiness
  attempt count after 7,181 ms. Readiness now uses the same elapsed startup
  budget. Its encoder log stopped after H.264 while testing HEVC: the selected
  capture bridge retained a stopped handoff, suppressing every later sample.
  Last-stream cleanup now joins that handoff and releases the exact slot before
  waking the encoder probe. A native bridge regression verifies pending-work
  joining, a fresh next owner and fencing of a stale stream terminal.
- The Mac restarted during the fourth smoke run. Its temporary products and
  logs, and earlier raw `/private/tmp` evidence, are no longer available. The
  earlier ledger is a recorded summary, not fresh readback of those reports;
  the interrupted fourth run has no verified outcome. Pinned sources and
  dependencies are being reconstructed for a new source-bound live run.

- The reconstructed candidate started native video successfully (1,097 ms
  host activation), then failed its first Shared Display switch. Host handoff
  took 148 ms and the transport was retained, but no replacement was presented.
  The pinned Moonlight RTP depacketizer stripped our prefix SEI marker before
  the adapter could validate its epoch. The initial stream does not require
  that replacement marker, explaining its successful startup. The encoder also
  logged an IDR-request warning; that warning alone did not terminate encoding.
- An old input-admission polling callback completed the new transition trace
  after just 2 ms while input draining yielded. The normal product now requires
  a true admission callback after the replacement's first-frame stage and after
  the surface-selection fence has cleared.
- The embedded engine now patches a disposable copy of the exact pinned
  depacketizer to preserve selected-surface markers on ordinary and IDR paths.
  Its upstream submodule stays clean. Unrelated prefixes remain stripped;
  duplicate markers remain visible for rejection. Actual parser regressions
  exercise both H.264 and HEVC plus parameter-set ordering. Native capture,
  handoff, epoch and bridge regressions passed. The live retest passed all four
  retained display/window switches and all six advancing presentations, fresh
  input and cleanup. Transition median was 837 ms, p95/max 2,121 ms in this
  short Simulator run. Some first new-epoch keyframes arrive while selection is
  fenced; the client now requests another keyframe after epoch configuration
  through the same native transport. This closes that gap without reconnecting.
  Its first 200-switch campaign failed after 25 successful retained switches:
  transition median 919 ms, p95 1,331 ms, maximum 1,599 ms. The selected capture
  became invalid, native video disconnected, and media/primary teardown
  cancelled Desktop recovery. Concurrent desktop navigation is a possible
  contributor to that scope loss; its cause is not established.
- A controlled retest failed during the twentieth switch after 19 successes.
  Median was 1,076 ms, p95/maximum 5,577 ms. The managed handoff failed while
  the watcher reported both permit and selected capture current. Both failed
  campaigns completed key cleanup and restored Simulator state. Neither meets
  the repeated-switch gate. All failures stay in the ledger.
- A deterministic parent regression then reproduced `invalidRecord` when an
  atomic receipt rename unlinked the reader's already-open old inode. The child
  also republished identical receipts on each 20 ms tick, increasing exposure
  to that race. Both readers now discard a replaced snapshot and open the new
  safe record within the unchanged deadline; same-inode mutations, missing or
  unsafe replacements remain failures. Identical safe acknowledgements keep
  their inode. Four parent tests and the real native read-interleaving,
  lifecycle, unsafe-file, bridge, epoch and depacketizer regressions pass.
  The repaired source has been rebuilt for a new live campaign; these tests
  do not establish that every previously observed live failure is repaired.
- Repeated keyframe callbacks previously inflated presentation counts. The
  report now counts distinct presentation generations and records callback
  counts separately. Missing generations, unmatched or out-of-order progress,
  and stalls still fail. Six reporting regression tests pass. The disposable
  target's two-hour backstop now exceeds the bounded 200-switch/long-session
  campaign instead of terminating after twenty minutes.
- The atomic-read repair's controlled 200-switch retest failed after 101
  successful retained switches, during the next selection. Median was 733 ms,
  p95 1,206 ms and maximum 1,609 ms. One host factory, native launch and video
  start served all completed switches. All 102 distinct presentations advanced;
  the failed selection never reached fresh video. Native video disconnected
  with code -1 before the selection fence. The retained owner then rejected
  replacement, and product teardown cancelled the attempted Desktop recovery.
  Capture scope 4 was also reported; the initiating engine/capture cause is
  not established. No preceding sleep event was found. Cleanup, key cleanup
  and Simulator restoration passed. This run still fails acceptance.
- Capability probing suspends before choosing retained replacement. The client
  now rechecks renderer presentation/input state after that await and yields
  to an already-owned recovery. This addresses the observed failed-owner
  transfer; it does not prove the initiating disconnect is repaired. The native
  engine now classifies exact pinned terminal format literals into fixed numeric
  reasons, without formatting or retaining arguments, endpoints or input.
  Native engine/adapter tests pass; the updated normal live journey is pending.
- The diagnostic collector now keeps a read-only open descriptor across atomic
  application-log rotation, drains the old tail and then opens the new safe
  inode. Four regressions cover exact ordering, partial lines, unsafe/mutated
  files and bounded output. The subsequent resize journey passed six advancing
  presentations, fresh input and automatic Desktop recovery under the original
  Control session. Its complete journal captured 495,813 bytes with no rotations.
- The previous retained candidate was installed on the iPhone 18 Pro Max and
  Mac. macOS rejected the new Agent at execution with AMFI error -413,
  `No matching profile found`, despite successful deep signature verification.
  Embedding the existing macOS development profile, verified against this
  Mac's provisioning UDID, current certificate and unchanged entitlements,
  restored launch. The installed Agent and main app are running. Pairing,
  Keychain groups, designated requirements and OS permissions were preserved.
  Native UI automation currently closes its pipe when selecting Mac Companion;
  process/sample evidence does not substitute for a visible dashboard check.
  iPhone Mirroring for the affected phone still requires the user's first-time
  setup, so physical playback and latency have not been verified.

## Local run ledger

| Run | Outcome | Boundary |
| --- | --- | --- |
| `maccompanion-reliability-window-soak-v4-20261003` | Passed 22 switches / 24 presentations | Previous full-reconnection path; normal Simulator, synthetic final input |
| `maccompanion-reliability-background-v4-20261003` | Passed UI recovery journey | Previous candidate; cancelled-transition trace defect repaired subsequently |
| `maccompanion-retained-switch-smoke-20261003` | Failed initial video | Retina geometry rejection; no successful retained switches |
| `maccompanion-retained-switch-smoke-v2-20261003` | Failed initial startup | Four-second XPC receiver expiry; no successful retained switches |
| `maccompanion-retained-switch-smoke-v3-20261003` | Failed initial startup | Internal readiness attempt count and stopped encoder-probe handoff; no successful retained switches |
| `maccompanion-retained-switch-smoke-v4-20261003` | Interrupted; outcome unverified | Mac restart; raw temporary evidence unavailable |
| `maccompanion-retained-reliability-validation-v3-20261003.log` | Passed | Stable Xcode 27.0, 125 fixtures, packages/platform/native; before polled activation repair |
| `maccompanion-reliability-resume-selected-capture-tests-v2-20261003.log` | Passed | Stable Xcode; native capture/context/handoff and actual pinned Sunshine bridge, synthetic samples and inert streams |
| `maccompanion-reliability-resume-selected-capture-tests-v3-20261003.log` | Passed | Final explicit probe-retirement regression output against pinned upstream |
| `maccompanion-reliability-resume-validation-20261003.log` | Passed | Stable Xcode 27.0, 125 indexed fixtures, package/platform/native checks; before rebuilt host catalog |
| `maccompanion-reliability-resume-validation-final-20261003.log` | Passed | Stable Xcode, final host catalog and repaired clean source fetch |
| `maccompanion-reliability-resume-native-sdk-simulator-20261003.log` | Passed build and lifecycle tests | Source-bound native client; no physical acceptance |
| `maccompanion-reliability-resume-normal-simulator-20261003` | Passed build | Normal app, native frameworks verified, no reference probe |
| `maccompanion-reliability-resume-staged-mac-20261003.json` | Passed staging and deep signature | Existing app/Agent entitlements and designated requirements preserved; not installed |
| `maccompanion-reliability-depacketizer-switch-smoke-20261003` | Passed 4 retained switches / 6 advancing presentations | Real capture, normal Simulator, synthetic final input; before replacement keyframe request |
| `maccompanion-reliability-retained-200-switches-20261003` | Failed after 25 retained switches; 1 cancelled recovery | 200-switch target not completed; scope loss, media/primary teardown; cleanup restored |
| `maccompanion-reliability-controlled-200-switches-20261003` | Failed after 19 retained switches; next transition failed | Handoff failure with current permit/capture; cleanup restored |
| `maccompanion-reliability-receipt-race-before-repair-20261003.log` | Failed as expected | Deterministic atomic rename reproduced parent `invalidRecord` |
| `maccompanion-reliability-receipt-race-after-repair-20261003.log` | Passed 4 tests | Exact predecessor, atomic rename, unsafe replacements, same-inode mutation, expiry and epoch |
| `maccompanion-reliability-atomic-native-regressions-20261003.log` | Passed | Actual command-read interleaving plus capture/context/handoff, pinned bridge and depacketizer |
| `maccompanion-reliability-profile-repaired-mac-install-20261003.json` | Installed; Agent launch restored | Existing compatible macOS development profile; no pairing reset; dashboard UI check pending |
| `maccompanion-reliability-atomic-200-switches-20261003` | Failed after 101 retained switches; next transition failed | Native disconnect before fence; cause unresolved; cleanup restored |
| `maccompanion-reliability-atomic-window-resize-20261003` | Passed 6 advancing presentations and same-Control Desktop recovery | Real capture, normal Simulator, synthetic final input; complete diagnostic journal |
| `maccompanion-reliability-terminal-sdk-simulator-v2-20261004.log` | Passed SDK build and 23 engine/adapter tests | Fixed terminal classifications and current client lifecycle source; not physical acceptance |
| `maccompanion-reliability-terminal-final-validation-20261004.log` | Passed | Required stable Xcode 27.0 validation, 125 indexed fixtures, package/platform/native checks |
| `maccompanion-reliability-terminal-continuity-smoke-20261004` | Passed 4 retained switches / 6 advancing presentations | 2 Control sessions, 2 host/video starts; cleanup and complete journal verified |
| `maccompanion-reliability-terminal-background-20261004` | Passed 6 advancing presentations | Background input fencing, fresh foreground enrollment and primary network-loss recovery; cleanup/journal verified |
| `maccompanion-reliability-terminal-desktop-space-continuity-20261004` | Passed one-minute Desktop video/input continuity | Mission Control entry/exit attempted; no verified Space switch, so Spaces acceptance remains pending |
| `maccompanion-reliability-terminal-200-switches-20261004` | Passed 202 retained switches / 204 advancing presentations | Exactly 2 host/video starts for 2 Control sessions; no failed/cancelled/incomplete transitions; cleanup/journal verified |
| `maccompanion-reliability-terminal-mac-install-20261004.json` | Installed; main app and Agent launched | Existing entitlements, designated requirements and compatible profile; rollback bundle retained |
| `maccompanion-reliability-terminal-ios-install-evidence-20261004.json` | Installed on iPhone 18 Pro Max; process launched | Existing app updated, no pairing reset; physical UI/playback unverified |
| `maccompanion-reliability-preflight-before-repair-tests-20261004.log` | Failed as expected: 2 methods / 6 assertions | Deterministic suspended capability reply admitted stale recovery/cancelled work; subsequent Xcode diagnostic collection interrupted |
| `maccompanion-reliability-preflight-after-repair-tests-20261004.log` | Passed 27 tests | 4 deterministic preflight tests plus native engine/adapter lifecycle; current final source |
| `maccompanion-reliability-preflight-final-validation-20261004.log` | Passed | Required stable Xcode 27.0 validation, 125 indexed fixtures and package/platform/native checks |
| `maccompanion-reliability-preflight-resize-20261004` | Passed 6 advancing presentations and same-Control Desktop recovery | Final source; fixed native terminal reason identifies server notification; cleanup/journal verified |
| `maccompanion-reliability-preflight-background-20261004` | Passed 6 advancing presentations | Final source; background input fencing, fresh foreground enrollment and primary connection-loss recovery; cleanup/journal verified |
| `maccompanion-reliability-preflight-200-switches-20261004` | Failed evidence gate; UI journey passed | Original journal lost the relocated container's new log at rotation; host retained 202 switches; cleanup restored |
| `maccompanion-reliability-preflight-supplementary-assessment-20261004` | Diagnostic only; gate not accepted | Separate read-only tail reconstructs 202 complete switches / 204 advancing presentations, 2 host/video starts; original failure preserved |
| `maccompanion-reliability-relocated-journal-validation-20261004.log` | Passed stable validation | Collector repair, 125 indexed fixtures and platform/native checks |
| `maccompanion-reliability-relocated-journal-smoke-20261004` | Passed 4 retained switches / 6 advancing presentations | Confirms 1 actual Simulator container relocation, complete journal, cleanup and restoration |
| `maccompanion-reliability-preflight-window-closure-20261004` | Passed 6 advancing presentations | Selected-window closure recovers Desktop/input under the same Control; complete journal and cleanup |
| `maccompanion-reliability-preflight-window-move-20261004` | Passed 6 advancing presentations | Selected-window movement recovers Desktop/input under the same Control; complete journal and cleanup |
| `maccompanion-reliability-final-evidence-validation-20261004.log` | Passed stable validation | Final collector/window-loss harness, 125 indexed fixtures and platform/native checks |
| `maccompanion-reliability-preflight-desktop-spaces-v2-20261004` | Passed one-minute Desktop continuity and observed full-screen entry | Client visibly showed the Finder full-screen Space; exit restored after stream Stop; not a full round-trip acceptance |
| `maccompanion-reliability-preflight-desktop-spaces-v3-20261004` | Passed one-minute Desktop continuity with observed full-screen Space round trip | Before/full-screen/returned Desktop video visible in browser mirror; one presentation; queued frames before/after both UI actions; Finder restored |
| `maccompanion-reliability-preflight-mac-install-20261004.json` | Installed; app/Agent launched | Final source, existing identity/profile preserved; rollback retained |
| `maccompanion-reliability-preflight-ios-install-evidence-20261004.json` | Installed on iPhone 18 Pro Max; process launched | Final source, existing app updated; no pairing reset; physical UI/playback unverified |

New reports and content-free diagnostics are private local artifacts under
`/private/tmp`. The earlier ledger recorded cleanup and Simulator restoration
for the first three failed live runs. They remain in the reliability denominator
even though the raw temporary evidence did not survive the Mac restart.

The first reconstructed candidate source fingerprint was
`1512324b9ea7d5c2851e64a7e44d6032655ac20c43bea68016c37b7c7330f29f`.
Its source-built host hash is
`72d088503cd1a3fee6151ec857b53ac2131f5484f899f0488217f3a005574c6f`;
the signed normal-Mac host catalog is
`b79b5ba5d3842e0d573b200729ee2e9d13a70863d50a25c49660d38469654146`.
The clean fetch now restores and verifies the already-pinned `nanors` transport
submodule, whose absence initially blocked this rebuild. No source pin changed.

The installed pre-atomic-repair candidate has source fingerprint
`a4ff696d88204ac5032aba689f21b08f118724daa7acc5bc8b98797d64db699d`
and host catalog
`154682e0c847670323ac8ab8a3e2e37ba91a89fac4577fa4a246f7b8931fc5a7`.
The rebuilt atomic-repair candidate has source fingerprint
`90f7e7800a0d53326a204a6b10c6f71c2d430668386b7c7e1bcb9080f560dce3`,
source-built host hash
`160c81fab4828bcc5b19901188063e549bd25ec7646e9ba29330899f56bb3e79`
and signed host catalog
`8260de888661cdd7eba49506510ecf438ee8b03559f7c5e0a111bf831f34c21e`.
The source-built host, both embedded iOS SDKs, normal Mac app and normal
device/Simulator apps build successfully. Required full stable Xcode validation
passes with 125 indexed fixtures. Both signed updates are staged, with existing
identities and compatible profiles verified. Its 200-switch retest failed after
101 successes. That candidate was superseded before installation.
The diagnostic/preflight candidate has source fingerprint
`7b676535b54c84c99a6f4bb0fb3751f63fd0bd0465b8a3419e3e767140ffec36`.
Both native SDKs and normal Mac/device/Simulator apps build successfully. The
host sources/package are unchanged. Required final stable validation passes.
The short continuity journey passed four switches with median 660 ms and
p95/maximum 1,225 ms; six distinct presentations advanced across two Control
sessions, with exactly two host/video starts and four retained switches.
Its complete journal, key cleanup and Simulator restoration passed.
The matching development updates are installed on the Mac and iPhone 18 Pro Max.
The Mac app and correctly profiled Agent are running; the iPhone process launch
succeeded. Existing identities, profiles and pairing data were preserved.
Mac dashboard UI automation still closes its pipe. iPhone Mirroring still shows
first-time setup. Neither process launch establishes visible UI or playback.
The background/network journey also passes six advancing presentations,
background input fencing, fresh foreground enrollment, primary connection-loss
recovery and cleanup. Its complete journal captured 524,359 bytes.
One-minute Desktop continuity also passes with ongoing client frames and input.
Mission Control entry/exit did not interrupt video; its automation endpoint
timed out and no actual Space change was verified. This is not a Spaces pass.
The full campaign passed 200 Window/Desktop changes plus two display changes:
202 succeeded, zero failed/cancelled/incomplete/invalid. All 204 distinct
presentations advanced, with zero stalls or invalid progress. Exactly two host
factories, native launches and video starts served two Control sessions; all
202 ordinary switches retained the transport. Median was 691 ms, p95 1,526 ms,
maximum 2,933 ms. Cleanup, key cleanup and Simulator restoration passed. The
complete journal captured 432,867 bytes with no rotations. This is normal
Simulator/real-capture evidence, not a physical latency pass or proof of the
previous initiating disconnect's cause.

Review during that run found a remaining preflight ordering gap: automatic
recovery publishes a busy view while awaiting primary refresh, before reserving
the surface-transition flag. A capability reply can arrive in that interval.
The extracted production preflight reproduced that gap deterministically:
both supported and unsupported replies entered replacement after recovery
reserved the view. Suspended cancellation/owner changes were also admitted.
Two failing test methods recorded six assertion failures; unrelated native
tests passed. Xcode's subsequent diagnostic collector was stopped after the
failure result was preserved, not counted as a clean diagnostic completion.

The final repair revalidates selection ownership after every capability reply,
including an unsupported result, and checks the busy state before fallback.
Recovery can own either path without a stale request ending Control. A renderer
disconnect with no competing recovery still permits the existing replacement
path. Four deterministic tests and all 27 native engine/adapter tests now pass.
Required full stable validation also passes. This source has fingerprint
`8be2e47b1ca4ab43083da62188e8184e33fb4c225b3af45306d225f9d7349450`.
The passing 202-switch campaign above belongs to the preceding installed
diagnostic candidate; it is not attributed to this final source.

Both SDKs and normal Mac/device/Simulator apps now build for that final source.
The resize recovery journey passes all six presentations, restored input and
same-Control Desktop recovery. Its complete journal captured 446,738 bytes;
cleanup and Simulator restoration passed. The terminal reason was the fixed
server-notification classification, without raw engine arguments.
Final signed updates are installed on the Mac and affected iPhone; both Mac
processes run and the phone process launch succeeds. Pairing identities and the
existing compatible profiles were preserved. Final background/network recovery
also passes six advancing presentations, background input fencing, fresh
foreground enrollment and primary connection-loss recovery. Its complete
journal captured 463,329 bytes; cleanup and Simulator restoration passed.
The final-source UI journey completed all 202 switches, but its original report
failed the evidence gate. The diagnostic collector followed its open file after
XCTest relocated the app container, then could not locate the new inode at the
application log's 512 KiB rotation. A deterministic moved-directory/rotation
reproduction also showed the old collector incorrectly reporting completeness.
The repaired collector resolves the current Simulator container after the
cached parent disappears and refuses completeness if the source remains missing.
Six collector regressions and full stable validation pass. The repaired live
smoke confirms one actual app-container relocation and passes all four retained
switches, six advancing presentations, complete journaling and cleanup. Closure
and movement of the selected window each also pass six advancing presentations
and fresh Desktop/input recovery under the same original Control session.
Their journals also record one container relocation; cleanup and restoration pass.

A separate read-only snapshot and supplementary journal preserve the rotated
tail. Their diagnostic assessment shows 202 complete retained switches and
204 advancing presentations, no failed/cancelled/incomplete/invalid transitions,
zero stalls, two native launches/video starts and two host factories. Median is
780 ms, p95 1,126 ms and maximum 1,994 ms. The snapshot remains an exact prefix
of the supplementary log, and both original and supplemental files are retained.
The original failed report is unchanged. This assessment is diagnostic only;
the repaired collector must pass a new source-bound campaign.

Final stable validation passes for the expanded closure/movement harness. A
one-minute Desktop hold also passes with a verified full-screen Space round trip:
CUA invoked Finder's Enter/Exit Full Screen commands; the normal client's
browser-mirrored video showed the full-screen Finder and returned desktop.
Content-free action timestamps fall inside the live stream, with queued frame
progress before and after the round trip. One native presentation served the
entire hold, including continued synthetic input checks. Finder's original
window state, exact test keys, Simulator app/state and preview helper were
restored or cleaned up. This covers full-screen Space entry/exit, not ordinary
cycling between several Desktop Spaces or affected-phone behavior. The first
CLI attempt used incompatible test flags and was rejected before a journey;
its configuration-error log is preserved.

Baseline inventory found native Sunshine `2026.914.233613` on this Mac. The
affected iPhone's normal installed-app inventory contains no Moonlight/Limelight
entry. No performance comparison, baseline installation or new pairing was
performed; the same-hardware comparison remains pending.
The affected phone's content-free app log was exported read-only. Its last event
is at 2026-10-04 04:13:38 UTC, before final-build acceptance. Historical failures
include application-inactive presentation retirement and input/authority loss;
the log contains no final native terminal-source classifications. Those events
do not establish a new-build initiating cause or physical acceptance.

## Backend watcher follow-up, 2026-10-04

The captured long-run termination does not yet have a proven initiating cause.
A separate deterministic production-owner regression proves a backend watcher
race: suspend its original-Control read during `.retaining`, complete retention
under the same operation ID, then resume the old assessment. The old watcher
retires the healthy owner, despite current Control and selected capture. The
before-repair test records two failing assertions; its content-free live OS log
also records the erroneous retirement.

The normative continuity document and indexed fixture now describe local
watcher-generation fencing. Each local phase change creates a new validation
generation. A late assessment can retire only its exact operation, scope and
validation generation. The next bounded watcher iteration still checks current
Control/deadlines. Both deterministic cases pass, including genuine original
Control loss after the stale result. Authentication transcripts, keys and
deadlines are unchanged.

Required full stable validation with 125 indexed fixtures passes. Both native
SDKs and all normal Mac/device/Simulator builds pass for source
`97523786ebaa3cad57a5780259c83547d0ff699dfc51e7180dc2ffdafd935ab9`.
One device SDK attempt failed because parallel builds recreated the same OpenSSL
directory; a sequential retry passed. Signed normal updates are installed with
the existing profile, entitlements, requirements and pairing state preserved.
The new complete 200-switch campaign failed. It recorded 64 completed
transitions: 63 retained switches and one fresh Desktop recovery. The next
retained Window handoff timed out without a new surface presentation and was
cancelled. The first terminal event occurred several seconds after successful
input admission; the managed host watchdog explicitly reported
`controlCurrent=false`, `deadlineCurrent=true`. The fresh Desktop recovery
then succeeded under the same Control, but the following Window handoff did not.
There were two host factories/native starts within that first Control session,
64 retained handoffs and no invalid progress events. Transition median was
931 ms, p95 1,735 ms and maximum 2,828 ms, including the fresh recovery.
The complete journal captured 391,028 bytes and one container relocation.
Cleanup, exact-key cleanup and Simulator restoration passed. This proves the
watcher phase fix alone does not resolve the long-run failure. A diagnostic-only
follow-up classifies original-permit versus selected-capture validation loss;
required stable validation passes, with authentication and checks unchanged.
The unchanged preceding app's
20-switch diagnostic reproduction passed 22 retained switches and 24 advancing
presentations; it did not reproduce or explain the long-run termination.
The affected phone update installed successfully, but iOS refused process launch
because the phone is locked. Installation is not a physical playback result.

## Native child follow-up, 2026-10-04

The diagnostic-only candidate
`a6d62feaf41322989f9393bab50e024628021772d204458334cb4b14a864ea6d`
also fails the complete repeated-switch gate. It completed 151 retained switches
before an unexpected native Control disconnect (`terminal-source-1`, code -1).
The native child recorded `selected-capture-stream-error=4`, meaning its current
selection predicate failed. The Mac watchdog did not emit a validation code
before this earlier child failure. Fresh Desktop recovery then succeeded under
the original Control. XCTest failed because the keyboard did not return during
that unexpected recovery; the original report remains failed.

There were 152 successful transition traces including that recovery, 153
advancing presentations, two host factories/video starts within the first
Control, and no failed/cancelled/incomplete or invalid transition traces. These
successful-looking traces do not erase the terminal disconnect or XCTest failure.
The 151 retained switches measured median 896 ms, p95 1,380 ms and maximum
3,301 ms; including Desktop recovery raises maximum to 4,452 ms. The complete
journal captured 714,103 bytes, one container relocation and one atomic rotation.
Cleanup, exact-key cleanup and original Simulator restoration passed.
Evidence: `maccompanion-reliability-watchdog-reasons-reproduction-20261004`.

The expanded resize test now selects the changed Window immediately after fresh
Desktop recovery. It verifies fresh presentation, advancing media, keyboard,
pointer/modifiers/shortcuts and reuse of the recovered host. It passes seven
advancing presentation generations, four retained handoffs and exactly three
host factories/native starts across two Control sessions including the one
intentional recovery. Its complete journal captured 205,310 bytes and a real
container relocation; all cleanup passed. This controlled recovery sequence
does not reproduce or explain the intermittent long-run selection loss.
Evidence: `maccompanion-reliability-recovery-reselection-resize-20261004`.

A read-only Quartz query comparison observed 300 reads of the owned disposable
window with no missing-window or geometry differences. This short probe does
not establish that either query is reliable over the long failure interval.
Earlier native-child diagnostics now distinguish twelve existing selection
rejections and thirteen existing handoff errors. The normative vocabulary and
sole indexed fixture were updated before the closed reader; no rejection,
deadline, authentication or input-admission semantics are relaxed. Native
capture/context/handoff and pinned bridge contracts pass. The source-built
diagnostic host/client builds, native contracts and required stable validation pass.
The installed Mac/iPhone apps remain the preceding watcher-fix candidate.

## Shared retirement publication repair, 2026-10-04

The next diagnostic source
`d54bd3a973c2da2d8c751d426bda1759cc58969396fab60e1caadd517dcebb8e`
fails its controlled resize journey. The native child records selection reason
10 (window geometry), correctly rejecting the changed window. A concurrent exact
health command then escapes as `LocalInteractiveNativeBackendErrorV1.unavailable`;
the authenticated local XPC endpoint is invalidated. Desktop recovery starts,
but bootstrap media fails and the primary shuts down about 30 ms later,
cancelling recovery. Four presentation generations advanced before this loss;
its complete 214,962-byte journal and all cleanup remain preserved.
Evidence: `maccompanion-reliability-native-child-reasons-resize-smoke-20261004`.

A gated regression independently reproduces this ordering in 32 of 32 attempts:
an in-flight health read suspends while the capture watchdog fences the permit,
then the worker and native retirement finish. Retirement previously published
its exact scope tombstone and cleared ownership in the initiating caller after
awaiting the shared task. Another waiter could return before that publication;
health then threw instead of returning inactive, escalating expected window loss
into whole-control teardown.

Publication now completes inside the shared retirement task. Every joined caller
observes the exact retired scope and cleared ownership before returning. The
normative local-backend profile and sole indexed fixture were updated first.
All 32 regression attempts pass after repair; existing joined-drain, wrong-scope,
malformed-sample and stale-retire tests also pass. No receipt shape, signature,
pairing, deadline, malformed-command or input-admission rule is relaxed.
Before/after evidence: `maccompanion-reliability-retirement-publication-before-20261004.log`
and `maccompanion-reliability-retirement-publication-after-20261004.log`.

The normal pickers now observe the transition gate, show recovery progress,
disable remote selections/refresh while busy and keep Cancel available. The
expanded journey holds the picker open across resize recovery and then requires
fresh Window video/input and reuse of the recovered host. Source
`2e587e9d9127e92bf5063a4487d2c47a45d75155331cb1280e8401571a67b35d`
builds for the Simulator. Required stable validation passes; its runtime follow-up is recorded below.
The installed Mac/iPhone apps remain the preceding watcher-fix
candidate; this repair has not yet been installed on the affected phone.

### Fresh picker inventory follow-up

The first repair candidate correctly recovered Desktop video/input in 2,513 ms
while the picker remained open. Its journey failed solely because the test
looked for Cancel while iOS active search exposed Close instead. That failed
report is preserved (`maccompanion-reliability-retirement-publication-resize-20261004`).
Correcting the assertion exposed a real second failure: Desktop recovery
invalidates the previous surface-bound one-use target inventory. The picker
still showed those old rows, so immediate reselection failed before a new
surface request could be prepared. Recovery itself succeeded in 2,356 ms;
the reselection terminated Control. That failed report is also preserved
(`maccompanion-reliability-retirement-publication-resize-search-cancel-20261004`).

The normal UI now keeps an open picker fenced after video recovery until a fresh
inventory read completes. A local inventory generation rejects late pre-transition
results; only the fresh surface-bound tokens re-enable selection. Ordinary
selections still obtain fresh presentation/input, and obsolete tokens remain
rejected by the existing protocol. The display picker refreshes after a
transition as well. The normative continuity profile and sole indexed fixture
were updated before implementation.

Final source
`0609a0b1f5db7dc94e234c412b2a5c77abbe55550b33f39225a7fa702d34f77c`
passes required stable-Xcode validation, both native client SDK builds and
normal Mac/Simulator/device builds. Both normal apps are staged with existing
signing identities, requirements/profiles and Keychain groups preserved. The
source-built diagnostic host has a verified first-party supervisor and signed
catalog `3cd7a967d9c118cecd7ecab5efb7296ef6f4013e6046de6039470766ece177f3`.
The final open-picker resize/reselection journey passes: seven advancing
presentation generations, four retained handoffs and exactly three host/video
starts across two Control sessions including the intentional Desktop recovery.
All five transition traces complete, with recovery at 2,560 ms and retained
Window reselection at 811 ms. Keyboard, pointer, modifiers and shortcuts pass;
no presentation stalls or invalid events occur. Its complete 253,744-byte
journal follows one real container relocation; cleanup, exact-key cleanup and
original Simulator restoration pass.
Evidence: `maccompanion-reliability-final-retirement-inventory-resize-20261004`.
The final-source 200-switch gate passes: 202 retained handoffs, 204 unique
advancing presentations, exactly two host factories/native launches/video starts
across two Control sessions, and no failed/cancelled/incomplete/invalid transition
traces or stalled presentations. Median time to fresh input is 912 ms, p95
1,180 ms and maximum 1,553 ms. Stage p95 values are renderer drain 36 ms,
enrollment drain 184 ms, host acknowledgement 157 ms, native preparation 521 ms,
first frame 133 ms and input admission 391 ms; these stage percentiles are not
additive. The 686,890-byte journal is complete through one actual container
relocation and one atomic rotation. Stop, the second Control session, cleanup,
exact-key cleanup and original Simulator restoration pass.
Evidence: `maccompanion-reliability-final-retirement-inventory-200-switches-20261004`.

The same candidate is now installed at `/Users/yihong/Applications/Mac Companion.app`
and on the physical iPhone 18 Pro Max. Existing signing requirements, profiles,
Keychain groups and pairing data are preserved. Mac app and bundled Agent run;
the Agent's TLS listener reaches ready. Device installation succeeds, but iOS
refuses launch while the phone is locked. No physical playback, one-hour session
or perceived latency result is inferred from installation. Previous app bundles
and failed test reports are preserved. Install receipts:
`maccompanion-reliability-final-retirement-inventory-mac-install-20261004.json`
and `maccompanion-reliability-final-retirement-inventory-ios-install-20261004.json`.

### Additional final-source recovery checks

Window movement with the picker open passes fresh Desktop recovery, inventory
refresh and Window reselection: seven advancing presentations, four retained
handoffs, exactly three native/host starts across two Control sessions including
one recovery, and no stalls/invalid progress. All cleanup and Simulator
restoration pass (`maccompanion-reliability-final-retirement-inventory-move-20261004`).

Background input fencing, foreground fresh enrollment and a deliberate primary
listener interruption/reconnection pass on the same source, with six advancing
presentations. The complete journal is 194,796 bytes through one container
relocation. Cleanup, exact-key cleanup and original Simulator restoration pass
(`maccompanion-reliability-final-retirement-inventory-background-network-20261004`).
These reconnects follow actual lifecycle/network loss; the ordinary switching
gate separately requires retained transport.

Selected-window closure also passes on the final source: Desktop video and input
recover under the original Control session, with six advancing presentations and
four completed transition traces. The complete 208,419-byte journal follows one
container relocation; cleanup, exact-key cleanup and original Simulator
restoration pass (`maccompanion-reliability-final-retirement-inventory-window-closure-20261004`).

A one-minute Desktop continuity journey passes on the final source, including
keyboard, pointer, modifiers, shortcuts, complete 211,497-byte diagnostic journal
and restoration (`maccompanion-reliability-final-retirement-inventory-desktop-spaces-20261004`).
The directory name does not establish Spaces acceptance: native Mission Control
automation timed out before a Space change could be observed. No ordinary
multi-Desktop switch was verified. Its separate diagnostic assessment records
that limitation; the passing Desktop hold is not counted as a passing Spaces case.
Physical acceptance still requires the unlocked affected phone.

## Implementation fences

- Original primary, registered session key, Control generation and expiry are
  revalidated across every await and retained transfer.
- Opt-in retention is acknowledged only after input revocation and child pause.
  Unsupported peers retain the previous replacement path.
- Capture epochs follow submitted encoder PTS through reordered packets; queued
  frames cannot be relabelled as the new surface.
- Stop, background, primary/grant loss, timeout and failed handoff join owned
  cleanup. Old operation retirement cannot affect the new logical owner.
- Fresh presentation and geometry precede remote input. Local keyboard access
  remains available while delivery is paused.
- The repeated-switch campaign also requires another client-queued frame for
  every presentation, correlated by an anonymous diagnostic attempt, plus
  advancing host media and fresh input. Diagnostics add no admission delay.

## Remaining acceptance

Subsequent physical evidence is recorded in
[the view-switch failure investigation](2026-10-04-native-physical-switch-failure.md).
The affected phone's runtime journal contains real failures after initially
successful switches. This supersedes the earlier locked-phone limitation. The
latest physical retry establishes native post-update content-placement rejection
before the watchdog closes a retained Window handoff. A native regression
reproduces that fatal path; bounded discard before the first strictly matching
frame repairs it and passes final stable validation. The repaired normal Mac
host is signed, installed and launched with the existing pairing and compatible
iPhone client. Fresh repeated physical switches remain pending. Earlier input
posting and selected-surface lookup failures remain separate open cases.

Final source
`0609a0b1f5db7dc94e234c412b2a5c77abbe55550b33f39225a7fa702d34f77c`
is built, signed and installed on both normal apps. Required stable validation,
open-picker resize/reselection and the complete 202-retained-switch gate pass.
Window movement with open-picker reselection and background/network recovery
pass on this source; selected-window closure and the one-minute Desktop hold
also pass.
Earlier closure, movement, background/network and Finder full-screen Space
journeys remain separately attributed to their earlier source; ordinary
multi-Desktop Space cycling remains pending after the Mission Control automation
timeout.

Physical startup/playback subsequently passes on the `d372301b...` candidate,
with approximately 220 seconds of advancing video. Remaining acceptance is
repeated physical display/window/resize/Spaces/background/network cases, an
affected-phone one-hour session, local Wi-Fi p95 below one second and a
same-hardware Sunshine/Moonlight comparison. The Simulator p95 of 1,180 ms is
above that latency target and is not a physical Wi-Fi measurement. Earlier
failed candidates and the preceding passing candidate remain separately recorded.

The campaign must fail if successful-looking switches reconnect instead of
retaining the transport, if terminal/incomplete traces disappear, or if cleanup
does not complete. Simulator input is synthetic and cannot establish physical
keyboard/pointer latency or everyday readiness.
