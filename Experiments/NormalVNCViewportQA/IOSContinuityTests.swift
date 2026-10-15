import Darwin
import ActivityKit
import LocalAuthentication
import SwiftUI
import XCTest
import Observation
@testable import Mac_Companion

private final class ContinuityAuthentication: LAContext, @unchecked Sendable {
    var reply: (@Sendable (Bool, (any Error)?) -> Void)?
    var evaluations = 0
    var preflights = 0
    var policyAvailable = true
    var invalidations = 0
    var cancelReplyOnInvalidate = false
    override func invalidate() {
        invalidations += 1
        if cancelReplyOnInvalidate { reply?(false, LAError(.appCancel)) }
    }
    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        preflights += 1; return policyAvailable
    }
    override func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        evaluations += 1; self.reply = reply
    }
}

@MainActor private final class ContinuityActivityBackend: RemoteSessionActivityBackend {
    var enabled = true
    var ids: [String] = []
    var contents: [ActivityContent<RemoteSessionActivityAttributes.ContentState>] = []
    var blocked = false
    var reply: CheckedContinuation<Void, Never>?
    var starts = 0
    var endedIDs: [String] = []
    var updatedIDs: [String] = []
    var completedUpdateIDs: [String] = []
    func existingIDs() -> [String] { ids }
    func start(_ attributes: RemoteSessionActivityAttributes, content: ActivityContent<RemoteSessionActivityAttributes.ContentState>) throws -> String {
        starts += 1
        let id = "synthetic-activity-\(starts)"
        ids.append(id); contents.append(content); return id
    }
    func update(_ id: String, content: ActivityContent<RemoteSessionActivityAttributes.ContentState>) async {
        contents.append(content)
        updatedIDs.append(id)
        if blocked { await withCheckedContinuation { reply = $0 } }
        completedUpdateIDs.append(id)
    }
    func end(_ id: String) async { endedIDs.append(id); ids.removeAll { $0 == id } }
    func release() { blocked = false; let saved = reply; reply = nil; saved?.resume() }
}

private final class ContinuitySession: CompanionVNCSession {
    var alive = true, ready = true, completeRelease = true
    var pauses = 0, stops = 0, resumes = 0
    override var running: Bool { alive }
    override var established: Bool { alive }
    override var connected: Bool { ready && alive }
    override func pause(completion: (() -> Void)?) {
        pauses += 1; ready = false
        if completeRelease { completion?() }
    }
    override func stop() { stops += 1; alive = false; ready = false }
    override func resume() { resumes += 1; ready = true }
}

@MainActor final class IOSContinuityTests: XCTestCase {

    func testColdUnlockEvaluatesAsynchronouslyWithoutDuplicatedPreflightAndHandlesMissingPasscode() async throws {
        let context = ContinuityAuthentication(), defaults = isolatedDefaults(), timings = DirectUnlockTimingsV1()
        defaults.set(true, forKey: DirectAppLockV1.preferenceKey)
        context.policyAvailable = false
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: defaults, unlockTimings: timings,
                                   isActive: { true }, isBackground: { false }, protectedDataAvailable: { true })
        defer { lock.setEnabled(false) }
        lock.install()
        XCTAssertEqual(context.preflights, 0); XCTAssertEqual(context.evaluations, 1)
        XCTAssertTrue(lock.authenticating); XCTAssertTrue(lock.privacyCoverVisible); XCTAssertFalse(lock.canInteract)
        context.reply?(false, LAError(.passcodeNotSet))
        try await eventually { !lock.authenticating }
        XCTAssertEqual(timings.records.last?.outcome, .unavailable)
        XCTAssertTrue(lock.message.contains("Set up a device passcode")); XCTAssertTrue(lock.unlockButtonEnabled)
        XCTAssertFalse(lock.canAccess); XCTAssertTrue(lock.privacyCoverVisible)
        lock.becameActive(); XCTAssertEqual(context.evaluations, 1)
        lock.authenticate(); XCTAssertEqual(context.preflights, 0); XCTAssertEqual(context.evaluations, 2)
    }
    func testSuccessfulLocalHandoffSurvivesCleanupCancellationWithoutRemoteAdmission() async throws {
        var active = true
        let context = ContinuityAuthentication(), timings = DirectUnlockTimingsV1()
        context.cancelReplyOnInvalidate = true
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(), unlockTimings: timings,
                                   isActive: { active }, isBackground: { false }, protectedDataAvailable: { true })
        defer { lock.setEnabled(false) }
        lock.setEnabled(true); active = false; lock.becameInactive(); context.reply?(true, nil)
        try await eventually { !lock.authenticating }
        XCTAssertEqual(context.invalidations, 1)
        try await Task.sleep(for: .milliseconds(125))
        XCTAssertEqual(lock.unlockButtonTitle, "Unlock")
        XCTAssertFalse(lock.privacyCoverVisible); XCTAssertTrue(lock.contentVisible); XCTAssertTrue(lock.canInteract)
        XCTAssertFalse(lock.canResumeRemoteSession)
        XCTAssertGreaterThanOrEqual(timings.records.last?.activitySamples.count ?? 0, 1)
        active = true; lock.receivedActivationNotification()
        XCTAssertTrue(lock.canInteract); XCTAssertTrue(lock.contentVisible); XCTAssertFalse(lock.privacyCoverVisible)
        XCTAssertEqual(context.evaluations, 1); XCTAssertEqual(context.invalidations, 1)
    }
    func testActivationSamplesDistinguishResponsiveInactivityFromMainActorStall() async throws {
        let timings = DirectUnlockTimingsV1(), token = try XCTUnwrap(timings.begin(active: true))
        timings.startActivationProbe(token: token) { (false, false) }
        try await Task.sleep(for: .milliseconds(125))
        let before = try XCTUnwrap(timings.records.last).activitySamples
        XCTAssertGreaterThanOrEqual(before.count, 1); XCTAssertTrue(before.allSatisfy { !$0.active && !$0.background })
        // Schedule a pending tick, then deliberately block this test's actor.
        try await Task.sleep(for: .milliseconds(5))
        usleep(120_000)
        try await Task.sleep(for: .milliseconds(5))
        XCTAssertTrue(try XCTUnwrap(timings.records.last).activitySamples.contains { $0.mainActorDelayMilliseconds >= 60 })
        timings.finish(.revoked)
        let count = timings.records.last?.activitySamples.count
        try await Task.sleep(for: .milliseconds(75))
        XCTAssertEqual(timings.records.last?.activitySamples.count, count)
    }
    func testAdmissionCheckpointPersistsWithoutNativeDisplayTick() async throws {
        let url = URL.temporaryDirectory.appending(path: "synthetic-unlock-checkpoint-" + UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let timings = DirectUnlockTimingsV1(persist: true, storageURL: url)
        let token = try XCTUnwrap(timings.begin(active: true))
        timings.mark(.activeAdmission, token: token)
        for _ in 0..<80 { timings.recordActivitySample(token: token, active: false, background: false, delayMilliseconds: 0) }
        timings.checkpoint(); await timings.waitForWrites()
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let saved = try XCTUnwrap((snapshot["records"] as? [[String: Any]])?.last)
        XCTAssertEqual(saved["outcome"] as? String, "pending")
        XCTAssertEqual((saved["activitySamples"] as? [Any])?.count, 64)
        XCTAssertEqual(timings.pendingToken, token)
        timings.finish(.revoked)
    }
    func testUnlockPhaseTimingsSeparateRawCallbackFromActorHandling() async throws {
        let context = ContinuityAuthentication(), timings = DirectUnlockTimingsV1()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(), unlockTimings: timings,
                                   isActive: { true }, protectedDataAvailable: { true })
        defer { lock.setEnabled(false) }
        lock.setEnabled(true)
        let reply = try XCTUnwrap(context.reply), signaled = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { reply(true, nil); signaled.signal() }
        XCTAssertEqual(signaled.wait(timeout: .now() + 1), .success)
        // A deliberate test-only actor stall must appear after the raw callback.
        usleep(80_000)
        try await eventually { lock.canInteract }
        let events = try XCTUnwrap(timings.records.last).events
        let raw = try XCTUnwrap(events.first { $0.phase == .authenticationCallback }).milliseconds
        let handled = try XCTUnwrap(events.first { $0.phase == .authenticationHandled }).milliseconds
        XCTAssertGreaterThanOrEqual(handled - raw, 70)
        XCTAssertFalse(events.contains { $0.phase == .activationNotification }, "Reconciliation is not an activation notification")
        XCTAssertFalse(lock.privacyCoverVisible)
        XCTAssertEqual(events.filter { $0.phase == .activeAdmission }.count, 1)
    }
    func testUnlockPhaseTimingsKeepActivationAndAuthenticationOrderDistinct() async throws {
        for resultFirst in [false, true] {
            var active = true
            let context = ContinuityAuthentication(), timings = DirectUnlockTimingsV1()
            let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(), unlockTimings: timings,
                                       isActive: { active }, protectedDataAvailable: { true })
            lock.setEnabled(true); active = false; lock.becameInactive()
            if resultFirst {
                context.reply?(true, nil); try await eventually { !lock.authenticating }
                XCTAssertFalse(lock.privacyCoverVisible); XCTAssertTrue(lock.canInteract)
                XCTAssertFalse(lock.canResumeRemoteSession)
                active = true; lock.receivedActivationNotification()
            } else {
                active = true; lock.receivedActivationNotification()
                XCTAssertTrue(lock.privacyCoverVisible); XCTAssertFalse(lock.canInteract)
                context.reply?(true, nil); try await eventually { lock.canInteract }
            }
            let events = try XCTUnwrap(timings.records.last).events
            let result = try XCTUnwrap(events.firstIndex { $0.phase == .authenticationHandled })
            let activation = try XCTUnwrap(events.firstIndex { $0.phase == .activationNotification })
            XCTAssertEqual(result < activation, resultFirst)
            XCTAssertEqual(events.filter { $0.phase == .activeAdmission }.count, 1)
            XCTAssertEqual(events.filter { $0.phase == .localAdmission }.count, 1)
            let reveal = try XCTUnwrap(events.firstIndex { $0.phase == .coverRemoved })
            XCTAssertEqual(reveal < activation, resultFirst)
            XCTAssertTrue(lock.canResumeRemoteSession)
            XCTAssertFalse(lock.privacyCoverVisible); XCTAssertTrue(lock.canInteract)
            lock.setEnabled(false)
        }
    }
    func testUnlockPhaseTimingsRetireOldCallbacksAndFrameProbes() async throws {
        var active = true
        let context = ContinuityAuthentication(), timings = DirectUnlockTimingsV1()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(), unlockTimings: timings,
                                   isActive: { active }, protectedDataAvailable: { true })
        defer { lock.setEnabled(false) }
        lock.setEnabled(true)
        let oldReply = try XCTUnwrap(context.reply), oldToken = try XCTUnwrap(lock.unlockTimingToken)
        active = false; lock.background()
        XCTAssertEqual(timings.records.first?.outcome, .revoked)
        active = true; lock.becameActive()
        let currentReply = try XCTUnwrap(context.reply), currentToken = try XCTUnwrap(lock.unlockTimingToken)
        XCTAssertNotEqual(oldToken, currentToken)
        oldReply(true, nil); try await Task.sleep(for: .milliseconds(25))
        lock.recordUnlockDisplayTick(token: oldToken, phase: .libraryDisplayTick)
        XCTAssertFalse(lock.canInteract); XCTAssertEqual(timings.records.count, 2)
        XCTAssertFalse(try XCTUnwrap(timings.records.last).events.contains { $0.phase == .authenticationCallback })
        currentReply(true, nil); try await eventually { lock.canInteract }
        let eventCount = try XCTUnwrap(timings.records.last).events.count
        currentReply(true, nil); try await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(timings.records.last?.events.count, eventCount)
        lock.protectedDataLost()
        lock.recordUnlockDisplayTick(token: currentToken, phase: .libraryDisplayTick)
        XCTAssertEqual(timings.records.last?.outcome, .revoked)
        XCTAssertFalse(try XCTUnwrap(timings.records.last).events.contains { $0.phase == .libraryDisplayTick })
        XCTAssertNil(lock.unlockTimingToken)
    }
    func testUnlockTimingDisplayProbeRecordsOneRealEligibleTick() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let root = UIViewController(); window.rootViewController = root; window.makeKeyAndVisible()
        let context = ContinuityAuthentication(), timings = DirectUnlockTimingsV1()
        var active = true
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(), unlockTimings: timings,
                                   isActive: { active }, protectedDataAvailable: { true })
        let probe = DirectUnlockFrameProbeView(frame: root.view.bounds)
        root.view.addSubview(probe); probe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        defer { probe.stop(); lock.setEnabled(false); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        lock.setEnabled(true)
        let token = try XCTUnwrap(lock.unlockTimingToken)
        probe.configure(lock: lock, token: token, phase: .libraryDisplayTick, enabled: true)
        XCTAssertFalse(probe.sampling)
        active = false; lock.becameInactive(); context.reply?(true, nil)
        try await eventually { !lock.authenticating }
        probe.configure(lock: lock, token: token, phase: .libraryDisplayTick, enabled: true)
        XCTAssertFalse(probe.sampling); XCTAssertFalse(lock.privacyCoverVisible)
        XCTAssertTrue(lock.canInteract); XCTAssertFalse(lock.canResumeRemoteSession)
        active = true; lock.receivedActivationNotification()
        probe.configure(lock: lock, token: token, phase: .libraryDisplayTick, enabled: true)
        root.view.layoutIfNeeded()
        try await eventually { timings.records.last?.outcome == .success }
        XCTAssertNil(lock.unlockTimingToken); XCTAssertFalse(probe.sampling)
        probe.configure(lock: lock, token: token, phase: .libraryDisplayTick, enabled: true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(timings.records.last?.events.filter { $0.phase == .libraryDisplayTick }.count, 1)
        probe.removeFromSuperview(); XCTAssertFalse(probe.sampling)
    }
    func testUnlockTimingWritesOrderedBoundedSnapshotOffAdmissionPath() async throws {
        let url = URL.temporaryDirectory.appending(path: "synthetic-unlock-timing-" + UUID().uuidString + ".json")
        let disabledURL = URL.temporaryDirectory.appending(path: "synthetic-disabled-timing-" + UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let timings = DirectUnlockTimingsV1(persist: true, storageURL: url)
        timings.libraryWaitStarted(); timings.libraryWaitFinished(readable: true)
        for _ in 0..<12 { _ = timings.begin(active: true) }
        timings.finish(.success)
        await timings.waitForWrites()
        let data = try Data(contentsOf: url)
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let records = try XCTUnwrap(snapshot["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 8)
        XCTAssertEqual(records.compactMap { $0["sequence"] as? Int }, Array(5...12))
        XCTAssertEqual(records.last?["outcome"] as? String, "success")
        let disabled = DirectUnlockTimingsV1(enabled: false, persist: true, storageURL: disabledURL)
        XCTAssertNil(disabled.begin(active: true)); disabled.libraryWaitStarted(); disabled.libraryWaitFinished(readable: true)
        await disabled.waitForWrites()
        XCTAssertFalse(FileManager.default.fileExists(atPath: disabledURL.path))
    }
    func testUnlockTimingSnapshotContainsOnlyBoundedContentFreePhases() throws {
        let timings = DirectUnlockTimingsV1()
        timings.libraryWaitStarted(); timings.libraryWaitFinished(readable: true)
        for _ in 0..<12 {
            let token = try XCTUnwrap(timings.begin(active: true))
            for phase in [DirectUnlockTimingsV1.Phase.evaluationIssued, .authenticationCallback, .authenticationHandled] {
                timings.mark(phase, token: token); timings.mark(phase, token: token)
            }
        }
        timings.finish(.success)
        XCTAssertEqual(timings.records.count, 8)
        XCTAssertEqual(timings.records.map(\.sequence), Array(5...12))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(timings.snapshot)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schema", "clock", "frameMeaning", "library", "records"])
        let records = try XCTUnwrap(object["records"] as? [[String: Any]])
        for record in records {
            XCTAssertEqual(Set(record.keys), ["sequence", "activeAtRequest", "libraryAtRequest", "outcome", "events", "activitySamples"])
            let samples = try XCTUnwrap(record["activitySamples"] as? [[String: Any]])
            XCTAssertLessThanOrEqual(samples.count, 64)
            for sample in samples { XCTAssertEqual(Set(sample.keys), ["milliseconds", "active", "background", "mainActorDelayMilliseconds"]) }
            let events = try XCTUnwrap(record["events"] as? [[String: Any]])
            XCTAssertLessThanOrEqual(events.count, 16)
            XCTAssertEqual(Set(events.compactMap { $0["phase"] as? String }).count, events.count)
            for event in events {
                XCTAssertEqual(Set(event.keys), ["phase", "milliseconds"])
                XCTAssertNotNil(event["milliseconds"] as? Double)
            }
        }
        let disabled = DirectUnlockTimingsV1(enabled: false)
        XCTAssertNil(disabled.begin(active: true)); disabled.libraryWaitStarted()
        XCTAssertTrue(disabled.snapshot.records.isEmpty); XCTAssertTrue(disabled.snapshot.library.isEmpty)
        let policy = try XCTUnwrap(try fixture()["clientAdditions"] as? [String: Any])
        let appLock = try XCTUnwrap(policy["appLock"] as? [String: Any])
        let diagnostic = try XCTUnwrap(appLock["developmentTimings"] as? [String: Any])
        XCTAssertEqual(diagnostic["maximumAttempts"] as? Int, 8)
        XCTAssertEqual(diagnostic["changesAdmission"] as? Bool, false)
    }

    private enum WaitFailure: Error { case conditionNotReached }
    private func isolatedDefaults() -> UserDefaults { UserDefaults(suiteName: "continuity-qa-" + UUID().uuidString)! }
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition did not become true within the bounded wait")
        throw WaitFailure.conditionNotReached
    }
    func testObservedDesktopEndDismissesDuringBlockedUpdateAndLateCompletionCannotRetireReplacement() async throws {
        let fixture = try fixture()
        let policy = try XCTUnwrap(fixture["recoveryPolicy"] as? [String: Any])
        XCTAssertEqual(policy["knownEndIndependentOfActivityUpdate"] as? Bool, true)
        let vectors = try XCTUnwrap(fixture["interruptionCases"] as? [[String: Any]])
        XCTAssertNotNil(vectors.first { $0["name"] as? String == "observed-desktop-end-during-stalled-activity-update" })
        let backend = ContinuityActivityBackend()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", address: "test.local")
        let owner = VNCSessionActivityController(mac: mac, defaults: isolatedDefaults(), backend: backend)
        defer { backend.release(); owner.finish() }
        owner.setPhase("connected"); await owner.waitForUpdates()
        let oldID = try XCTUnwrap(backend.ids.first)
        backend.blocked = true; owner.setPhase("paused")
        try await eventually { backend.reply != nil }
        owner.setPhase("ended")
        XCTAssertFalse(owner.ownsActivity(oldID), "Known closure revokes ownership synchronously")
        try await eventually { backend.endedIDs.contains(oldID) }
        XCTAssertNotNil(backend.reply, "Dismissal must happen before the stalled update returns")
        XCTAssertTrue(backend.ids.isEmpty)

        owner.setPhase("connected"); await owner.waitForUpdates()
        let replacementID = try XCTUnwrap(backend.ids.first)
        XCTAssertNotEqual(replacementID, oldID); XCTAssertTrue(owner.ownsActivity(replacementID))
        backend.release()
        try await eventually { backend.completedUpdateIDs.contains(oldID) }
        XCTAssertEqual(backend.ids, [replacementID]); XCTAssertTrue(owner.ownsActivity(replacementID))
        owner.setPhase("paused"); await owner.waitForUpdates()
        XCTAssertEqual(backend.updatedIDs, [oldID, replacementID], "Late old completion cannot consume or redirect replacement work")
        owner.finish(); await owner.waitForUpdates(); XCTAssertTrue(backend.ids.isEmpty)
    }
    func testTerminalFinishDismissesDuringBlockedUpdateAndCannotRestart() async throws {
        let vectors = try XCTUnwrap(try fixture()["interruptionCases"] as? [[String: Any]])
        XCTAssertNotNil(vectors.first { $0["name"] as? String == "terminal-finish-during-stalled-activity-update" })
        let backend = ContinuityActivityBackend()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", address: "test.local")
        let owner = VNCSessionActivityController(mac: mac, kind: .terminal, defaults: isolatedDefaults(), backend: backend)
        defer { backend.release(); owner.finish() }
        owner.setPhase("connected"); await owner.waitForUpdates()
        let id = try XCTUnwrap(backend.ids.first)
        backend.blocked = true; owner.setForeground(false)
        try await eventually { backend.reply != nil }
        owner.finish(); XCTAssertFalse(owner.ownsActivity(id))
        try await eventually { backend.endedIDs.contains(id) }
        XCTAssertNotNil(backend.reply, "Terminal stop dismisses before the stalled update returns")
        owner.setForeground(true); owner.setPhase("connected")
        backend.release(); await owner.waitForUpdates()
        try await eventually { backend.completedUpdateIDs.contains(id) }
        XCTAssertTrue(backend.ids.isEmpty); XCTAssertEqual(backend.starts, 1)
        XCTAssertEqual(backend.endedIDs, [id]); XCTAssertEqual(backend.updatedIDs, [id])
    }
    func testInactiveAuthenticationObservablyAdmitsActualActivationWithoutSceneChange() async throws {
        var active = true
        let authentication = ContinuityAuthentication()
        let lock = DirectAppLockV1(contextFactory: { authentication }, defaults: isolatedDefaults(),
            isActive: { active }, isBackground: { false }, protectedDataAvailable: { true })
        defer { lock.setEnabled(false) }
        lock.setEnabled(true); lock.install()
        active = false; lock.becameInactive(); authentication.reply?(true, nil)
        try await eventually { !lock.authenticating }
        XCTAssertTrue(lock.canAccess); XCTAssertTrue(lock.contentVisible)
        XCTAssertTrue(lock.canInteract); XCTAssertFalse(lock.privacyCoverVisible)
        XCTAssertFalse(lock.canResumeRemoteSession)
        var observed = false
        withObservationTracking { _ = lock.canResumeRemoteSession } onChange: {
            MainActor.assumeIsolated { observed = true }
        }
        active = true; lock.becameActive()
        XCTAssertTrue(observed); XCTAssertTrue(lock.canInteract)
        lock.becameInactive(); XCTAssertFalse(lock.canInteract); XCTAssertTrue(lock.contentVisible)
        lock.becameActive(); XCTAssertTrue(lock.canInteract); XCTAssertEqual(authentication.evaluations, 1)
    }
    func testActivationBeforeAuthenticationResultKeepsCoverUntilSuccess() async throws {
        var active = true
        let context = ContinuityAuthentication()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(),
            isActive: { active }, isBackground: { false }, protectedDataAvailable: { true })
        defer { lock.setEnabled(false) }
        lock.setEnabled(true)
        active = false; lock.becameInactive()
        active = true; lock.becameActive()
        XCTAssertFalse(lock.canAccess); XCTAssertFalse(lock.canInteract); XCTAssertFalse(lock.contentVisible)
        XCTAssertTrue(lock.privacyCoverVisible); XCTAssertTrue(lock.authenticating)
        XCTAssertEqual(context.evaluations, 1)
        context.reply?(true, nil); try await eventually { lock.canInteract }
        XCTAssertTrue(lock.contentVisible); XCTAssertFalse(lock.privacyCoverVisible)
        XCTAssertEqual(context.evaluations, 1)
    }
    func testAlreadyActiveAuthenticationSuccessNeedsNoLifecycleNotification() async throws {
        let context = ContinuityAuthentication()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(),
            isActive: { true }, isBackground: { false }, protectedDataAvailable: { true })
        var publications = 0
        let observer = NotificationCenter.default.addObserver(forName: DirectAppLockV1.unlocked, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { publications += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer); lock.setEnabled(false) }
        let vectors = try XCTUnwrap(try fixture()["appAuthenticationHandoffCases"] as? [[String: Any]])
        XCTAssertEqual(vectors.first { $0["name"] as? String == "already-active-success-without-notification" }?["requiresNewActivationEvent"] as? Bool, false)
        lock.setEnabled(true); context.reply?(true, nil)
        try await eventually { lock.canInteract }
        XCTAssertTrue(lock.contentVisible); XCTAssertFalse(lock.privacyCoverVisible)
        XCTAssertEqual(publications, 1); XCTAssertEqual(context.evaluations, 1)
        lock.becameActive(); XCTAssertEqual(publications, 1)
    }
    func testCancelledInactiveAuthenticationRequiresExplicitRetry() async throws {
        var active = true
        let context = ContinuityAuthentication()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(),
            isActive: { active }, isBackground: { false }, protectedDataAvailable: { true })
        defer { lock.setEnabled(false) }
        lock.setEnabled(true)
        active = false; lock.becameInactive(); context.reply?(false, LAError(.userCancel))
        try await eventually { !lock.authenticating }
        active = true; lock.becameActive(); lock.install(); lock.becameActive()
        XCTAssertFalse(lock.canAccess); XCTAssertFalse(lock.canInteract)
        XCTAssertTrue(lock.privacyCoverVisible); XCTAssertFalse(lock.authenticating)
        XCTAssertEqual(context.evaluations, 1)
        lock.authenticate(); XCTAssertEqual(context.evaluations, 2)
        context.reply?(true, nil); try await eventually { lock.canInteract }
    }
    func testPendingAuthenticationIsRetiredByProtectedDataLoss() async throws {
        var active = true, protected = true
        let context = ContinuityAuthentication()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(),
            isActive: { active }, isBackground: { false }, protectedDataAvailable: { protected })
        defer { lock.setEnabled(false) }
        lock.setEnabled(true); let reply = try XCTUnwrap(context.reply)
        active = false; lock.becameInactive(); reply(true, nil)
        try await eventually { !lock.authenticating }
        XCTAssertTrue(lock.canAccess); XCTAssertTrue(lock.canInteract)
        XCTAssertFalse(lock.canResumeRemoteSession)
        protected = false; lock.protectedDataLost(); reply(true, nil)
        active = true; lock.becameActive()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(lock.canAccess); XCTAssertFalse(lock.contentVisible); XCTAssertTrue(lock.privacyCoverVisible)
        XCTAssertEqual(context.evaluations, 1)
        protected = true; lock.becameActive(); XCTAssertEqual(context.evaluations, 2)
        context.reply?(true, nil); try await eventually { lock.canInteract }
    }
    func testUnlockButtonReflectsCurrentAttemptAndActiveAdmission() async throws {
        var active = true
        let context = ContinuityAuthentication()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(),
            isActive: { active }, isBackground: { false }, protectedDataAvailable: { true })
        defer { lock.setEnabled(false) }
        let appLock = try XCTUnwrap((try fixture()["clientAdditions"] as? [String: Any])?["appLock"] as? [String: Any])
        XCTAssertEqual(appLock["authenticationPresentation"] as? String, "persistentUnlockCard")
        lock.setEnabled(true)
        XCTAssertEqual(lock.unlockButtonTitle, appLock["evaluatingButtonTitle"] as? String)
        XCTAssertFalse(lock.unlockButtonEnabled); XCTAssertFalse(lock.canInteract)
        active = false; lock.becameInactive(); context.reply?(true, nil)
        try await eventually { !lock.authenticating }
        XCTAssertNil(appLock["pendingActiveButtonTitle"])
        XCTAssertEqual(lock.unlockButtonTitle, "Unlock")
        XCTAssertFalse(lock.unlockButtonEnabled); XCTAssertFalse(lock.privacyCoverVisible)
        XCTAssertTrue(lock.contentVisible); XCTAssertTrue(lock.canInteract)
        XCTAssertFalse(lock.canResumeRemoteSession)
        active = true; lock.becameActive()
        XCTAssertTrue(lock.canInteract); XCTAssertFalse(lock.privacyCoverVisible)
        XCTAssertFalse(lock.unlockButtonEnabled); XCTAssertEqual(context.evaluations, 1)
    }
    func testUnlockRetryButtonRequiresForegroundAndProtectedData() async throws {
        var active = true, protected = true
        let context = ContinuityAuthentication()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(),
            isActive: { active }, isBackground: { false }, protectedDataAvailable: { protected })
        defer { lock.setEnabled(false) }
        lock.setEnabled(true); active = false; lock.becameInactive()
        context.reply?(false, LAError(.userCancel)); try await eventually { !lock.authenticating }
        XCTAssertEqual(lock.unlockButtonTitle, "Unlock"); XCTAssertFalse(lock.unlockButtonEnabled)
        active = true; lock.becameActive(); XCTAssertTrue(lock.unlockButtonEnabled)
        protected = false; lock.becameActive(); XCTAssertFalse(lock.unlockButtonEnabled)
        var observed = false
        withObservationTracking { _ = lock.unlockButtonEnabled } onChange: { MainActor.assumeIsolated { observed = true } }
        protected = true; lock.becameActive()
        XCTAssertTrue(observed); XCTAssertTrue(lock.unlockButtonEnabled); XCTAssertEqual(context.evaluations, 1)
        lock.authenticate(); XCTAssertEqual(context.evaluations, 2); XCTAssertFalse(lock.unlockButtonEnabled)
    }
    func testDisablingUnlockDuringInactivityPublishesAtActiveBoundary() async throws {
        var active = true
        let context = ContinuityAuthentication()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(),
            isActive: { active }, isBackground: { false }, protectedDataAvailable: { true })
        lock.setEnabled(true); lock.install()
        var publications = 0
        let observer = NotificationCenter.default.addObserver(forName: DirectAppLockV1.unlocked, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { publications += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer); lock.setEnabled(false) }
        active = false; lock.becameInactive(); lock.setEnabled(false)
        XCTAssertTrue(lock.canAccess); XCTAssertFalse(lock.canInteract); XCTAssertEqual(publications, 0)
        active = true; lock.becameActive(); lock.becameActive()
        XCTAssertTrue(lock.canInteract); XCTAssertEqual(publications, 1)
        context.reply?(true, nil); try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(publications, 1)
    }
    func testInitialPurchaseReadPreservesFreeRightsAndOnlyNewestLookupPublishesReadiness() async throws {
        var replies: [CheckedContinuation<DirectProSnapshot, Never>] = []
        let access = DirectProAccess(defaults: isolatedDefaults(), readEntitlements: {
            await withCheckedContinuation { replies.append($0) }
        })
        let first = Task { await access.refresh() }
        try await eventually { replies.count == 1 }
        let second = Task { await access.refresh() }
        try await eventually { replies.count == 2 }
        let free = UUID(), paid = UUID()
        XCTAssertFalse(access.ready); XCTAssertTrue(access.canAddMac(count: 0))
        XCTAssertTrue(access.canUseMac(free, among: [free, paid])); XCTAssertFalse(access.canUseMac(paid, among: [free, paid]))
        replies[0].resume(returning: DirectProSnapshot(lifetime: true)); await first.value
        XCTAssertFalse(access.ready); XCTAssertFalse(access.hasPro)
        replies[1].resume(returning: DirectProSnapshot()); await second.value
        XCTAssertTrue(access.ready); XCTAssertFalse(access.hasPro)
        XCTAssertTrue(access.canUseMac(free, among: [free, paid]))
    }
    func testIndexedUnlockGraceNeverGrantsBackgroundAccessAndRequiresFreshAuthenticationAtExpiry() async throws {
        let vectors = try XCTUnwrap(try fixture()["appUnlockGraceCases"] as? [[String: Any]])
        for vector in vectors {
            var time: TimeInterval = 100, active = true, protected = true
            let context = ContinuityAuthentication()
            let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(), now: { time },
                isActive: { active }, protectedDataAvailable: { protected })
            defer { lock.setEnabled(false) }
            lock.setGraceSeconds(try XCTUnwrap(vector["graceSeconds"] as? Int)); lock.setEnabled(true)
            context.reply?(true, nil); try await Task.sleep(for: .milliseconds(30)); XCTAssertTrue(lock.canAccess)
            active = false; lock.background(); XCTAssertFalse(lock.canAccess)
            time += try XCTUnwrap(vector["elapsedSeconds"] as? Double)
            protected = try XCTUnwrap(vector["protectedDataAvailable"] as? Bool)
            lock.becameActive(); XCTAssertFalse(lock.canAccess, "Inactive return cannot reuse access")
            active = true; lock.becameActive()
            let needsAuthentication = try XCTUnwrap(vector["authenticate"] as? Bool)
            XCTAssertEqual(lock.canAccess, !needsAuthentication, vector["name"] as? String ?? "")
            if needsAuthentication && protected { XCTAssertTrue(lock.authenticating); XCTAssertEqual(context.evaluations, 2) }
        }
    }
    func testCancelledInactiveGestureNeverShowsNativeCoverOrReauthenticates() async throws {
        var active = true
        let context = ContinuityAuthentication()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(), isActive: { active }, isBackground: { false }, protectedDataAvailable: { true })
        defer { lock.setEnabled(false) }
        lock.setEnabled(true); lock.install()
        context.reply?(true, nil); try await eventually { lock.canAccess }
        XCTAssertFalse(lock.privacyCoverVisible)
        active = false
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertFalse(lock.privacyCoverVisible); XCTAssertTrue(lock.contentVisible)
        active = true; lock.becameActive()
        XCTAssertFalse(lock.privacyCoverVisible); XCTAssertEqual(context.evaluations, 1)
    }
    func testSuccessfulInactiveAuthenticationRevealsLocalControlsBeforeSingleRemotePublication() async throws {
        var active = true, background = false
        let context = ContinuityAuthentication()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(), isActive: { active }, isBackground: { background }, protectedDataAvailable: { true })
        var publications = 0
        let observer = NotificationCenter.default.addObserver(forName: DirectAppLockV1.unlocked, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { publications += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer); lock.setEnabled(false) }
        lock.setEnabled(true); XCTAssertTrue(lock.privacyCoverVisible)
        let oldReply = try XCTUnwrap(context.reply)
        let policy = try XCTUnwrap(try fixture()["clientAdditions"] as? [String: Any])
        let appLock = try XCTUnwrap(policy["appLock"] as? [String: Any])
        XCTAssertEqual(appLock["successfulInactiveAuthenticationShowsCover"] as? Bool, false)
        active = false; oldReply(true, nil); try await eventually { !lock.authenticating }
        XCTAssertTrue(lock.canAccess); XCTAssertTrue(lock.canInteract); XCTAssertTrue(lock.contentVisible)
        XCTAssertFalse(lock.privacyCoverVisible); XCTAssertEqual(publications, 0)
        XCTAssertFalse(lock.canResumeRemoteSession)
        XCTAssertEqual(appLock["remoteSessionResumeNeedsActiveAdmission"] as? Bool, true)
        active = true; lock.becameActive(); lock.becameActive()
        XCTAssertEqual(publications, 1)
        lock.background(); background = true; oldReply(true, nil)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(lock.canAccess); XCTAssertTrue(lock.privacyCoverVisible); XCTAssertEqual(publications, 1)
    }
    func testBackgroundBetweenLocalSuccessAndActivationRevokesHandoffWithoutRemoteResume() async throws {
        var active = true, background = false
        let context = ContinuityAuthentication(), timings = DirectUnlockTimingsV1()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(), unlockTimings: timings,
                                   isActive: { active }, isBackground: { background }, protectedDataAvailable: { true })
        var publications = 0
        let observer = NotificationCenter.default.addObserver(forName: DirectAppLockV1.unlocked, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { publications += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer); lock.setEnabled(false) }
        lock.setEnabled(true); let reply = try XCTUnwrap(context.reply)
        active = false; lock.becameInactive(); reply(true, nil)
        try await eventually { lock.canInteract }
        XCTAssertFalse(lock.canResumeRemoteSession); XCTAssertEqual(publications, 0)
        background = true; lock.background()
        XCTAssertFalse(lock.canAccess); XCTAssertFalse(lock.canInteract); XCTAssertTrue(lock.privacyCoverVisible)
        XCTAssertEqual(timings.records.last?.outcome, .revoked)
        reply(true, nil); try await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(publications, 0); XCTAssertFalse(lock.canResumeRemoteSession)
        background = false; active = true; lock.receivedActivationNotification()
        XCTAssertTrue(lock.authenticating); XCTAssertEqual(context.evaluations, 2)
        XCTAssertFalse(lock.canAccess); XCTAssertEqual(publications, 0)
        context.reply?(true, nil); try await eventually { lock.canResumeRemoteSession }
        XCTAssertEqual(publications, 1)
    }
    func testGraceForegroundPresentationDoesNotGrantInactiveAccessAndExpiryRemasks() async throws {
        var time: TimeInterval = 100, active = true, protected = true
        let context = ContinuityAuthentication()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(), now: { time }, isActive: { active }, isBackground: { false }, protectedDataAvailable: { protected })
        defer { lock.setEnabled(false) }
        lock.setGraceSeconds(30); lock.setEnabled(true)
        context.reply?(true, nil); try await eventually { lock.canAccess }
        active = false; lock.background(); XCTAssertTrue(lock.privacyCoverVisible)
        time += 1; lock.prepareForeground()
        XCTAssertFalse(lock.privacyCoverVisible); XCTAssertTrue(lock.contentVisible); XCTAssertFalse(lock.canAccess)
        active = true; lock.becameActive()
        XCTAssertTrue(lock.canAccess); XCTAssertEqual(context.evaluations, 1)
        active = false; lock.background(); time += 30; lock.prepareForeground()
        XCTAssertTrue(lock.privacyCoverVisible); XCTAssertFalse(lock.contentVisible)
        protected = false; lock.protectedDataLost(); lock.prepareForeground()
        XCTAssertTrue(lock.privacyCoverVisible); XCTAssertFalse(lock.canAccess)
    }
    func testProtectedDataLossRestartAndLateRepliesCannotReuseUnlock() async throws {
        var time: TimeInterval = 100
        let defaults = isolatedDefaults(), context = ContinuityAuthentication()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: defaults, now: { time }, isActive: { true }, protectedDataAvailable: { true })
        defer { lock.setEnabled(false) }
        lock.setGraceSeconds(30); lock.setEnabled(true)
        context.reply?(true, nil); try await Task.sleep(for: .milliseconds(30)); XCTAssertTrue(lock.canAccess)
        lock.background(); context.reply?(true, nil); try await Task.sleep(for: .milliseconds(30)); XCTAssertFalse(lock.canAccess)
        lock.protectedDataLost(); time += 1; lock.becameActive()
        XCTAssertFalse(lock.canAccess); XCTAssertTrue(lock.authenticating)
        let restarted = DirectAppLockV1(contextFactory: { ContinuityAuthentication() }, defaults: defaults, isActive: { true }, protectedDataAvailable: { true })
        XCTAssertFalse(restarted.canAccess, "Grace is never persisted across process restart"); restarted.setEnabled(false)
    }
    func testForegroundEvidenceRenewsConnectedFreshnessAndBackgroundNeverPublishesConnected() async throws {
        var date = Date(timeIntervalSince1970: 1000)
        let policy = try XCTUnwrap(try fixture()["recoveryPolicy"] as? [String: Any])
        XCTAssertEqual(policy["terminalReturnRenewsEvidence"] as? Bool, false)
        let backend = ContinuityActivityBackend()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", address: "test.local")
        let owner = VNCSessionActivityController(mac: mac, defaults: isolatedDefaults(), backend: backend, now: { date })
        owner.setPhase("connected"); await owner.waitForUpdates()
        let first = try XCTUnwrap(backend.contents.last?.staleDate)
        date.addTimeInterval(20); owner.setPhase("connected"); await owner.waitForUpdates()
        XCTAssertGreaterThan(try XCTUnwrap(backend.contents.last?.staleDate), first)
        let verifiedUntil = try XCTUnwrap(backend.contents.last?.staleDate)
        owner.setForeground(false); owner.setPhase("paused"); await owner.waitForUpdates()
        XCTAssertEqual(backend.contents.last?.state.phase, .paused)
        date.addTimeInterval(120); owner.setForeground(true); owner.setPhase("connected", verified: false); await owner.waitForUpdates()
        XCTAssertEqual(backend.contents.last?.staleDate, verifiedUntil, "Returning to a local socket does not manufacture peer evidence")
        XCTAssertLessThan(try XCTUnwrap(backend.contents.last?.staleDate), date)
        owner.setPhase("connected"); await owner.waitForUpdates()
        XCTAssertGreaterThan(try XCTUnwrap(backend.contents.last?.staleDate), date, "The first fresh peer evidence after a long pause must publish immediately")
        owner.setPhase("ended"); await owner.waitForUpdates(); XCTAssertTrue(backend.ids.isEmpty)
    }
    private func coordinator(backend: ContinuityActivityBackend) throws -> (VNCRemoteDesktopView.Coordinator, CompanionVNCViewer, ContinuitySession, URL) {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let library = DirectMacLibraryV1(url: folder.appending(path: "macs.json"))
        XCTAssertTrue(library.save(id: nil, name: "Synthetic Mac", address: "test.local"))
        let mac = try XCTUnwrap(library.macs.first)
        let files = DirectFilesSession(mac: mac, libraryURL: library.storageURL)
        let activity = VNCSessionActivityController(mac: mac, defaults: isolatedDefaults(), backend: backend)
        let coordinator = VNCRemoteDesktopView.Coordinator(mac: mac, files: files, activityController: activity)
        let viewer = CompanionVNCViewer(); viewer.loadViewIfNeeded()
        let session = ContinuitySession(); viewer.session = session; coordinator.viewer = viewer
        coordinator.observeActivity()
        return (coordinator, viewer, session, folder)
    }
    func testSlowActivityUpdateDoesNotKillReleasedDesktopTransport() async throws {
        let backend = ContinuityActivityBackend()
        let (coordinator, viewer, session, folder) = try coordinator(backend: backend)
        defer { backend.release(); coordinator.stopObserving(); coordinator.activity.finish(); viewer.stop(); try? FileManager.default.removeItem(at: folder) }
        coordinator.activity.setPhase("connected"); await coordinator.activity.waitForUpdates(); backend.blocked = true
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertEqual(session.pauses, 0)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try await Task.sleep(for: .milliseconds(1150))
        XCTAssertEqual(session.pauses, 1); XCTAssertEqual(session.stops, 0); XCTAssertTrue(session.alive)
        backend.release(); await coordinator.activity.waitForUpdates()
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(session.resumes, 1)
    }
    func testUnfinishedInputReleaseStillStopsAtBoundAndEndsActivity() async throws {
        let backend = ContinuityActivityBackend()
        let (coordinator, viewer, session, folder) = try coordinator(backend: backend)
        defer { backend.release(); coordinator.stopObserving(); coordinator.activity.finish(); viewer.stop(); try? FileManager.default.removeItem(at: folder) }
        coordinator.activity.setPhase("connected"); await coordinator.activity.waitForUpdates(); session.completeRelease = false; backend.blocked = true
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try await eventually { backend.reply != nil }
        let id = try XCTUnwrap(backend.ids.first)
        try await Task.sleep(for: .milliseconds(1150))
        XCTAssertFalse(session.alive); XCTAssertGreaterThan(session.stops, 0); XCTAssertTrue(backend.ids.isEmpty)
        XCTAssertTrue(backend.endedIDs.contains(id)); XCTAssertNotNil(backend.reply)
        backend.release(); await coordinator.activity.waitForUpdates()
    }
    private func capture(_ host: UIViewController, size: CGSize, name: String) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        window.frame = .init(origin: .zero, size: size); window.rootViewController = host; window.makeKeyAndVisible()
        window.layoutIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNotNil(host.view.window)
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testStaleActivityAndUnlockPreferenceRenderWithoutClaimingRetainedShell() throws {
        let mac = RemoteSessionActivityAttributes(macID: UUID(), macName: "Synthetic Mac", kind: .terminal)
        let host = UIHostingController(rootView: RemoteSessionActivityCard(attributes: mac, phase: .connected,
            isStale: true, activityID: "synthetic"))
        try capture(host, size: .init(width: 368, height: 220), name: "Stale session offers Open to Check")
        let paused = UIHostingController(rootView: RemoteSessionActivityCard(attributes: mac, phase: .paused, isStale: false, activityID: "synthetic"))
        try capture(paused, size: .init(width: 368, height: 220), name: "Paused Terminal offers return navigation")
        let additions = try XCTUnwrap(try fixture()["clientAdditions"] as? [String: Any])
        let lock = try XCTUnwrap(additions["appLock"] as? [String: Any]); XCTAssertEqual(lock["defaultGraceSeconds"] as? Int, 0); XCTAssertEqual(lock["graceClock"] as? String, "continuous-including-device-sleep")
    }
    func testExplicitUnlockDelaySettingsRenderWithImmediateDefault() async throws {
        let context = ContinuityAuthentication()
        let lock = DirectAppLockV1(contextFactory: { context }, defaults: isolatedDefaults(), isActive: { true }, protectedDataAvailable: { true })
        defer { lock.setEnabled(false) }
        lock.setEnabled(true); XCTAssertEqual(lock.graceSeconds, 0)
        let host = UIHostingController(rootView: Form { DirectAppUnlockSection(lock: lock) })
        context.reply?(true, nil); try await Task.sleep(for: .milliseconds(30))
        try capture(host, size: .init(width: 390, height: 320), name: "Explicit unlock delay preference")
        lock.setGraceSeconds(30); XCTAssertEqual(lock.graceSeconds, 30)
    }
}
