#if os(macOS)
import AppKit
import CompanionDomain
import CompanionNetworkPlatform
import CompanionWire
import CoreGraphics
import Dispatch
import Foundation
import SystemConfiguration

package struct MacAgentPublicConsoleSessionFactsV1: Equatable, Sendable {
    package let processUserID: UInt32
    package let windowSessionUserID: UInt32?
    package let onConsole: Bool?
    package let loginDone: Bool?
    package let primaryConsoleUserID: UInt32?

    package init(
        processUserID: UInt32,
        windowSessionUserID: UInt32?,
        onConsole: Bool?,
        loginDone: Bool?,
        primaryConsoleUserID: UInt32?
    ) {
        self.processUserID = processUserID
        self.windowSessionUserID = windowSessionUserID
        self.onConsole = onConsole
        self.loginDone = loginDone
        self.primaryConsoleUserID = primaryConsoleUserID
    }
}

public struct MacAgentConservativeRequestContextSnapshotV1:
    Equatable,
    Sendable
{
    public let hostState: HostState
    public let revision: UInt64
    public let started: Bool
    public let finished: Bool

    public init(
        hostState: HostState,
        revision: UInt64,
        started: Bool,
        finished: Bool
    ) {
        self.hostState = hostState
        self.revision = revision
        self.started = started
        self.finished = finished
    }
}

public enum MacAgentConservativeRequestContextProductErrorV1:
    Error,
    Equatable,
    Sendable
{
    case alreadyStarted
    case terminal
}

/// Owns live request clocks and the public macOS console-session view. Exact
/// same-UID, on-console, completed-login facts admit the logged-in MVP as
/// `userSessionActive`; incomplete, switched-user, sleep, and logout evidence
/// remains closed. Public facts do not distinguish screen lock, so this owner
/// never publishes `userSessionLocked`.
public final class MacAgentConservativeRequestContextProductV1:
    @unchecked Sendable
{
    private enum EventV1 {
        case willSleep
        case didWake
        case willPowerOff
        case ambiguousSessionChange
        case sessionResignedActive
    }

    private let lock = NSLock()
    private let notificationCenter: NotificationCenter
    private let observedObject: AnyObject?
    private let facts: @Sendable () -> MacAgentPublicConsoleSessionFactsV1
    private let wallNow: @Sendable () -> Int64
    private let monotonicNow: @Sendable () -> UInt64
    private let makeMessageID: @Sendable () -> WireUUID

    private var observers: [NSObjectProtocol] = []
    private var hostState: HostState = .otherConsoleUserActive
    private var revision: UInt64 = 0
    private var started = false
    private var finished = false
    private var terminalNotificationReceived = false

    public convenience init() {
        self.init(
            notificationCenter: NSWorkspace.shared.notificationCenter,
            observedObject: NSWorkspace.shared,
            facts: Self.currentPublicFacts,
            wallNow: {
                Int64(
                    (Date().timeIntervalSince1970 * 1_000).rounded(.down)
                )
            },
            monotonicNow: {
                DispatchTime.now().uptimeNanoseconds / 1_000_000
            },
            makeMessageID: { WireUUID(UUID()) }
        )
    }

    package init(
        notificationCenter: NotificationCenter,
        observedObject: AnyObject?,
        facts: @escaping @Sendable () -> MacAgentPublicConsoleSessionFactsV1,
        wallNow: @escaping @Sendable () -> Int64,
        monotonicNow: @escaping @Sendable () -> UInt64,
        makeMessageID: @escaping @Sendable () -> WireUUID
    ) {
        self.notificationCenter = notificationCenter
        self.observedObject = observedObject
        self.facts = facts
        self.wallNow = wallNow
        self.monotonicNow = monotonicNow
        self.makeMessageID = makeMessageID
    }

    deinit {
        let retainedObservers = observers
        for observer in retainedObservers {
            notificationCenter.removeObserver(observer)
        }
    }

    public func start() throws {
        lock.lock()
        guard !finished else {
            lock.unlock()
            throw MacAgentConservativeRequestContextProductErrorV1.terminal
        }
        guard !started else {
            lock.unlock()
            throw MacAgentConservativeRequestContextProductErrorV1
                .alreadyStarted
        }

        let observer = notificationCenter.addObserver(
            forName: nil,
            object: observedObject,
            queue: nil
        ) { [weak self] notification in
            self?.receive(notification)
        }
        observers = [observer]
        started = true
        let initialRevision = revision
        lock.unlock()

        let sampledState = Self.conservativeHostState(for: facts())
        lock.lock()
        defer { lock.unlock() }
        guard !finished,
              !terminalNotificationReceived,
              revision == initialRevision
        else {
            return
        }
        publishLocked(sampledState)
    }

    public func finish() {
        let retainedObservers: [NSObjectProtocol]
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        terminalNotificationReceived = true
        publishLocked(.serviceStoppingForLogout)
        retainedObservers = observers
        observers.removeAll()
        lock.unlock()

        for observer in retainedObservers {
            notificationCenter.removeObserver(observer)
        }
    }

    public func snapshot() -> MacAgentConservativeRequestContextSnapshotV1 {
        lock.lock()
        defer { lock.unlock() }
        return MacAgentConservativeRequestContextSnapshotV1(
            hostState: hostState,
            revision: revision,
            started: started,
            finished: finished
        )
    }

    public func primaryRequestContext() -> NetworkHostRequestContextV0 {
        NetworkHostRequestContextV0(
            hostState: currentHostState(),
            wallNowUnixMilliseconds: wallNow(),
            monotonicNowMilliseconds: monotonicNow(),
            responseMessageID: makeMessageID()
        )
    }

    public func pairingRequestContext() -> NetworkHostPairingRequestContextV0 {
        NetworkHostPairingRequestContextV0(
            wallNowUnixMilliseconds: wallNow(),
            monotonicNowMilliseconds: monotonicNow(),
            responseMessageID: makeMessageID()
        )
    }

    public var primaryContext:
        @Sendable () -> NetworkHostRequestContextV0
    {
        { [self] in primaryRequestContext() }
    }

    public var pairingContext:
        @Sendable () -> NetworkHostPairingRequestContextV0
    {
        { [self] in pairingRequestContext() }
    }

    package static func conservativeHostState(
        for facts: MacAgentPublicConsoleSessionFactsV1
    ) -> HostState {
        if facts.windowSessionUserID == facts.processUserID,
           facts.onConsole == true,
           facts.loginDone == true {
            return .userSessionActive
        }

        // CGSessionCopyCurrentDictionary may return nil outside a Quartz GUI
        // session, including for the per-user background Agent. Fall back only
        // to SystemConfiguration's primary logged-in console identity, and
        // never use it to override contradictory Quartz facts.
        guard facts.primaryConsoleUserID == facts.processUserID,
              facts.windowSessionUserID.map({ $0 == facts.processUserID })
                ?? true,
              facts.onConsole != false,
              facts.loginDone != false else {
            return .otherConsoleUserActive
        }
        return .userSessionActive
    }

    private func currentHostState() -> HostState {
        lock.lock()
        defer { lock.unlock() }
        return hostState
    }

    private func receive(_ notification: Notification) {
        guard let event = Self.event(for: notification.name) else { return }
        let sampledState: HostState?
        switch event {
        case .didWake, .ambiguousSessionChange:
            sampledState = Self.conservativeHostState(for: facts())
        case .willSleep, .willPowerOff, .sessionResignedActive:
            sampledState = nil
        }

        lock.lock()
        defer { lock.unlock() }
        guard started, !finished, !terminalNotificationReceived else { return }

        switch event {
        case .willSleep:
            publishLocked(.hostPreparingForSleep)
        case .didWake:
            publishLocked(sampledState ?? .otherConsoleUserActive)
        case .willPowerOff:
            terminalNotificationReceived = true
            publishLocked(.serviceStoppingForLogout)
        case .ambiguousSessionChange:
            guard hostState != .hostPreparingForSleep else { return }
            publishLocked(sampledState ?? .otherConsoleUserActive)
        case .sessionResignedActive:
            publishLocked(.otherConsoleUserActive)
        }
    }

    private func publishLocked(_ newValue: HostState) {
        guard hostState != newValue else { return }
        guard revision < UInt64.max else {
            hostState = .serviceStoppingForLogout
            terminalNotificationReceived = true
            return
        }
        hostState = newValue
        revision += 1
    }

    private static func event(for name: Notification.Name) -> EventV1? {
        switch name {
        case NSWorkspace.willSleepNotification:
            return .willSleep
        case NSWorkspace.didWakeNotification:
            return .didWake
        case NSWorkspace.willPowerOffNotification:
            return .willPowerOff
        case NSWorkspace.sessionDidBecomeActiveNotification,
             NSWorkspace.screensDidSleepNotification,
             NSWorkspace.screensDidWakeNotification:
            return .ambiguousSessionChange
        case NSWorkspace.sessionDidResignActiveNotification:
            return .sessionResignedActive
        default:
            return nil
        }
    }

    package static func currentPublicFacts()
        -> MacAgentPublicConsoleSessionFactsV1
    {
        let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
        let userID = (dictionary?[kCGSessionUserIDKey as String] as? NSNumber)?
            .uint32Value
        let onConsole = (dictionary?[kCGSessionOnConsoleKey as String]
            as? NSNumber)?.boolValue
        let loginDone = (dictionary?[kCGSessionLoginDoneKey as String]
            as? NSNumber)?.boolValue
        var primaryConsoleUserID: uid_t = 0
        var primaryConsoleGroupID: gid_t = 0
        let primaryConsoleUser = SCDynamicStoreCopyConsoleUser(
            nil,
            &primaryConsoleUserID,
            &primaryConsoleGroupID
        )
        return MacAgentPublicConsoleSessionFactsV1(
            processUserID: getuid(),
            windowSessionUserID: userID,
            onConsole: onConsole,
            loginDone: loginDone,
            primaryConsoleUserID: primaryConsoleUser == nil
                ? nil
                : primaryConsoleUserID
        )
    }
}
#endif
