#if os(macOS)
import Foundation

public enum MacAuthenticatedAgentBuildLifetimeErrorV0:
    Error, Equatable, Sendable
{
    case invalidPhase
}

/// One dashboard connection's authenticated running-Agent build. Production
/// consumers may read this evidence but only the package-owned reciprocal
/// local-XPC binding can publish or retire it.
@available(macOS 26.0, *)
public final class MacAuthenticatedAgentBuildLifetimeV0:
    @unchecked Sendable
{
    private enum Phase {
        case awaitingAuthentication
        case authenticated(UInt64)
        case retired
    }

    private let lock = NSLock()
    private var phase = Phase.awaitingAuthentication

    public init() {}

    public func currentBuild() -> UInt64? {
        lock.withLock {
            guard case let .authenticated(build) = phase else {
                return nil
            }
            return build
        }
    }

    package func authenticate(build: UInt64) throws {
        try lock.withLock {
            guard case .awaitingAuthentication = phase else {
                phase = .retired
                throw MacAuthenticatedAgentBuildLifetimeErrorV0.invalidPhase
            }
            phase = .authenticated(build)
        }
    }

    package func retire() {
        lock.withLock { phase = .retired }
    }
}
#endif
