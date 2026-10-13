import ActivityKit
import LocalAuthentication
import SwiftUI
import XCTest
import Observation
@testable import Mac_Companion

private final class ContinuityAuthentication: LAContext, @unchecked Sendable {
    var reply: (@Sendable (Bool, (any Error)?) -> Void)?
    var evaluations = 0
    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool { true }
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
        try await eventually { lock.canAccess }
        XCTAssertFalse(lock.canInteract); XCTAssertFalse(lock.privacyCoverVisible)
        var observed = false
        withObservationTracking { _ = lock.canInteract } onChange: {
            MainActor.assumeIsolated { observed = true }
        }
        active = true; lock.becameActive()
        XCTAssertTrue(observed); XCTAssertTrue(lock.canInteract)
        lock.becameInactive(); XCTAssertFalse(lock.canInteract); XCTAssertTrue(lock.contentVisible)
        lock.becameActive(); XCTAssertTrue(lock.canInteract); XCTAssertEqual(authentication.evaluations, 1)
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
    func testSuccessfulInactiveAuthenticationHidesRealCoverBeforeSingleActivePublication() async throws {
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
        active = false; oldReply(true, nil); try await eventually { lock.canAccess }
        XCTAssertFalse(lock.privacyCoverVisible); XCTAssertEqual(publications, 0)
        active = true; lock.becameActive(); lock.becameActive()
        XCTAssertEqual(publications, 1)
        lock.background(); background = true; oldReply(true, nil)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(lock.canAccess); XCTAssertTrue(lock.privacyCoverVisible); XCTAssertEqual(publications, 1)
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
