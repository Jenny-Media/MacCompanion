#if os(macOS)
import CompanionAgent
import ServiceManagement

/// A label-free platform adapter. The permanent containing app constructs the
/// exact `SMAppService.mainApp` or `SMAppService.agent(plistName:)` instance and
/// passes it here; this module never chooses an identifier or role topology.
@MainActor
public final class SMAppServiceRawLoginRoleV1:
    @unchecked Sendable,
    AgentLoginRoleRawServiceV1
{
    private let service: SMAppService

    public init(service: SMAppService) {
        self.service = service
    }

    public func status() async -> AgentLoginRoleRegistrationStateV1 {
        Self.project(service.status)
    }

    public func register() async throws {
        try service.register()
    }

    public func unregisterAndWait() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            service.unregister { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    nonisolated public static func project(
        _ status: SMAppService.Status
    ) -> AgentLoginRoleRegistrationStateV1 {
        switch status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .unknown
        }
    }
}
#endif
