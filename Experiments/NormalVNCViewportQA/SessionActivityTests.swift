import ActivityKit
import AppIntents
import SwiftUI
import XCTest
@testable import Mac_Companion

@MainActor private final class RecordingActivityBackend: RemoteSessionActivityBackend {
    var enabled = true
    var ids: [String] = []
    var events: [String] = []
    var nextID = "new"
    func existingIDs() -> [String] { ids }
    func start(_ attributes: RemoteSessionActivityAttributes, content: ActivityContent<RemoteSessionActivityAttributes.ContentState>) throws -> String {
        ids.append(nextID); events.append("start:" + content.state.phase.rawValue); return nextID
    }
    func update(_ id: String, content: ActivityContent<RemoteSessionActivityAttributes.ContentState>) async { events.append("update:" + content.state.phase.rawValue) }
    func end(_ id: String) async { events.append("end:" + id); ids.removeAll { $0 == id } }
}
private final class ActivityActionTestSession: CompanionVNCSession {
    var alive = true
    var stops = 0
    var resumes = 0
    override var running: Bool { alive }
    override func stop() { stops += 1; alive = false }
    override func resume() { resumes += 1 }
}
@MainActor final class SessionActivityTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "session-qa-" + UUID().uuidString)! }
    func testIndexedEndActionsCannotTargetRetiredOrOtherActivities() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(fixture["liveActivityEndCases"] as? [[String: Any]])
        for vector in cases {
            let backend = RecordingActivityBackend(); backend.nextID = vector["currentID"] as? String ?? "current"
            let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", address: "test.local")
            let owner = VNCSessionActivityController(mac: mac, defaults: defaults(), backend: backend)
            owner.setPhase("connected"); await owner.waitForUpdates()
            if vector["currentID"] is NSNull { owner.finish() }
            XCTAssertEqual(owner.ownsActivity(try XCTUnwrap(vector["requestedID"] as? String)), vector["endsViewer"] as? Bool)
            owner.finish(); await owner.waitForUpdates()
        }
    }
    func testEndIntentStopsThePausedViewerAndRetiresRecoveryOnlyOnce() async throws {
        guard ActivityKitSessionBackend().enabled else { throw XCTSkip("Live Activities disabled in Simulator settings") }
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic End Session QA", address: "test.local")
        var exits = 0
        let coordinator = VNCRemoteDesktopView.Coordinator(mac: mac, showMacs: { exits += 1 })
        let viewer = CompanionVNCViewer(); viewer.loadViewIfNeeded()
        let native = ActivityActionTestSession(); viewer.session = native; coordinator.viewer = viewer
        coordinator.observeActivity()
        defer { coordinator.stopObserving(); coordinator.activity.finish(); viewer.stop() }
        coordinator.activity.setPhase("connected"); await coordinator.activity.waitForUpdates()
        let id = try XCTUnwrap(Activity<RemoteSessionActivityAttributes>.activities.first(where: { $0.attributes.macID == mac.id })?.id)
        _ = try await EndRemoteSessionIntent(activityID: "unrelated").perform()
        XCTAssertTrue(native.alive); XCTAssertEqual(exits, 0)
        coordinator.activity.setForeground(false); coordinator.activity.setPhase("paused")
        await coordinator.activity.waitForUpdates()
        _ = try await EndRemoteSessionIntent(activityID: id).perform()
        await coordinator.activity.waitForUpdates()
        XCTAssertFalse(native.alive); XCTAssertGreaterThan(native.stops, 0); XCTAssertEqual(exits, 1)
        XCTAssertFalse(coordinator.activity.ownsActivity(id))
        XCTAssertFalse(ActivityKitSessionBackend().existingIDs().contains(id))
        viewer.foregrounded(); XCTAssertEqual(native.resumes, 0)
        _ = try await EndRemoteSessionIntent(activityID: id).perform()
        XCTAssertEqual(exits, 1); XCTAssertEqual(native.resumes, 0)
    }
    func testEndIntentDismissesOnlyItsOrphanWhenNoViewerExists() async throws {
        let backend = ActivityKitSessionBackend()
        guard backend.enabled else { throw XCTSkip("Live Activities disabled in Simulator settings") }
        let content = ActivityContent(state: RemoteSessionActivityAttributes.ContentState(phase: .paused), staleDate: Date().addingTimeInterval(900))
        let first = try backend.start(.init(macID: UUID(), macName: "Orphan QA"), content: content)
        let other = try backend.start(.init(macID: UUID(), macName: "Other QA"), content: content)
        _ = try await EndRemoteSessionIntent(activityID: first).perform()
        XCTAssertFalse(backend.existingIDs().contains(first)); XCTAssertTrue(backend.existingIDs().contains(other))
        await backend.end(other)
    }
    func testActivityCardsRenderNamesStatesAndActionsAtPhoneWidth() throws {
        let attributes = RemoteSessionActivityAttributes(macID: UUID(), macName: "A Mac With A Very Long User Assigned Name")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: VStack(spacing: 8) {
            ForEach([RemoteSessionActivityAttributes.Phase.connected, .paused, .reconnecting], id: \.self) { phase in
                RemoteSessionActivityCard(attributes: attributes, phase: phase, isStale: false, activityID: "synthetic")
                    .background(.black, in: RoundedRectangle(cornerRadius: 20))
            }
            RemoteSessionActivityCard(attributes: attributes, phase: .connected, isStale: true, activityID: "synthetic")
                .background(.black, in: RoundedRectangle(cornerRadius: 20))
        }.frame(width: 320).preferredColorScheme(.dark))
        window.rootViewController = controller; window.makeKeyAndVisible(); window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertNotNil(controller.view.window)
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = "Synthetic session activity cards"
        attachment.lifetime = .keepAlways; add(attachment)
        window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
    }
    func testExpandedIslandContentFitsNarrowWidthsAndLargerText() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for width: CGFloat in [280, 320, 368] {
            for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
                let content = RemoteSessionExpandedContent(
                    attributes: .init(macID: UUID(), macName: "A Mac With A Very Long User Assigned Name"),
                    phase: .reconnecting, isStale: false, activityID: "synthetic")
                    .foregroundStyle(.white).preferredColorScheme(.dark)
                    .environment(\.dynamicTypeSize, size)
                let controller = UIHostingController(rootView: content)
                controller.safeAreaRegions = []
                window.rootViewController = controller; window.makeKeyAndVisible(); window.layoutIfNeeded()
                let measured = controller.sizeThatFits(in: CGSize(width: width, height: 500))
                // Leave room above this inset full-width region for the camera cutout.
                XCTAssertLessThanOrEqual(measured.height, 132, "width=\(width), text=\(size), height=\(measured.height)")
                controller.view.frame = CGRect(x: 20, y: 100, width: width, height: measured.height)
                controller.view.backgroundColor = .black
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                let image = UIGraphicsImageRenderer(size: controller.view.bounds.size).image { _ in
                    controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Expanded island \(Int(width)) \(size)"
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }
    func testStatusOptOutAndDismissalAreIndependentOfRecovery() async throws {
        let defaults = defaults(), backend = RecordingActivityBackend()
        backend.ids = ["orphan"]
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", address: "test.local")
        let owner = VNCSessionActivityController(mac: mac, defaults: defaults, backend: backend)
        XCTAssertTrue(VNCSessionActivityController.enabled(in: defaults))
        owner.setPhase("reconnecting"); await owner.waitForUpdates()
        XCTAssertEqual(backend.events, ["end:orphan"])
        owner.setPhase("connected"); await owner.waitForUpdates()
        XCTAssertEqual(backend.events.last, "start:connected")
        owner.setForeground(false); owner.setPhase("paused"); await owner.waitForUpdates()
        XCTAssertEqual(backend.events.last, "update:paused")
        defaults.set(false, forKey: VNCSessionActivityController.preferenceKey); owner.preferenceChanged(); await owner.waitForUpdates()
        XCTAssertEqual(backend.events.last, "end:new")
        defaults.set(true, forKey: VNCSessionActivityController.preferenceKey); owner.preferenceChanged(); await owner.waitForUpdates()
        XCTAssertTrue(backend.ids.isEmpty) // foreground is required for activity creation
        owner.setForeground(true); owner.setPhase("connected"); await owner.waitForUpdates()
        XCTAssertEqual(backend.events.last, "update:connected")
        backend.ids = []; owner.setPhase("paused"); await owner.waitForUpdates()
        owner.setPhase("connected"); await owner.waitForUpdates()
        XCTAssertTrue(backend.ids.isEmpty) // respect dismissal until a deliberate opt-in
        owner.finish(); owner.setPhase("connected"); await owner.waitForUpdates()
        XCTAssertTrue(backend.ids.isEmpty)
    }
    func testActualActivityKitStartsPausesAndEnds() async throws {
        let backend = ActivityKitSessionBackend()
        guard backend.enabled else { throw XCTSkip("Live Activities disabled in Simulator settings") }
        let attrs = RemoteSessionActivityAttributes(macID: UUID(), macName: "Mac Companion QA")
        let id = try backend.start(attrs, content: ActivityContent(state: .init(phase: .connected), staleDate: Date().addingTimeInterval(60)))
        XCTAssertTrue(backend.existingIDs().contains(id))
        try await Task.sleep(for: .seconds(1))
        await backend.update(id, content: ActivityContent(state: .init(phase: .paused), staleDate: Date().addingTimeInterval(900)))
        // ActivityKit publishes its process-local snapshot asynchronously after update returns.
        for _ in 0..<40 {
            if Activity<RemoteSessionActivityAttributes>.activities.first(where: { $0.id == id })?.content.state.phase == .paused { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(Activity<RemoteSessionActivityAttributes>.activities.first(where: { $0.id == id })?.content.state.phase, .paused)
        await backend.end(id)
        XCTAssertFalse(backend.existingIDs().contains(id))
    }
    func testDisabledSystemActivitiesDoNotStartAndDeepLinksAreBounded() async throws {
        let backend = RecordingActivityBackend(); backend.enabled = false
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", address: "test.local")
        let owner = VNCSessionActivityController(mac: mac, defaults: defaults(), backend: backend)
        owner.setPhase("connected"); await owner.waitForUpdates(); XCTAssertTrue(backend.events.isEmpty)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for c in try XCTUnwrap(fixture["resumeURLCases"] as? [[String: Any]]) {
            let link = try XCTUnwrap(URL(string: try XCTUnwrap(c["url"] as? String)))
            XCTAssertEqual(RemoteSessionActivityAttributes.resumeMacID(from: link) != nil, c["valid"] as? Bool)
        }
    }
}
