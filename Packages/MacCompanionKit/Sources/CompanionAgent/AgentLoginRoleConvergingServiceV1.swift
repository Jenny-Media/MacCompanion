public enum AgentLoginRoleRegistrationStateV1:
    String, CaseIterable, Sendable
{
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
}

/// The minimal surface a permanent `SMAppService` adapter must provide. Its
/// unregister operation must not return until the framework's asynchronous
/// completion fires, so a successful postcondition means the job is no longer
/// eligible to launch and any running helper has completed framework teardown.
public protocol AgentLoginRoleRawServiceV1: Sendable {
    func status() async -> AgentLoginRoleRegistrationStateV1
    func register() async throws
    func unregisterAndWait() async throws
}

public enum AgentLoginRoleConvergenceErrorV1:
    Error, Equatable, Sendable
{
    case requiresApproval
    case serviceNotFound
    case platformFailure
    case postconditionFailed(
        expected: AgentLoginRoleRegistrationStateV1,
        actual: AgentLoginRoleRegistrationStateV1
    )
}

public enum AgentLoginRoleRegistrationAcquisitionV1:
    Equatable,
    Sendable
{
    case newlyRegistered
    case alreadyRegistered
}

/// Narrow registration seam for the foreground disabled-Agent bootstrap.
/// Ownership is derived from the exact pre-mutation status inside the same
/// actor that performs and verifies registration, so rollback never guesses
/// whether this setup attempt introduced the login role.
public protocol AgentBootstrapLoginRoleServiceV1:
    AgentLoginRoleServiceV1
{
    func acquireForBootstrap() async throws
        -> AgentLoginRoleRegistrationAcquisitionV1
}

/// Makes the raw registration API idempotent and verifies every postcondition.
/// A framework call that reports an error after reaching the requested state is
/// accepted as converged; all other errors are reduced to a closed reason.
public actor AgentLoginRoleConvergingServiceV1:
    AgentBootstrapLoginRoleServiceV1
{
    private let raw: any AgentLoginRoleRawServiceV1

    public init(raw: any AgentLoginRoleRawServiceV1) {
        self.raw = raw
    }

    public func register() async throws {
        _ = try await acquireForBootstrap()
    }

    public func acquireForBootstrap() async throws
        -> AgentLoginRoleRegistrationAcquisitionV1
    {
        switch await raw.status() {
        case .enabled:
            return .alreadyRegistered
        case .requiresApproval:
            throw AgentLoginRoleConvergenceErrorV1.requiresApproval
        case .notFound:
            throw AgentLoginRoleConvergenceErrorV1.serviceNotFound
        case .unknown:
            throw AgentLoginRoleConvergenceErrorV1.platformFailure
        case .notRegistered:
            break
        }

        do {
            try await raw.register()
        } catch {
            guard await raw.status() == .enabled else {
                throw AgentLoginRoleConvergenceErrorV1.platformFailure
            }
            return .newlyRegistered
        }
        let actual = await raw.status()
        guard actual == .enabled else {
            throw AgentLoginRoleConvergenceErrorV1.postconditionFailed(
                expected: .enabled,
                actual: actual
            )
        }
        return .newlyRegistered
    }

    public func unregister() async throws {
        switch await raw.status() {
        case .notRegistered:
            return
        case .notFound:
            throw AgentLoginRoleConvergenceErrorV1.serviceNotFound
        case .unknown:
            throw AgentLoginRoleConvergenceErrorV1.platformFailure
        case .enabled, .requiresApproval:
            break
        }

        do {
            try await raw.unregisterAndWait()
        } catch {
            guard await raw.status() == .notRegistered else {
                throw AgentLoginRoleConvergenceErrorV1.platformFailure
            }
            return
        }
        let actual = await raw.status()
        guard actual == .notRegistered else {
            throw AgentLoginRoleConvergenceErrorV1.postconditionFailed(
                expected: .notRegistered,
                actual: actual
            )
        }
    }
}
