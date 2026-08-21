import CompanionDomain
import CompanionIPC
import Foundation
import Testing

private let localIPCDeviceID = UUID(
    uuidString: "018f9600-0000-7000-8000-000000000001"
)!
private let localIPCReviewID = UUID(
    uuidString: "018f9600-0000-7000-8000-000000000002"
)!
private let localIPCCommandID = UUID(
    uuidString: "018f9600-0000-7000-8000-000000000003"
)!
private let localIPCRequestID = UUID(
    uuidString: "018f9600-0000-7000-8000-000000000004"
)!
private let localIPCApprovalID = UUID(
    uuidString: "018f9600-0000-7000-8000-000000000005"
)!
private let localIPCSessionID = UUID(
    uuidString: "018f9600-0000-7000-8000-000000000006"
)!
private let localIPCDeviceName = try! DeviceDisplayName("Travel iPhone")

private func grantDecisionCommand(
    decision: LocalGrantDecisionV0 = .approve
) throws -> LocalGrantDecisionCommandV0 {
    try LocalGrantDecisionCommandV0(
        commandID: localIPCCommandID,
        reviewID: localIPCReviewID,
        deviceID: localIPCDeviceID,
        deviceDisplayName: localIPCDeviceName,
        decision: decision,
        expectedAuthorizationEpoch: .init(rawValue: 4),
        expectedGrantRevision: .init(rawValue: 7),
        expectedPolicyRevision: .init(rawValue: 3),
        expectedCurrentGrants: CapabilityGrantSet([
            "maccompanion.status.read",
        ]),
        proposedGrants: CapabilityGrantSet([
            "maccompanion.status.read",
            "maccompanion.system.setAudioMuted",
        ]),
        decidedAtUnixMilliseconds: 1_000
    )
}

private func interactiveStopCommand(
    sessionID: UUID? = localIPCSessionID
) throws -> LocalInteractiveStopCommandV0 {
    try LocalInteractiveStopCommandV0(
        commandID: localIPCCommandID,
        deviceID: localIPCDeviceID,
        deviceDisplayName: localIPCDeviceName,
        requestID: localIPCRequestID,
        approvalID: localIPCApprovalID,
        interactiveSessionID: sessionID,
        reason: .userRequested,
        occurredAtUnixMilliseconds: 2_000
    )
}

@Test func approvedGrantDecisionIsExactlyBoundAndAdvancesBothFences() throws {
    let command = try grantDecisionCommand()
    let encoded = try JSONEncoder().encode(command)
    #expect(try JSONDecoder().decode(
        LocalGrantDecisionCommandV0.self,
        from: encoded
    ) == command)

    let receipt = try LocalGrantDecisionReceiptV0(
        correlationID: command.commandID,
        reviewID: command.reviewID,
        deviceID: command.deviceID,
        decision: .approve,
        storedGrants: try command.proposedGrantSet(),
        authorizationEpoch: .init(rawValue: 5),
        grantRevision: .init(rawValue: 8),
        policyRevision: .init(rawValue: 3),
        completedAtUnixMilliseconds: 1_001
    )
    try receipt.validate(against: command)

    let stale = try LocalGrantDecisionReceiptV0(
        correlationID: UUID(),
        reviewID: command.reviewID,
        deviceID: command.deviceID,
        decision: .approve,
        storedGrants: try command.proposedGrantSet(),
        authorizationEpoch: .init(rawValue: 5),
        grantRevision: .init(rawValue: 8),
        policyRevision: .init(rawValue: 3),
        completedAtUnixMilliseconds: 1_001
    )
    #expect(throws: LocalAuthorityMessageErrorV0.bindingMismatch) {
        try stale.validate(against: command)
    }
}

@Test func declinedGrantDecisionPreservesExactCurrentState() throws {
    let command = try grantDecisionCommand(decision: .decline)
    let receipt = try LocalGrantDecisionReceiptV0(
        correlationID: command.commandID,
        reviewID: command.reviewID,
        deviceID: command.deviceID,
        decision: .decline,
        storedGrants: try command.expectedCurrentGrantSet(),
        authorizationEpoch: command.expectedAuthorizationEpoch,
        grantRevision: command.expectedGrantRevision,
        policyRevision: command.expectedPolicyRevision,
        completedAtUnixMilliseconds: 1_001
    )
    try receipt.validate(against: command)

    let mutated = try LocalGrantDecisionReceiptV0(
        correlationID: command.commandID,
        reviewID: command.reviewID,
        deviceID: command.deviceID,
        decision: .decline,
        storedGrants: try command.proposedGrantSet(),
        authorizationEpoch: .init(rawValue: 5),
        grantRevision: .init(rawValue: 8),
        policyRevision: command.expectedPolicyRevision,
        completedAtUnixMilliseconds: 1_001
    )
    #expect(throws: LocalAuthorityMessageErrorV0.revisionMismatch) {
        try mutated.validate(against: command)
    }
}

@Test func grantDecisionDecoderRejectsUnknownAndNoncanonicalGrantFields() throws {
    let command = try grantDecisionCommand()
    let data = try JSONEncoder().encode(command)
    let text = try #require(String(data: data, encoding: .utf8))
    let unknown = text.replacingOccurrences(
        of: "{",
        with: "{\"unknown\":true,",
        options: [],
        range: text.startIndex..<text.index(after: text.startIndex)
    )
    #expect(throws: LocalAuthorityMessageErrorV0.unknownOrMissingField) {
        _ = try JSONDecoder().decode(
            LocalGrantDecisionCommandV0.self,
            from: Data(unknown.utf8)
        )
    }

    let reordered = text.replacingOccurrences(
        of: "[\"maccompanion.status.read\",\"maccompanion.system.setAudioMuted\"]",
        with: "[\"maccompanion.system.setAudioMuted\",\"maccompanion.status.read\"]"
    )
    #expect(reordered != text)
    #expect(throws: LocalAuthorityMessageErrorV0.invalidGrantSet) {
        _ = try JSONDecoder().decode(
            LocalGrantDecisionCommandV0.self,
            from: Data(reordered.utf8)
        )
    }

    let versionOpening = try #require(
        text.range(of: "\"protocolVersion\":{")
    )
    var nestedUnknown = text
    nestedUnknown.insert(
        contentsOf: "\"unknown\":1,",
        at: versionOpening.upperBound
    )
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(
            LocalGrantDecisionCommandV0.self,
            from: Data(nestedUnknown.utf8)
        )
    }
}

@Test func grantDecisionRequiresStrictExpansionAndSafeCurrentRevisions() throws {
    #expect(throws: LocalAuthorityMessageErrorV0.invalidGrantSet) {
        try LocalGrantDecisionCommandV0(
            commandID: UUID(),
            reviewID: UUID(),
            deviceID: localIPCDeviceID,
            deviceDisplayName: localIPCDeviceName,
            decision: .approve,
            expectedAuthorizationEpoch: .init(rawValue: 1),
            expectedGrantRevision: .init(rawValue: 1),
            expectedPolicyRevision: .init(rawValue: 1),
            expectedCurrentGrants: CapabilityGrantSet(["a"]),
            proposedGrants: CapabilityGrantSet(["a"]),
            decidedAtUnixMilliseconds: 1
        )
    }
    #expect(throws: LocalAuthorityMessageErrorV0.revisionMismatch) {
        try LocalGrantDecisionCommandV0(
            commandID: UUID(),
            reviewID: UUID(),
            deviceID: localIPCDeviceID,
            deviceDisplayName: localIPCDeviceName,
            decision: .approve,
            expectedAuthorizationEpoch: .init(rawValue: 0),
            expectedGrantRevision: .init(rawValue: 1),
            expectedPolicyRevision: .init(rawValue: 1),
            expectedCurrentGrants: CapabilityGrantSet([]),
            proposedGrants: CapabilityGrantSet(["a"]),
            decidedAtUnixMilliseconds: 1
        )
    }
}

@Test func interactiveStopRequiresExactCompleteAgentTeardownReceipt() throws {
    for sessionID: UUID? in [localIPCSessionID, nil] {
        let command = try interactiveStopCommand(sessionID: sessionID)
        #expect(try JSONDecoder().decode(
            LocalInteractiveStopCommandV0.self,
            from: JSONEncoder().encode(command)
        ) == command)
        let receipt = try LocalInteractiveStoppedReceiptV0(
            correlationID: command.commandID,
            deviceID: command.deviceID,
            requestID: command.requestID,
            approvalID: command.approvalID,
            interactiveSessionID: command.interactiveSessionID,
            reason: command.reason,
            remoteAuthorityEnded: true,
            runtimeTeardownComplete: true,
            completedAtUnixMilliseconds: 2_001
        )
        try receipt.validate(against: command)
    }

    #expect(throws: LocalAuthorityMessageErrorV0.teardownIncomplete) {
        try LocalInteractiveStoppedReceiptV0(
            correlationID: localIPCCommandID,
            deviceID: localIPCDeviceID,
            requestID: localIPCRequestID,
            approvalID: localIPCApprovalID,
            interactiveSessionID: localIPCSessionID,
            reason: .userRequested,
            remoteAuthorityEnded: true,
            runtimeTeardownComplete: false,
            completedAtUnixMilliseconds: 2_001
        )
    }
}

@Test func interactiveStopRejectsMismatchedSessionReasonAndTime() throws {
    let command = try interactiveStopCommand()
    let mismatched = try LocalInteractiveStoppedReceiptV0(
        correlationID: command.commandID,
        deviceID: command.deviceID,
        requestID: command.requestID,
        approvalID: command.approvalID,
        interactiveSessionID: UUID(),
        reason: .controlDisabled,
        remoteAuthorityEnded: true,
        runtimeTeardownComplete: true,
        completedAtUnixMilliseconds: 2_001
    )
    #expect(throws: LocalAuthorityMessageErrorV0.bindingMismatch) {
        try mismatched.validate(against: command)
    }
    #expect(throws: LocalAuthorityMessageErrorV0.invalidTime) {
        try LocalInteractiveStopCommandV0(
            commandID: UUID(),
            deviceID: localIPCDeviceID,
            deviceDisplayName: localIPCDeviceName,
            requestID: localIPCRequestID,
            approvalID: localIPCApprovalID,
            interactiveSessionID: nil,
            reason: .userRequested,
            occurredAtUnixMilliseconds: -1
        )
    }
}
