import CompanionInteractiveShared
import CompanionInteractiveWire

package enum ClientNativeSurfaceRecoveryPolicyV0 {
    package static func permitsDesktopRecovery(kind: InteractiveSurfaceKind,
        failure: InteractiveNativeVideoFailureV0?, primaryCurrent: Bool,
        foreground: Bool, now: UInt64, expiry: UInt64) -> Bool {
        guard [.desktop, .application, .window].contains(kind), primaryCurrent, foreground, now < expiry else { return false }
        // Native enrollment loss requires a separate fresh Control check.
        return failure == .connectionFailed || failure == .incompatibleFrame || failure == .authorizationLost
    }
}

/// Counts component recovery independently of surface UUIDs. A replacement
/// descriptor cannot reset the budget and create an endless enrollment loop.
package struct ClientNativeSurfaceRecoveryBudgetV1 {
    private var attempted = false
    private var healthySince: UInt64?
    package init() {}

    package mutating func presented(now: UInt64) {
        if healthySince == nil { healthySince = now }
    }
    package mutating func take(now: UInt64) -> Bool {
        if let healthySince, now >= healthySince, now - healthySince >= 30_000 {
            attempted = false
        }
        healthySince = nil
        guard !attempted else { return false }
        attempted = true
        return true
    }
    package mutating func userSelectedView() {
        attempted = false
        healthySince = nil
    }
    package mutating func interrupted() { healthySince = nil }
}
