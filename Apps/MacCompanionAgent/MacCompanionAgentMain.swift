import CompanionAgentNetworkPlatform
import CompanionAgentPlatform
import Dispatch

/// Permanent per-user LaunchAgent process boundary.
///
/// The process remains deliberately inert until the signed local-IPC and
/// durable startup composition is installed. Packaging it now proves the
/// final process identity and `SMAppService.agent` bundle topology without
/// opening a listener, creating keys, or claiming readiness prematurely.
@main
enum MacCompanionAgentMain {
    static func main() {
        dispatchMain()
    }
}
