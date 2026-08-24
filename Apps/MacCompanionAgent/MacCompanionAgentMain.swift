import CompanionAgentApplicationPlatform
import Darwin

/// Permanent per-user LaunchAgent process boundary.
///
/// The application platform first reconciles private release storage, durable
/// intent, and host identity, then selects exactly one hidden local service:
/// authenticated menu/readiness/status plus the single LAN product for
/// canonical enabled startup,
/// the exact durable bootstrap for canonical disabled startup, closed
/// authentication-only for durable recovery, and none before first unlock.
/// This executable cannot import LocalXPC, choose a profile, inject an
/// authority, or construct a second Mach-service owner.
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

        switch outcome {
        case .retryAfterFirstUnlock:
            exit(EXIT_FAILURE)
        case .running(let owner):
            await owner.waitForRestartRequest()
            await owner.finish()
        }
    }
}
