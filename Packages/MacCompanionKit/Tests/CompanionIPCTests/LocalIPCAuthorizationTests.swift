import CompanionIPC
import Testing

@Test func localIPCRoleMatrixIsClosed() throws {
    let allowed: Set<String> = [
        "menuApp>agent:negotiateProtocol",
        "menuApp>agent:readAgentStatus",
        "menuApp>agent:createPairingSession",
        "menuApp>agent:dismissPairingSession",
        "menuApp>agent:resolveLocalApproval",
        "menuApp>agent:administerDevices",
        "menuApp>agent:decideGrantExpansion",
        "menuApp>agent:stopInteractiveSession",
        "menuApp>agent:recoverHostIdentity",
        "menuApp>agent:readAuditHistory",
        "menuApp>agent:exportDiagnostics",
        "menuApp>agent:publishInteractiveMedia",
        "menuApp>agent:publishInteractiveState",
        "diagnosticCLI>agent:negotiateProtocol",
        "diagnosticCLI>agent:readAgentStatus",
        "diagnosticCLI>agent:exportDiagnostics",
        "agent>menuApp:negotiateProtocol",
        "agent>menuApp:publishPairingReview",
        "agent>menuApp:installInteractiveLease",
        "agent>menuApp:revokeInteractiveLease",
        "agent>menuApp:applyInteractiveInput",
        "agent>menuApp:applyInteractiveSurface",
        "agent>menuApp:publishHostIdentityRecoveryReview",
        "agent>menuApp:publishHostIdentityRecoveryResume",
    ]

    for caller in LocalProcessRole.allCases {
        for endpoint in LocalProcessRole.allCases {
            for method in LocalIPCMethod.allCases {
                let key = "\(caller.rawValue)>\(endpoint.rawValue):\(method.rawValue)"
                if allowed.contains(key) {
                    try LocalIPCAuthorizationPolicy.authorize(
                        authenticatedCaller: caller,
                        endpoint: endpoint,
                        method: method,
                        version: .init()
                    )
                } else {
                    #expect(throws: LocalIPCAuthorizationError.self) {
                        try LocalIPCAuthorizationPolicy.authorize(
                            authenticatedCaller: caller,
                            endpoint: endpoint,
                            method: method,
                            version: .init()
                        )
                    }
                }
            }
        }
    }
}

@Test func localIPCVersionMismatchFailsBeforeMethodAdmission() {
    #expect(throws: LocalIPCAuthorizationError.unsupportedVersion(
        .init(major: 0, minor: 2)
    )) {
        try LocalIPCAuthorizationPolicy.authorize(
            authenticatedCaller: .menuApp,
            endpoint: .agent,
            method: .readAgentStatus,
            version: .init(major: 0, minor: 2)
        )
    }
}
