import CompanionTransport
import CompanionWire
import Foundation
import Testing

private func wireUUID(_ value: Int) -> WireUUID {
    WireUUID(UUID(uuidString: String(format: "018f7000-0000-7000-8000-%012x", value))!)
}

@Test func replayWindowRejectsDuplicatesAndEvictsOnlyTheOldest() throws {
    var window = ConnectionReplayWindow(capacity: 3)
    try window.admit(wireUUID(1))
    try window.admit(wireUUID(2))
    try window.admit(wireUUID(3))

    #expect(throws: TransportGuardError.duplicateMessage(wireUUID(2))) {
        try window.admit(wireUUID(2))
    }
    try window.admit(wireUUID(4))
    #expect(window.count == 3)
    try window.admit(wireUUID(1))
    #expect(window.count == 3)
}

@Test func v0ReplayWindowRemainsBoundedAcrossCompaction() throws {
    var window = ConnectionReplayWindow()
    for value in 0..<(ConnectionReplayWindow.v0Capacity * 3) {
        try window.admit(wireUUID(value))
    }
    #expect(window.count == ConnectionReplayWindow.v0Capacity)
    #expect(throws: TransportGuardError.duplicateMessage(
        wireUUID(ConnectionReplayWindow.v0Capacity * 3 - 1)
    )) {
        try window.admit(wireUUID(ConnectionReplayWindow.v0Capacity * 3 - 1))
    }
}

@Test func inFlightLimitAndDuplicateRequestFailClosed() throws {
    var tracker = InFlightCommandTracker(limit: 2)
    try tracker.register(
        messageID: wireUUID(1),
        requestKind: .statusSnapshotRequest,
        registeredAtMonotonicNanoseconds: 100,
        deadlineMonotonicNanoseconds: 200
    )
    try tracker.register(
        messageID: wireUUID(2),
        requestKind: .keepalivePing,
        registeredAtMonotonicNanoseconds: 100,
        deadlineMonotonicNanoseconds: 200
    )

    #expect(throws: TransportGuardError.duplicatePendingRequest(wireUUID(1))) {
        try tracker.register(
            messageID: wireUUID(1),
            requestKind: .statusSnapshotRequest,
            registeredAtMonotonicNanoseconds: 100,
            deadlineMonotonicNanoseconds: 200
        )
    }
    #expect(throws: TransportGuardError.inFlightLimitReached(2)) {
        try tracker.register(
            messageID: wireUUID(3),
            requestKind: .statusSnapshotRequest,
            registeredAtMonotonicNanoseconds: 100,
            deadlineMonotonicNanoseconds: 200
        )
    }
}

@Test func auditRepliesAreRegisteredAndFailedSendsCanBeCancelled() throws {
    var tracker = InFlightCommandTracker()
    try tracker.register(
        messageID: wireUUID(30),
        requestKind: .auditListRequest,
        registeredAtMonotonicNanoseconds: 100,
        deadlineMonotonicNanoseconds: 200
    )
    #expect(tracker.cancel(messageID: wireUUID(30))?.requestKind == .auditListRequest)
    #expect(tracker.count == 0)

    try tracker.register(
        messageID: wireUUID(31),
        requestKind: .auditListRequest,
        registeredAtMonotonicNanoseconds: 100,
        deadlineMonotonicNanoseconds: 200
    )
    #expect(try tracker.resolve(
        correlationID: wireUUID(31),
        responseKind: .auditListResponse,
        nowMonotonicNanoseconds: 199
    ).requestKind == .auditListRequest)
}

@Test func correlationKindAndDeadlineMustAllMatch() throws {
    var tracker = InFlightCommandTracker()
    try tracker.register(
        messageID: wireUUID(1),
        requestKind: .statusSnapshotRequest,
        registeredAtMonotonicNanoseconds: 100,
        deadlineMonotonicNanoseconds: 200
    )

    #expect(throws: TransportGuardError.unknownCorrelation(wireUUID(2))) {
        try tracker.resolve(
            correlationID: wireUUID(2),
            responseKind: .statusSnapshotResponse,
            nowMonotonicNanoseconds: 150
        )
    }
    #expect(throws: TransportGuardError.unexpectedResponse(
        request: .statusSnapshotRequest,
        response: .keepalivePong
    )) {
        try tracker.resolve(
            correlationID: wireUUID(1),
            responseKind: .keepalivePong,
            nowMonotonicNanoseconds: 150
        )
    }
    #expect(tracker.count == 1)
    #expect(try tracker.resolve(
        correlationID: wireUUID(1),
        responseKind: .statusSnapshotResponse,
        nowMonotonicNanoseconds: 199
    ).requestKind == .statusSnapshotRequest)
    #expect(tracker.count == 0)
}

@Test func expiryRemovesPendingCommandAtExactDeadline() throws {
    var tracker = InFlightCommandTracker()
    try tracker.register(
        messageID: wireUUID(1),
        requestKind: .statusSnapshotRequest,
        registeredAtMonotonicNanoseconds: 100,
        deadlineMonotonicNanoseconds: 200
    )

    #expect(tracker.expire(at: 199).isEmpty)
    #expect(tracker.expire(at: 200).map(\.messageID) == [wireUUID(1)])
    #expect(tracker.count == 0)
}

@Test func onlyRegisteredRequestKindsAndForwardDeadlinesAreAccepted() {
    var tracker = InFlightCommandTracker()
    #expect(throws: TransportGuardError.unsupportedRequestKind(.statusSnapshotResponse)) {
        try tracker.register(
            messageID: wireUUID(1),
            requestKind: .statusSnapshotResponse,
            registeredAtMonotonicNanoseconds: 100,
            deadlineMonotonicNanoseconds: 200
        )
    }
    #expect(throws: TransportGuardError.invalidDeadline) {
        try tracker.register(
            messageID: wireUUID(1),
            requestKind: .statusSnapshotRequest,
            registeredAtMonotonicNanoseconds: 200,
            deadlineMonotonicNanoseconds: 200
        )
    }
}

@Test func everyOperationRequestAcceptsOnlyItsClosedReplySet() throws {
    let pairs: [(WireMessageKind, WireMessageKind)] = [
        (.operationInvoke, .operationApprovalRequired),
        (.operationInvoke, .operationStatusResponse),
        (.operationApprove, .operationStatusResponse),
        (.operationStatusRequest, .operationStatusResponse),
        (.operationCancel, .operationStatusResponse),
        (.operationCancel, .error),
    ]
    var tracker = InFlightCommandTracker()
    for (offset, pair) in pairs.enumerated() {
        let messageID = wireUUID(100 + offset)
        try tracker.register(
            messageID: messageID,
            requestKind: pair.0,
            registeredAtMonotonicNanoseconds: 100,
            deadlineMonotonicNanoseconds: 200
        )
        #expect(try tracker.resolve(
            correlationID: messageID,
            responseKind: pair.1,
            nowMonotonicNanoseconds: 150
        ).requestKind == pair.0)
    }

    try tracker.register(
        messageID: wireUUID(200),
        requestKind: .operationApprove,
        registeredAtMonotonicNanoseconds: 100,
        deadlineMonotonicNanoseconds: 200
    )
    #expect(throws: TransportGuardError.unexpectedResponse(
        request: .operationApprove,
        response: .operationApprovalRequired
    )) {
        try tracker.resolve(
            correlationID: wireUUID(200),
            responseKind: .operationApprovalRequired,
            nowMonotonicNanoseconds: 150
        )
    }
}

@Test func capabilityDiscoveryAcceptsOnlyPageOrClosedError() throws {
    for response in [
        WireMessageKind.capabilityRegistryResponse,
        WireMessageKind.error,
    ] {
        var tracker = InFlightCommandTracker()
        try tracker.register(
            messageID: wireUUID(20),
            requestKind: .capabilityRegistryRequest,
            registeredAtMonotonicNanoseconds: 100,
            deadlineMonotonicNanoseconds: 200
        )
        _ = try tracker.resolve(
            correlationID: wireUUID(20),
            responseKind: response,
            nowMonotonicNanoseconds: 150
        )
    }

    var tracker = InFlightCommandTracker()
    try tracker.register(
        messageID: wireUUID(21),
        requestKind: .capabilityRegistryRequest,
        registeredAtMonotonicNanoseconds: 100,
        deadlineMonotonicNanoseconds: 200
    )
    #expect(throws: TransportGuardError.unexpectedResponse(
        request: .capabilityRegistryRequest,
        response: .statusSnapshotResponse
    )) {
        _ = try tracker.resolve(
            correlationID: wireUUID(21),
            responseKind: .statusSnapshotResponse,
            nowMonotonicNanoseconds: 150
        )
    }
}

@Test func interactiveSessionRequestsAcceptOnlyTheirClosedReplySets() throws {
    let pairs: [(WireMessageKind, WireMessageKind)] = [
        (.interactiveSessionRequest, .interactiveSessionApprovalRequired),
        (.interactiveSessionRequest, .error),
        (.interactiveSessionApprove, .interactiveSessionAccepted),
        (.interactiveSessionApprove, .error),
        (.interactiveInitialSurfaceRequest, .interactiveInitialSurfaceDescriptor),
        (.interactiveInitialSurfaceRequest, .error),
        (
            .interactiveInitialSurfaceAcknowledgement,
            .interactiveInitialSurfaceAcknowledged
        ),
        (.interactiveInitialSurfaceAcknowledgement, .error),
        (.interactiveSurfaceSelect, .interactiveSurfaceSelected),
        (.interactiveSurfaceSelect, .error),
        (.interactiveSurfaceTargetsRequest, .interactiveSurfaceTargetsResponse),
        (.interactiveSurfaceTargetsRequest, .error),
        (.interactiveSurfaceAcknowledgement, .interactiveSurfaceAcknowledged),
        (.interactiveSurfaceAcknowledgement, .error),
    ]
    for (offset, pair) in pairs.enumerated() {
        var tracker = InFlightCommandTracker()
        let messageID = wireUUID(300 + offset)
        try tracker.register(
            messageID: messageID,
            requestKind: pair.0,
            registeredAtMonotonicNanoseconds: 100,
            deadlineMonotonicNanoseconds: 200
        )
        #expect(try tracker.resolve(
            correlationID: messageID,
            responseKind: pair.1,
            nowMonotonicNanoseconds: 150
        ).requestKind == pair.0)
    }

    var tracker = InFlightCommandTracker()
    try tracker.register(
        messageID: wireUUID(310),
        requestKind: .interactiveSessionApprove,
        registeredAtMonotonicNanoseconds: 100,
        deadlineMonotonicNanoseconds: 200
    )
    #expect(throws: TransportGuardError.unexpectedResponse(
        request: .interactiveSessionApprove,
        response: .interactiveSessionApprovalRequired
    )) {
        try tracker.resolve(
            correlationID: wireUUID(310),
            responseKind: .interactiveSessionApprovalRequired,
            nowMonotonicNanoseconds: 150
        )
    }
}
