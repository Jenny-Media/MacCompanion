import CompanionAgentApplicationPlatform
import CompanionLocalXPCPlatform
import Darwin
import Dispatch

/// Permanent per-user LaunchAgent process boundary.
///
/// The process first reconciles its private release storage, durable desired
/// intent, and host identity behind a narrow activation-inert owner. Only a
/// ready preparation or durable recovery wait may open the existing same-team/
/// exact-menu-identifier authentication-only XPC handshake. First-unlock wait
/// exits so the configured launchd policy may retry. It starts no product XPC,
/// observer, listener, provider, process, login role, pairing, or readiness
/// path.
@main
enum MacCompanionAgentMain {
    static func main() async {
        let localXPC = MacLocalXPCServerV1(
            profile: .authenticationOnly
        ) { _ in
            // Authenticated connection events are intentionally not yet
            // converted into lifecycle readiness or method authority.
        }
        let retention: MacCompanionAgentInertStartupRetentionV1
        do {
            retention = try await MacCompanionAgentInertStartupCoordinatorV1
                .prepareAndStartAuthentication {
                    try localXPC.start()
                }
        } catch {
            // The coordinator retires any prepared owner before this escapes.
            exit(EXIT_FAILURE)
        }

        guard case .retryAfterFirstUnlock = retention else {
            withExtendedLifetime((retention, localXPC)) {
                dispatchMain()
            }
        }
        exit(EXIT_FAILURE)
    }
}
