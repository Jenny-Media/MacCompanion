#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import ActivityKit
import Foundation

@MainActor protocol RemoteSessionActivityBackend {
    var enabled: Bool { get }
    func existingIDs() -> [String]
    func start(_ attributes: RemoteSessionActivityAttributes, content: ActivityContent<RemoteSessionActivityAttributes.ContentState>) throws -> String
    func update(_ id: String, content: ActivityContent<RemoteSessionActivityAttributes.ContentState>) async
    func end(_ id: String) async
}

@MainActor struct ActivityKitSessionBackend: RemoteSessionActivityBackend {
    var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    func existingIDs() -> [String] { Activity<RemoteSessionActivityAttributes>.activities.map(\.id) }
    func start(_ attributes: RemoteSessionActivityAttributes, content: ActivityContent<RemoteSessionActivityAttributes.ContentState>) throws -> String {
        try Activity.request(attributes: attributes, content: content, pushType: nil).id
    }
    func update(_ id: String, content: ActivityContent<RemoteSessionActivityAttributes.ContentState>) async {
        await Self.updateActivity(id, content: content)
    }
    nonisolated private static func updateActivity(_ id: String, content: ActivityContent<RemoteSessionActivityAttributes.ContentState>) async {
        if let activity = Activity<RemoteSessionActivityAttributes>.activities.first(where: { $0.id == id }) { await activity.update(content) }
    }
    func end(_ id: String) async { await Self.endActivity(id) }
    nonisolated private static func endActivity(_ id: String) async {
        if let activity = Activity<RemoteSessionActivityAttributes>.activities.first(where: { $0.id == id }) { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}

@MainActor final class VNCSessionActivityController {
    static let preferenceKey = "direct-session-live-activity-enabled-v1"
    static func enabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: preferenceKey) == nil || defaults.bool(forKey: preferenceKey)
    }
    private let backend: any RemoteSessionActivityBackend
    private let defaults: UserDefaults
    private let attributes: RemoteSessionActivityAttributes
    private var activityID: String?
    private var phase: RemoteSessionActivityAttributes.Phase?
    private var foreground = true
    private var connectedOnce = false
    private var dismissed = false
    private var finished = false
    private var preferenceEnabled: Bool
    private var work: Task<Void, Never>?
    init(mac: DirectMacRecordV1, defaults: UserDefaults = .standard, backend: any RemoteSessionActivityBackend = ActivityKitSessionBackend()) {
        self.defaults = defaults; self.backend = backend; self.preferenceEnabled = Self.enabled(in: defaults)
        attributes = .init(macID: mac.id, macName: mac.name)
        // A process restart must not leave a previous socket labeled connected.
        let orphaned = backend.existingIDs()
        work = Task { for id in orphaned { await backend.end(id) } }
    }
    func setForeground(_ value: Bool) { foreground = value; reconcileSoon() }
    func setPhase(_ value: String) {
        if value == "ended" { phase = nil; connectedOnce = false; reconcileSoon(); return }
        guard !finished, let next = RemoteSessionActivityAttributes.Phase(rawValue: value) else { return }
        if next == .connected { connectedOnce = true }
        guard phase != next else { return }
        phase = next; reconcileSoon()
    }
    func preferenceChanged() {
        let enabled = Self.enabled(in: defaults)
        if enabled && !preferenceEnabled { dismissed = false }
        preferenceEnabled = enabled; reconcileSoon()
    }
    func finish() { finished = true; phase = nil; reconcileSoon() }
    func ownsActivity(_ id: String) -> Bool { !finished && activityID == id }
    func waitForUpdates() async { await work?.value }
    private func reconcileSoon() {
        let previous = work
        work = Task { [self] in await previous?.value; await reconcile() }
    }
    private func reconcile() async {
        guard !finished, Self.enabled(in: defaults), backend.enabled, let phase, connectedOnce else {
            if let id = activityID { activityID = nil; await backend.end(id) }
            return
        }
        if let id = activityID, !backend.existingIDs().contains(id) { activityID = nil; dismissed = true }
        let content = ActivityContent(state: RemoteSessionActivityAttributes.ContentState(phase: phase),
            staleDate: Date().addingTimeInterval(phase == .paused ? 900 : 60))
        if let id = activityID { await backend.update(id, content: content) }
        else if foreground && !dismissed {
            // OS denial or user-disabled Live Activities never affects VNC.
            activityID = try? backend.start(attributes, content: content)
        }
    }
}
#endif
