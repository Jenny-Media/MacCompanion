import CompanionInteractiveShared
import CompanionInteractiveWire

package enum ClientNativeSurfaceRecoveryPolicyV0 {
    package static func permitsDesktopRecovery(kind: InteractiveSurfaceKind,
        failure: InteractiveNativeVideoFailureV0?, primaryCurrent: Bool,
        foreground: Bool, now: UInt64, expiry: UInt64) -> Bool {
        guard [.application, .window].contains(kind), primaryCurrent, foreground, now < expiry else { return false }
        // Native enrollment loss requires a separate fresh Control check.
        return failure == .connectionFailed || failure == .incompatibleFrame || failure == .authorizationLost
    }
}
