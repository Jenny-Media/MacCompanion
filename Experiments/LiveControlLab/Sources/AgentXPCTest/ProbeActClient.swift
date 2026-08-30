#if !DEBUG || !os(macOS)
#error("Disposable Act client is macOS Debug only")
#endif
import CompanionClient
import CompanionClientNetworkPlatform
import CompanionIPC
import CompanionLocalXPCPlatform
import CompanionNativeProviders
import CompanionWire
import Foundation

enum ProbeActClient {
    enum Failure: Error { case catalog, grant, outcome, replay, unsafeStorage }
    private static let capability = NativeAudioMuteCapabilityV1.capabilityID
    private static func parameters(_ muted: Bool) -> CanonicalJSONValue {
        .object([.init(key: "muted", value: .boolean(muted))])
    }

    @available(macOS 26.0, *)
    static func run(network: NetworkClientConfiguredRouteApplicationProductV1, menu: MacLocalXPCClientV1,
                    deviceID: UUID, directory: URL, replay: Bool,
                    emit: @escaping @Sendable (String) -> Void) async throws {
        let state = network.primaryState
        let checkpoint = directory.appendingPathComponent("act-operation.json")
        if replay {
            let attributes = try FileManager.default.attributesOfItem(atPath: checkpoint.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw Failure.unsafeStorage }
            let operation = try JSONDecoder().decode(UUID.self, from: Data(contentsOf: checkpoint))
            try await catalog(state, granted: true)
            _ = try await state.resumeOperationStatus(capabilityID: capability, operationID: WireUUID(operation))
            guard case .succeeded = try await terminal(state) else { throw Failure.replay }
            try await state.finishOperation()
            // Same durable request tuple replays without a new side effect.
            _ = try await state.beginOperation(capabilityID: capability, parameters: parameters(true), operationID: WireUUID(operation))
            guard case .succeeded = try await terminal(state) else { throw Failure.replay }
            try await state.finishOperation()
            emit("act-durable-status-and-invoke-replay-verified")
            return
        }
        try await catalog(state, granted: false)
        do {
            _ = try await state.beginOperation(capabilityID: capability, parameters: parameters(true), operationID: WireUUID(UUID()))
            throw Failure.grant
        } catch ClientActChannelErrorV1.operationRejected { emit("act-client-ungranted-operation-rejected") }
        let request = try LocalCapabilityGrantReviewRequestV1(commandID: UUID(), deviceID: deviceID,
            capabilityID: capability, requestedAtUnixMilliseconds: ProbePairingClient.wall())
        let review = try await menu.makeCapabilityGrantReview(request)
        guard try await menu.makeCapabilityGrantReview(request) == review, review.currentGrantIDs.isEmpty,
              try review.descriptor.domainValue() == NativeAudioMuteCapabilityV1.descriptor() else { throw Failure.grant }
        let decline = try review.command(commandID: UUID(), decision: .decline, decidedAtUnixMilliseconds: ProbePairingClient.wall())
        let declined = try await menu.decideCapabilityGrant(decline)
        guard try await menu.decideCapabilityGrant(decline) == declined,
              declined.grantRevision == review.grantRevision else { throw Failure.grant }
        try await state.reloadApprovedActions()
        try await catalog(state, granted: false)
        let changed = try review.command(commandID: decline.commandID, decision: .approve, decidedAtUnixMilliseconds: decline.decidedAtUnixMilliseconds)
        do {
            _ = try await menu.decideCapabilityGrant(changed)
            throw Failure.grant
        } catch MacLocalXPCMenuPairingCommandErrorV1.commandFailed {}
        emit("signed-act-decline-and-changed-replay-rejected")

        let fresh = try await menu.makeCapabilityGrantReview(.init(commandID: UUID(), deviceID: deviceID,
            capabilityID: capability, requestedAtUnixMilliseconds: ProbePairingClient.wall()))
        let approval = try fresh.command(commandID: UUID(), decision: .approve, decidedAtUnixMilliseconds: ProbePairingClient.wall())
        let oldConnection = state.snapshot().connectionID
        let approved = try await menu.decideCapabilityGrant(approval)
        guard try await menu.decideCapabilityGrant(approval) == approved,
              approved.storedGrantIDs == [capability] else { throw Failure.grant }
        // Explicit lifecycle reconnect, never reusing the pre-grant session.
        try await network.binding.setForeground(false)
        try await network.binding.setForeground(true)
        try await catalog(state, granted: true)
        guard state.snapshot().connectionID != oldConnection else { throw Failure.grant }
        emit("signed-act-approval-fences-primary-and-reconnects")

        let operation = UUID()
        _ = try await state.beginOperation(capabilityID: capability, parameters: parameters(true), operationID: WireUUID(operation))
        guard try await terminal(state) == .succeeded(verifiedResult: parameters(true)) else { throw Failure.outcome }
        try await state.finishOperation()
        _ = try await state.beginOperation(capabilityID: capability, parameters: parameters(true), operationID: WireUUID(operation))
        guard case .succeeded = try await terminal(state) else { throw Failure.replay }
        try await state.finishOperation()
        emit("act-execute-readback-and-exact-replay-verified")

        _ = try await state.beginOperation(capabilityID: capability, parameters: parameters(false), operationID: WireUUID(UUID()))
        guard try await terminal(state) == .failed(.providerRejected) else { throw Failure.outcome }
        try await state.finishOperation()
        emit("act-mismatched-readback-fails-closed")
        _ = try await state.beginOperation(capabilityID: capability, parameters: parameters(false), operationID: WireUUID(UUID()))
        guard try await terminal(state) == .succeeded(verifiedResult: parameters(false)) else { throw Failure.outcome }
        try await state.finishOperation()
        try JSONEncoder().encode(operation).write(to: checkpoint, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: checkpoint.path)
        let previous = state.snapshot().observedStatus
        try await state.refreshStatus()
        let deadline = ContinuousClock.now + .seconds(5)
        while state.snapshot().observedStatus == previous, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard state.snapshot().connectionID != nil, state.snapshot().observedStatus != previous,
              state.snapshot().controlState == .inactive else { throw Failure.outcome }
        emit("act-completes-without-control-preserves-observe")
    }

    private static func catalog(_ state: NetworkClientPrimaryApplicationStateV0, granted: Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            let snapshot = state.snapshot()
            if let channel = snapshot.actChannel, await channel.state == .idle {
                try await state.reloadApprovedActions()
            }
            if let error = snapshot.catalogRemoteError {
                FileHandle.standardOutput.write(Data("act-catalog-error:\(error.code)\n".utf8))
                throw Failure.catalog
            }
            if snapshot.connectionID != nil, let catalog = snapshot.catalog,
               catalog.capabilities.map(\.capabilityID) == (granted ? [capability] : []) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.catalog
    }

    private static func terminal(_ state: NetworkClientPrimaryApplicationStateV0) async throws -> OperationResultPresentationV1 {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if case let .terminal(result) = state.snapshot().operationState { return result }
            if let error = state.snapshot().operationRemoteError {
                // Closed remote code only; no operation payload or result content.
                FileHandle.standardOutput.write(Data("act-remote-error:\(error.code)\n".utf8))
                throw Failure.outcome
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.outcome
    }
}
