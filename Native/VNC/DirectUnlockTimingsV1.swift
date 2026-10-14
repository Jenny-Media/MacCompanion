#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import SwiftUI
import UIKit

/// Fixed names and monotonic offsets only. The recorder never accepts user data.
@MainActor final class DirectUnlockTimingsV1 {
    enum Phase: String, Codable, Sendable {
        case requested, evaluationIssued, authenticationCallback, authenticationHandled
        case activationNotification, activeAdmission, coverRemoved
        case unlockNotification, unlockObserversReturned
        case libraryWaitStarted, libraryReadable, libraryUnreadable
        case libraryDisplayTick, desktopDisplayTick, terminalDisplayTick
    }
    enum Outcome: String, Codable, Sendable { case pending, success, failed, unavailable, revoked, replaced, preferenceChanged }
    enum LibraryState: String, Codable, Sendable { case notStarted, waiting, readable, unreadable }
    struct Event: Codable, Sendable { let phase: Phase; let milliseconds: Double }
    struct Record: Codable, Sendable {
        let sequence: Int
        let activeAtRequest: Bool
        let libraryAtRequest: LibraryState
        var outcome: Outcome
        var events: [Event]
    }
    struct Snapshot: Encodable, Sendable {
        let schema = 1
        let clock = "continuous-milliseconds-since-recorder-start"
        let frameMeaning = "eligible-native-display-tick-proxy"
        let library: [Event]
        let records: [Record]
    }
    #if DEBUG
    private static let supported = true
    #else
    private static let supported = false
    #endif
    private let enabled: Bool
    private let persist: Bool
    private let storageURL: URL?
    private let clock: @Sendable () -> ContinuousClock.Instant
    private let origin: ContinuousClock.Instant
    private let writer = DispatchQueue(label: "MacCompanion.unlock-timing-snapshot", qos: .utility)
    private var token: UUID?
    private var sequence = 0
    private var libraryState = LibraryState.notStarted
    private var libraryEvents: [Event] = []
    private(set) var records: [Record] = []
    init(enabled: Bool = true, persist: Bool = false, storageURL: URL? = nil,
         clock: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) {
        self.enabled = Self.supported && enabled; self.persist = persist; self.storageURL = storageURL
        self.clock = clock; origin = clock()
    }
    var callbackClock: @Sendable () -> ContinuousClock.Instant { clock }
    var snapshot: Snapshot { Snapshot(library: libraryEvents, records: records) }
    var pendingToken: UUID? { token }
    func begin(active: Bool) -> UUID? {
        guard enabled else { return nil }
        finish(.replaced)
        sequence += 1; let id = UUID(); token = id
        records.append(Record(sequence: sequence, activeAtRequest: active, libraryAtRequest: libraryState,
                              outcome: .pending, events: []))
        if records.count > 8 { records.removeFirst(records.count - 8) }
        mark(.requested, token: id); return id
    }
    private func event(_ phase: Phase, at instant: ContinuousClock.Instant) -> Event {
        let value = origin.duration(to: instant).components
        return Event(phase: phase, milliseconds: Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15)
    }
    func mark(_ phase: Phase, token id: UUID?, at instant: ContinuousClock.Instant? = nil) {
        guard enabled, let id, token == id, !records.isEmpty,
              !records[records.count - 1].events.contains(where: { $0.phase == phase }),
              records[records.count - 1].events.count < 16 else { return }
        records[records.count - 1].events.append(event(phase, at: instant ?? clock()))
    }
    func finish(_ outcome: Outcome, token id: UUID? = nil) {
        guard enabled, token != nil, id == nil || token == id, !records.isEmpty else { return }
        records[records.count - 1].outcome = outcome; token = nil; save()
    }
    func libraryWaitStarted() {
        guard enabled, libraryState == .notStarted else { return }
        libraryState = .waiting; libraryEvents.append(event(.libraryWaitStarted, at: clock()))
    }
    func libraryWaitFinished(readable: Bool) {
        guard enabled, libraryState == .waiting else { return }
        libraryState = readable ? .readable : .unreadable
        libraryEvents.append(event(readable ? .libraryReadable : .libraryUnreadable, at: clock())); save()
    }
    func waitForWrites() async {
        await withCheckedContinuation { continuation in
            writer.async { continuation.resume() }
        }
    }
    private func save() {
        guard enabled, persist else { return }
        let snapshot = snapshot
        let url = storageURL ?? URL.cachesDirectory.appending(path: "UnlockPhaseTimings-v1.json")
        // Encoding and ordered, atomic writes are outside the admission actor.
        writer.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

#if DEBUG
/// A refresh callback is a frame opportunity, not proof of displayed pixels.
struct DirectUnlockFrameProbe: UIViewRepresentable {
    let lock: DirectAppLockV1
    let token: UUID?
    let phase: DirectUnlockTimingsV1.Phase
    var enabled = true
    func makeUIView(context: Context) -> DirectUnlockFrameProbeView { DirectUnlockFrameProbeView() }
    func updateUIView(_ view: DirectUnlockFrameProbeView, context: Context) {
        view.configure(lock: lock, token: token, phase: phase, enabled: enabled)
    }
    static func dismantleUIView(_ view: DirectUnlockFrameProbeView, coordinator: ()) { view.stop() }
}
@MainActor private final class DirectUnlockDisplayTarget: NSObject {
    weak var view: DirectUnlockFrameProbeView?
    init(_ view: DirectUnlockFrameProbeView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) { view?.tick() }
}
@MainActor final class DirectUnlockFrameProbeView: UIView {
    private weak var lock: DirectAppLockV1?
    private var token: UUID?
    private var phase = DirectUnlockTimingsV1.Phase.libraryDisplayTick
    private var enabled = false
    private var link: CADisplayLink?
    var sampling: Bool { link != nil }
    override init(frame: CGRect) {
        super.init(frame: frame); isUserInteractionEnabled = false; isAccessibilityElement = false
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func configure(lock: DirectAppLockV1, token: UUID?, phase: DirectUnlockTimingsV1.Phase, enabled: Bool) {
        if self.token != token || self.lock !== lock || self.phase != phase { stop() }
        self.lock = lock; self.token = token; self.phase = phase; self.enabled = enabled
        reconcile()
    }
    private var eligible: Bool {
        guard enabled, let lock, let token, lock.unlockTimingToken == token,
              lock.canInteract, lock.contentVisible, !lock.privacyCoverVisible,
              let window, !window.isHidden, window.windowScene?.activationState == .foregroundActive,
              bounds.width > 0, bounds.height > 0 else { return false }
        var ancestor: UIView? = self
        while let view = ancestor {
            if view.isHidden || view.alpha <= 0 { return false }
            ancestor = view.superview
        }
        return true
    }
    override func didMoveToWindow() { super.didMoveToWindow(); reconcile() }
    override func layoutSubviews() { super.layoutSubviews(); reconcile() }
    private func reconcile() {
        guard eligible else { stop(); return }
        if link == nil {
            let link = CADisplayLink(target: DirectUnlockDisplayTarget(self), selector: #selector(DirectUnlockDisplayTarget.tick(_:)))
            self.link = link; link.add(to: .main, forMode: .common)
        }
    }
    func tick() {
        defer { stop() }
        guard eligible, let token else { return }
        lock?.recordUnlockDisplayTick(token: token, phase: phase)
    }
    func stop() { link?.invalidate(); link = nil }
    isolated deinit { link?.invalidate() }
}
#endif
#endif
