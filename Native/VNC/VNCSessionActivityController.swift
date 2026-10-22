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
    private final class Owner {
        weak var controller: VNCSessionActivityController?
        init(_ controller: VNCSessionActivityController) { self.controller = controller }
    }
    private static var owners: [String: Owner] = [:]
    private static func orphanedIDs(in backend: any RemoteSessionActivityBackend) -> [String] {
        owners = owners.filter { $0.value.controller?.ownsActivity($0.key) == true }
        return backend.existingIDs().filter { owners[$0] == nil }
    }
    static func retireOrphanedActivities(backend: any RemoteSessionActivityBackend = ActivityKitSessionBackend()) async {
        // Capture IDs before the first suspension. A later session's activity
        // must never become a target of this cleanup.
        let orphaned = orphanedIDs(in: backend)
        for id in orphaned { await backend.end(id) }
    }
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
    private var startupRetirement: Task<Void, Never>?
    private var workGeneration: UInt64 = 0
    private var retirements: [UUID: Task<Void, Never>] = [:]
    private var dirty = false
    private let now: () -> Date
    private var phaseDate: Date?
    private var evidenceDate: Date?
    private var lastEvidencePublication: Date?
    init(mac: DirectMacRecordV1, kind: RemoteSessionActivityAttributes.Kind = .desktop, defaults: UserDefaults = .standard, backend: any RemoteSessionActivityBackend = ActivityKitSessionBackend(), now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults; self.backend = backend; self.preferenceEnabled = Self.enabled(in: defaults)
        self.now = now
        attributes = .init(macID: mac.id, macName: mac.name, kind: kind)
        // A process restart must not leave a previous socket labeled connected.
        let orphaned = Self.orphanedIDs(in: backend)
        if !orphaned.isEmpty {
            // This prerequisite outlives canceled status work and early ends.
            startupRetirement = Task { [backend] in
                for id in orphaned { await backend.end(id) }
            }
        }
    }
    func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value
        if !value { phaseDate = now() }
        reconcileSoon()
    }
    func setPhase(_ value: String, verified: Bool = true) {
        if value == "ended" {
            phase = nil; connectedOnce = false
            phaseDate = nil; evidenceDate = nil; lastEvidencePublication = nil
            retireActivity()
            return
        }
        guard !finished, let next = RemoteSessionActivityAttributes.Phase(rawValue: value) else { return }
        if next == .connected {
            connectedOnce = true
            if verified { evidenceDate = now() }
            if phase == next {
                if verified && foreground && (lastEvidencePublication.map { now().timeIntervalSince($0) >= 15 } ?? true) {
                    lastEvidencePublication = now(); reconcileSoon()
                }
                return
            }
            if verified { lastEvidencePublication = now() }
        }
        guard phase != next else { return }
        phaseDate = now()
        phase = next; reconcileSoon()
    }
    func preferenceChanged() {
        let enabled = Self.enabled(in: defaults)
        if enabled && !preferenceEnabled { dismissed = false }
        preferenceEnabled = enabled
        if !enabled { retireActivity() }
        else { reconcileSoon() }
    }
    func finish() { finished = true; phase = nil; retireActivity() }
    func ownsActivity(_ id: String) -> Bool { !finished && activityID == id }
    func waitForUpdates() async {
        while startupRetirement != nil || work != nil || !retirements.isEmpty {
            if let startup = startupRetirement { await startup.value; startupRetirement = nil }
            await work?.value
            for retirement in Array(retirements.values) { await retirement.value }
        }
    }
    private func retireActivity() {
        // ActivityKit updates can stall. A known end must not queue behind one,
        // and its late completion must not consume a replacement owner's work.
        workGeneration &+= 1
        work?.cancel(); work = nil; dirty = false
        guard let id = activityID else { return }
        activityID = nil
        Self.owners[id] = nil
        let token = UUID()
        retirements[token] = Task { [self] in
            await backend.end(id)
            retirements[token] = nil
        }
    }
    private func reconcileSoon() {
        dirty = true
        guard work == nil else { return }
        let generation = workGeneration
        work = Task { [self] in await drainUpdates(generation: generation) }
    }
    private func drainUpdates(generation: UInt64) async {
        if let startup = startupRetirement { await startup.value }
        guard generation == workGeneration else { return }
        startupRetirement = nil
        while generation == workGeneration && dirty {
            dirty = false; await reconcile()
        }
        if generation == workGeneration { work = nil }
    }
    private func reconcile() async {
        guard !finished, Self.enabled(in: defaults), backend.enabled, let phase, connectedOnce else {
            if let id = activityID { activityID = nil; Self.owners[id] = nil; await backend.end(id) }
            return
        }
        if let id = activityID, !backend.existingIDs().contains(id) { activityID = nil; Self.owners[id] = nil; dismissed = true }
        let visiblePhase: RemoteSessionActivityAttributes.Phase = foreground ? phase : .paused
        let verified = visiblePhase == .connected ? evidenceDate : phaseDate
        let content = ActivityContent(state: RemoteSessionActivityAttributes.ContentState(phase: visiblePhase),
            staleDate: (verified ?? now()).addingTimeInterval(60))
        if let id = activityID { await backend.update(id, content: content) }
        else if foreground && !dismissed {
            // OS denial or user-disabled Live Activities never affects VNC.
            activityID = try? backend.start(attributes, content: content)
            if let id = activityID { Self.owners[id] = Owner(self) }
        }
    }
}
#endif
