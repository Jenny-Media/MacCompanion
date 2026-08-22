import CompanionAgentApplicationPlatform
import Darwin
import Dispatch

/// Permanent per-user LaunchAgent process boundary.
///
/// The application platform first reconciles private release storage, durable
/// intent, and host identity, then selects exactly one hidden local service:
/// authenticated readiness/status for canonical enabled startup,
/// authentication-only for disabled or durable recovery, and none before first
/// unlock. This executable cannot import LocalXPC, choose a profile, inject a
/// reader, or construct a second Mach-service owner.
@main
enum MacCompanionAgentMain {
    static func main() async {
        let outcome: MacCompanionAgentLocalServiceStartupOutcomeV1
        do {
            outcome = try await MacCompanionAgentLocalServiceStartupV1.start()
        } catch {
            // Startup joins the selected service's terminal cleanup and never
            // falls back to a different profile before an error escapes.
            exit(EXIT_FAILURE)
        }

        guard case .retryAfterFirstUnlock = outcome else {
            withExtendedLifetime(outcome) {
                dispatchMain()
            }
        }
        exit(EXIT_FAILURE)
    }
}
