import CompanionAgentNetworkPlatform
import CompanionAgentPlatform
import CompanionLocalXPCPlatform
import Darwin
import Dispatch

/// Permanent per-user LaunchAgent process boundary.
///
/// The process opens only its same-team/exact-menu-identifier local XPC
/// handshake. It creates no remote listener, key, store, status authority, or
/// method capability and never claims Agent readiness from an authenticated
/// hello alone.
@main
enum MacCompanionAgentMain {
    static func main() {
        do {
            let localXPC = MacLocalXPCServerV1 { _ in
                // Authenticated connection events are intentionally not yet
                // converted into lifecycle readiness or method authority.
            }
            try localXPC.start()
            withExtendedLifetime(localXPC) {
                dispatchMain()
            }
        } catch {
            // A process without its required local trust boundary must not
            // remain alive and appear serviceable.
            exit(EXIT_FAILURE)
        }
    }
}
