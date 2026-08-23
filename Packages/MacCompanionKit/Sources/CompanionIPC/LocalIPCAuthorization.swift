public enum LocalProcessRole: String, Codable, CaseIterable, Sendable {
    case agent
    case menuApp
    case diagnosticCLI
}

public enum LocalIPCMethod: String, Codable, CaseIterable, Sendable {
    case negotiateProtocol
    case readRemoteAccessBootstrap
    case enableRemoteAccess
    case publishMenuReady
    case readAgentStatus
    case createPairingSession
    case dismissPairingSession
    case publishPairingReview
    case withdrawPairingReview
    case resolveLocalApproval
    case administerDevices
    case decideGrantExpansion
    case stopInteractiveSession
    case recoverHostIdentity
    case acknowledgeHostIdentityRecoveryCompletion
    case readAuditHistory
    case exportDiagnostics
    case installInteractiveLease
    case revokeInteractiveLease
    case applyInteractiveInput
    case applyInteractiveSurface
    case publishInteractiveMedia
    case publishInteractiveState
    case closeNetworkAdmissionForUpdate
    case drainNetworkConnectionsForUpdate
    case reopenNetworkAdmissionAfterUpdateFailure
    case publishHostIdentityRecoveryReview
    case publishHostIdentityRecoveryResume
    case withdrawHostIdentityRecovery
}

private struct LocalIPCVersionAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

public struct LocalIPCProtocolVersion: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case major, minor
    }

    public let major: UInt16
    public let minor: UInt16

    public init(major: UInt16 = 0, minor: UInt16 = 1) {
        self.major = major
        self.minor = minor
    }

    public init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: LocalIPCVersionAnyCodingKey.self)
        guard Set(all.allKeys.map(\.stringValue))
                == Set(CodingKeys.allCases.map(\.stringValue)) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "local IPC version requires exact keys"
                )
            )
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        major = try c.decode(UInt16.self, forKey: .major)
        minor = try c.decode(UInt16.self, forKey: .minor)
    }
}

public enum LocalIPCAuthorizationError: Error, Equatable, Sendable {
    case unsupportedVersion(LocalIPCProtocolVersion)
    case sameRoleConnection
    case methodDenied(
        caller: LocalProcessRole,
        endpoint: LocalProcessRole,
        method: LocalIPCMethod
    )
}

/// Role authorization applied only after a platform adapter has authenticated
/// the peer's audit token and code identity. A caller-supplied role is never
/// sufficient evidence for invoking this policy.
public enum LocalIPCAuthorizationPolicy {
    public static func authorize(
        authenticatedCaller: LocalProcessRole,
        endpoint: LocalProcessRole,
        method: LocalIPCMethod,
        version: LocalIPCProtocolVersion
    ) throws {
        guard version == LocalIPCProtocolVersion() else {
            throw LocalIPCAuthorizationError.unsupportedVersion(version)
        }
        guard authenticatedCaller != endpoint else {
            throw LocalIPCAuthorizationError.sameRoleConnection
        }
        guard permittedMethods(
            authenticatedCaller: authenticatedCaller,
            endpoint: endpoint
        ).contains(method) else {
            throw LocalIPCAuthorizationError.methodDenied(
                caller: authenticatedCaller,
                endpoint: endpoint,
                method: method
            )
        }
    }

    public static func permittedMethods(
        authenticatedCaller: LocalProcessRole,
        endpoint: LocalProcessRole
    ) -> Set<LocalIPCMethod> {
        switch (authenticatedCaller, endpoint) {
        case (.menuApp, .agent):
            [
                .negotiateProtocol,
                .readRemoteAccessBootstrap,
                .enableRemoteAccess,
                .publishMenuReady,
                .readAgentStatus,
                .createPairingSession,
                .dismissPairingSession,
                .resolveLocalApproval,
                .administerDevices,
                .decideGrantExpansion,
                .stopInteractiveSession,
                .recoverHostIdentity,
                .acknowledgeHostIdentityRecoveryCompletion,
                .readAuditHistory,
                .exportDiagnostics,
                .publishInteractiveMedia,
                .publishInteractiveState,
                .closeNetworkAdmissionForUpdate,
                .drainNetworkConnectionsForUpdate,
                .reopenNetworkAdmissionAfterUpdateFailure,
            ]
        case (.diagnosticCLI, .agent):
            [
                .negotiateProtocol,
                .readAgentStatus,
                .exportDiagnostics,
            ]
        case (.agent, .menuApp):
            [
                .negotiateProtocol,
                .publishPairingReview,
                .withdrawPairingReview,
                .installInteractiveLease,
                .revokeInteractiveLease,
                .applyInteractiveInput,
                .applyInteractiveSurface,
                .publishHostIdentityRecoveryReview,
                .publishHostIdentityRecoveryResume,
                .withdrawHostIdentityRecovery,
            ]
        default:
            []
        }
    }
}
