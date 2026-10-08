#if !DEBUG || !os(macOS)
#error("Disposable real pairing client is macOS Debug only")
#endif
import CompanionClient
import CompanionInteractiveShared
import CompanionClientApp
import CompanionClientNetworkPlatform
import CompanionIPC
import CompanionLocalXPCPlatform
import CompanionNativeProviders
import CompanionPresentation
import CompanionWire
import CryptoKit
import Foundation

/// Software custody substitutes hardware protection only within the runner's
/// private directory. Pairing/authentication use the production client owners.
private actor ProbeClientCustody: ClientIdentityKeyCustodyV0 {
    private struct Keys: Codable {
        let session: Data
        let approval: Data
        let sessionReference: UUID
        let approvalReference: UUID
    }
    private let location: URL
    private var keys: Keys?
    init(directory: URL) throws {
        location = directory.appendingPathComponent("software-client-keys.json")
        if FileManager.default.fileExists(atPath: location.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
                throw ProbePairingClient.Failure.unsafeStorage
            }
            keys = try JSONDecoder().decode(Keys.self, from: Data(contentsOf: location))
        }
    }
    func prepareIdentity(pairingID: UUID, clientID: UUID) throws -> ClientPreparedIdentityV0 {
        if keys == nil {
            let value = Keys(session: P256.Signing.PrivateKey().rawRepresentation,
                approval: P256.Signing.PrivateKey().rawRepresentation,
                sessionReference: UUID(), approvalReference: UUID())
            try JSONEncoder().encode(value).write(to: location, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
            keys = value
        }
        guard let keys else { throw ProbePairingClient.Failure.unsafeStorage }
        return try .init(pairingID: pairingID, clientID: clientID,
            sessionKey: .init(role: .session, reference: .init(keys.sessionReference),
                publicKeyX963: P256.Signing.PrivateKey(rawRepresentation: keys.session).publicKey.x963Representation,
                protection: .afterFirstUnlockThisDeviceOnly),
            approvalKey: .init(role: .approval, reference: .init(keys.approvalReference),
                publicKeyX963: P256.Signing.PrivateKey(rawRepresentation: keys.approval).publicKey.x963Representation,
                protection: .whenUnlockedThisDeviceOnlyUserPresence))
    }
    func validatePreparedIdentity(_ identity: ClientPreparedIdentityV0) throws -> Bool {
        guard keys != nil else { return false }
        return try prepareIdentity(pairingID: identity.pairingID, clientID: identity.clientID) == identity
    }
    func signSessionInput(_ input: Data, using reference: ClientSigningKeyReferenceV0) throws -> Data {
        guard let keys, reference.rawValue == keys.sessionReference else { throw ProbePairingClient.Failure.unsafeStorage }
        return try P256.Signing.PrivateKey(rawRepresentation: keys.session).signature(for: input).rawRepresentation
    }
    func signApprovalInput(_ input: Data, using reference: ClientSigningKeyReferenceV0,
                           reason: ClientApprovalPresenceReasonV0) throws -> Data {
        guard let keys, reference.rawValue == keys.approvalReference else { throw ProbePairingClient.Failure.unsafeStorage }
        return try P256.Signing.PrivateKey(rawRepresentation: keys.approval).signature(for: input).rawRepresentation
    }
    func discardPreparedIdentity(_ identity: ClientPreparedIdentityV0) throws {
        guard try validatePreparedIdentity(identity) else { return }
        try FileManager.default.removeItem(at: location)
        keys = nil
    }
}

enum ProbePairingClient {
    private struct RevocationCheckpoint: Codable {
        let command: LocalDeviceRevocationCommandV0
        let receipt: LocalDeviceRevokedReceiptV0
    }
    enum Failure: Error { case unsafeStorage, unexpectedReview, pairingFailed, notConnected, noObservation }
    static func wall() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
    static func mono() -> UInt64 { DispatchTime.now().uptimeNanoseconds / 1_000_000 }

    @available(macOS 26.0, *)
    static func run(testID: UUID, menu: MacLocalXPCClientV1, surfaces: ProbePresentationSurface,
                    create: Bool, interactive: ProbeInteractiveMenu? = nil,
                    revocationReviewOnly: Bool = false, revocationReplay: Bool = false,
                    act: Bool = false, actReplay: Bool = false, actDenial: Bool = false, actFault: String? = nil,
                    emit: @escaping @Sendable (String) -> Void) async throws {
        var directory = URL(fileURLWithPath: "/private/tmp/maccompanion-agent-xpc-\(testID.uuidString.lowercased())")
        let canonical = realpath(directory.path, nil)
        defer { free(canonical) }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard canonical.map({ String(cString: $0) }) == directory.path,
              attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else { throw Failure.unsafeStorage }
        let clientID: UUID
        if interactive?.scenario == .revocationRace {
            // A second genuinely paired client, never a rewrite or revival of
            // the already revoked client's stored identity or device record.
            guard create else { throw Failure.unsafeStorage }
            directory.appendPathComponent("revocation-race-client", isDirectory: true)
            guard !FileManager.default.fileExists(atPath: directory.path) else { throw Failure.unsafeStorage }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            clientID = UUID()
        } else { clientID = testID }
        let custody = try ProbeClientCustody(directory: directory)
        let store = try AtomicFileClientPairedHostStoreV0(directory: directory.appendingPathComponent("client-paired"))
        if create {
            guard try await store.allRecords().isEmpty else { throw Failure.unsafeStorage }
            let receipt = try await menu.createPairingSession(.init(commandID: UUID()))
            let pairing = try NetworkClientPairingApplicationCompositionV0.makeOwner(clientID: clientID,
                custody: custody, persistence: store,
                verificationQueue: DispatchQueue(label: "Probe.pair.verify"),
                connectionQueue: DispatchQueue(label: "Probe.pair.connection"))
            try await pairing.receiveScan(receipt.encodedQRCode)
            let attempt = Task { try await pairing.acceptPreview() }
            do {
                guard case let .presented(review) = try await surfaces.next(),
                      review.pairingID == receipt.pairingID, review.clientID == clientID else {
                    throw Failure.unexpectedReview
                }
                let deadline = ContinuousClock.now + .seconds(5)
                var snapshot = await pairing.snapshot()
                while snapshot.phase != .compareOnMac, snapshot.phase != .failed, ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(10))
                    snapshot = await pairing.snapshot()
                }
                let identity = try await custody.prepareIdentity(pairingID: receipt.pairingID, clientID: clientID)
                guard snapshot.phase == .compareOnMac,
                      snapshot.preview?.fingerprintTrust == .pinnedTLSVerified,
                      snapshot.authentication?.authenticationString == review.authenticationString.rawValue,
                      snapshot.authentication?.pairingID == review.pairingID,
                      Data(SHA256.hash(data: identity.sessionKey.publicKeyX963)) == review.sessionPublicKeyFingerprint.rawValue,
                      Data(SHA256.hash(data: identity.approvalKey.publicKeyX963)) == review.approvalPublicKeyFingerprint.rawValue else {
                    throw Failure.unexpectedReview
                }
                emit("real-pairing-pin-and-sas-verified")
                let command = try LocalPairingDecisionCommandV0(commandID: UUID(), review: review,
                    deviceDisplayName: .init("Disposable XPC client"), decision: .approve,
                    decidedAtUnixMilliseconds: wall())
                let decision = try await menu.resolveLocalApproval(command)
                try decision.validate(against: command)
                guard try await menu.resolveLocalApproval(command) == decision else { throw Failure.unexpectedReview }
                let changed = try LocalPairingDecisionCommandV0(commandID: command.commandID, review: review,
                    deviceDisplayName: nil, decision: .decline, decidedAtUnixMilliseconds: command.decidedAtUnixMilliseconds)
                do {
                    _ = try await menu.resolveLocalApproval(changed)
                    throw Failure.unexpectedReview
                } catch MacLocalXPCMenuPairingCommandErrorV1.commandFailed {
                    emit("real-pairing-exact-replay-and-mutation-rejection-verified")
                }
                try await attempt.value
                guard await pairing.snapshot().phase == .paired else { throw Failure.pairingFailed }
                emit("real-pairing-approved-and-persisted")
            } catch {
                await pairing.cancel()
                attempt.cancel()
                _ = try? await attempt.value
                throw error
            }
        }
        let reopened = try AtomicFileClientPairedHostStoreV0(directory: directory.appendingPathComponent("client-paired"))
        let records = try await reopened.allRecords()
        guard records.count == 1, let record = records.first, record.clientID == clientID,
              record.deviceState == .activeMonitorOnly,
              record.endpoints.count == 1,
              record.endpoints[0].value == "127.0.0.1", record.endpoints[0].port == 59_654 else {
            throw Failure.pairingFailed
        }
        if revocationReplay {
            let checkpoint: RevocationCheckpoint = try readPrivate(directory.appendingPathComponent("revocation-receipt.json"))
            guard checkpoint.command.review.deviceID == record.deviceID,
                  try await menu.revokeDevice(checkpoint.command) == checkpoint.receipt else { throw Failure.unexpectedReview }
            emit("durable-revocation-replay-verified")
        }
        if let interactive {
            if interactive.scenario == .lifecycle || interactive.scenario == .revocationRace || interactive.scenario == .native {
                let priorGrants = interactive.scenario == .lifecycle ? [NativeAudioMuteCapabilityV1.capabilityID] : []
                let declined = try await menu.makeInteractiveControlGrantReview(.init(commandID: UUID(), requestedAtUnixMilliseconds: wall()))
                guard declined.deviceID == record.deviceID, declined.currentGrantIDs == priorGrants else { throw Failure.unexpectedReview }
                _ = try await menu.decideInteractiveControlGrant(declined.makeDecisionCommand(commandID: UUID(),
                    decision: .decline, decidedAtUnixMilliseconds: wall()))
                let approved = try await menu.makeInteractiveControlGrantReview(.init(commandID: UUID(), requestedAtUnixMilliseconds: wall()))
                guard approved.deviceID == record.deviceID, approved.currentGrantIDs == priorGrants,
                      approved.reviewID != declined.reviewID else { throw Failure.unexpectedReview }
                _ = try await menu.decideInteractiveControlGrant(approved.makeDecisionCommand(commandID: UUID(),
                    decision: .approve, decidedAtUnixMilliseconds: wall()))
                do {
                    _ = try await menu.makeInteractiveControlGrantReview(.init(commandID: UUID(), requestedAtUnixMilliseconds: wall()))
                    throw Failure.unexpectedReview
                } catch MacLocalXPCMenuPairingCommandErrorV1.commandFailed {
                    emit("signed-control-grant-decline-approve-verified")
                }
            }
            let admission = try LocalInteractiveAdmissionPublicationV1(commandID: UUID(),
                menuAppGeneration: interactive.effects.menuGeneration, revision: 1,
                selectedDisplayID: interactive.effects.displayID)
            let published = try await menu.publishInteractiveAdmission(admission)
            try published.validate(against: admission)
            emit("signed-interactive-admission-verified")
        }
        let routes = try AtomicFileClientConfiguredRouteStoreV1(directory: directory.appendingPathComponent("client-routes"))
        if try await routes.snapshot(hostID: record.hostID) == nil {
            let plan = ClientConfiguredRouteBootstrapPlanV1(pairedHost: record)
            let choices = Dictionary(uniqueKeysWithValues: plan.endpointsRequiringExplicitChoice.map {
                ($0, ClientConfiguredRouteProvenanceV1.privateNetwork)
            })
            let catalog = try plan.complete(explicitChoices: choices,
                routeID: { _ in try WireBytes16(withUnsafeBytes(of: UUID().uuid) { Data($0) }) })
            _ = try await routes.replaceAtomically(catalog, expectedRevision: nil)
        }
        if actDenial {
            try await ProbeActWireClient.denied(record: record, custody: custody, emit: emit)
            return
        }
        if let actFault {
            try await ProbeActWireClient.fault(record: record, custody: custody, directory: directory,
                mode: actFault, emit: emit)
            return
        }
        let network = try await NetworkClientConfiguredRouteApplicationProductFactoryV1.make(hostID: record.hostID,
            pairedHosts: reopened, routes: routes,
            runtime: .init(custody: custody,
                clock: { .init(wallNowUnixMilliseconds: wall(), monotonicNowMilliseconds: mono()) },
                verificationQueue: DispatchQueue(label: "Probe.primary.verify"),
                connectionQueue: DispatchQueue(label: "Probe.primary.connection"),
                monotonicNow: { Int64(mono()) }, jitterBasisPoints: { 10_000 }))
        do {
            try await network.binding.start()
            try await network.binding.setForeground(true)
            try await network.binding.setNetworkReachable(true)
            if revocationReplay {
                let rejectionDeadline = ContinuousClock.now + .seconds(8)
                while (await network.binding.snapshot()).lifecycle.reconnect.reconnect.failedRounds == 0,
                      ContinuousClock.now < rejectionDeadline {
                    guard network.primaryState.snapshot().availability != .connected else { throw Failure.notConnected }
                    try await Task.sleep(for: .milliseconds(20))
                }
                guard (await network.binding.snapshot()).lifecycle.reconnect.reconnect.failedRounds > 0,
                      network.primaryState.snapshot().availability != .connected else { throw Failure.notConnected }
                emit("revoked-client-reconnect-rejected")
                await network.interactiveRoles.close()
                await network.binding.close()
                return
            }
            let deadline = ContinuousClock.now + .seconds(8)
            while network.primaryState.snapshot().availability != .connected, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            guard network.primaryState.snapshot().availability == .connected else { throw Failure.notConnected }
            emit("real-primary-authentication-verified")
            try await network.primaryState.refreshStatus()
            let first = try await observation(network.primaryState)
            guard first.snapshot.hostID.rawValue == record.hostID else { throw Failure.noObservation }
            try await network.primaryState.refreshStatus()
            let second = try await observation(network.primaryState, after: first)
            guard second.snapshot.generation == first.snapshot.generation,
                  second.snapshot.revision > first.snapshot.revision else { throw Failure.noObservation }
            emit("real-observe-sequence-verified")
            if act || actReplay {
                try await ProbeActClient.run(network: network, menu: menu, deviceID: record.deviceID,
                    directory: directory, replay: actReplay, emit: emit)
            }
            if revocationReviewOnly {
                emit("requesting-unconfirmed-revocation-review")
                let reply = try await menu.makeDeviceRevocationReview(.init(commandID: UUID(),
                    deviceID: record.deviceID, requestedAtUnixMilliseconds: wall()))
                let command = try LocalDeviceRevocationCommandV0(commandID: UUID(), review: reply.review,
                    confirmedAtUnixMilliseconds: wall())
                try writePrivate(command, to: directory.appendingPathComponent("abandoned-revocation-review.json"))
                emit("unconfirmed-revocation-review-created")
            }
            if let interactive {
                try await control(network: network, menu: menu, interactive: interactive,
                    deviceID: record.deviceID, directory: directory, signer: try ClientCustodiedSessionSignerV0(custody: custody, sessionKey: record.sessionKey), emit: emit)
            }
            await network.interactiveRoles.close()
            await network.binding.close()
        } catch {
            await network.interactiveRoles.close()
            await network.binding.close()
            throw error
        }
    }

    @available(macOS 26.0, *)
    private static func control(network: NetworkClientConfiguredRouteApplicationProductV1,
        menu: MacLocalXPCClientV1, interactive: ProbeInteractiveMenu,
        deviceID: UUID, directory: URL, signer: any ClientSessionAuthenticationSigningV0,
        emit: @escaping @Sendable (String) -> Void) async throws {
        let primaryID = network.primaryState.snapshot().connectionID
        if interactive.scenario == .admissionRace || interactive.scenario == .revocationRace {
            await interactive.effects.pauseNextDesktop()
        }
        _ = try await network.primaryState.beginInteractiveControl(effects: [.view, .pointer, .keyboard])
        if interactive.scenario == .revocationRace {
            let pauseDeadline = ContinuousClock.now + .seconds(3)
            while !(await interactive.effects.desktopIsWaiting), ContinuousClock.now < pauseDeadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard await interactive.effects.desktopIsWaiting else { throw Failure.notConnected }
            emit("revocation-race-desktop-pause-observed")
            let review = try await menu.makeDeviceRevocationReview(.init(commandID: UUID(),
                deviceID: deviceID, requestedAtUnixMilliseconds: wall()))
            let command = try LocalDeviceRevocationCommandV0(commandID: UUID(), review: review.review,
                confirmedAtUnixMilliseconds: wall())
            let revoke = Task { try await menu.revokeDevice(command) }
            do {
                let fenceDeadline = ContinuousClock.now + .seconds(1)
                while network.primaryState.snapshot().connectionID != nil, ContinuousClock.now < fenceDeadline {
                    try await Task.sleep(for: .milliseconds(10))
                }
                guard network.primaryState.snapshot().connectionID == nil,
                      await interactive.effects.desktopIsWaiting else { throw Failure.notConnected }
                emit("revocation-race-primary-fenced-before-desktop-resume")
                await interactive.effects.resumeDesktop()
                let receipt = try await revoke.value
                try receipt.validate(against: command)
                let idleDeadline = ContinuousClock.now + .seconds(5)
                while await interactive.runtime.state() != .idle, ContinuousClock.now < idleDeadline {
                    try await Task.sleep(for: .milliseconds(10))
                }
                let effects = await interactive.effects.snapshot()
                guard effects.started == 0, await interactive.runtime.state() == .idle,
                      network.primaryState.snapshot().connectionID == nil else {
                    emit("revocation-race-install-count:\(effects.started)")
                    throw Failure.notConnected
                }
                guard try await menu.revokeDevice(command) == receipt else { throw Failure.unexpectedReview }
                emit("production-revocation-during-preparation-rejected")
                return
            } catch {
                await interactive.effects.resumeDesktop()
                revoke.cancel()
                _ = try? await revoke.value
                throw error
            }
        }
        if interactive.scenario == .admissionRace {
            let pauseDeadline = ContinuousClock.now + .seconds(3)
            while !(await interactive.effects.desktopIsWaiting), ContinuousClock.now < pauseDeadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard await interactive.effects.desktopIsWaiting else { throw Failure.notConnected }
            emit("race-desktop-pause-observed")
            let withdrawn = try LocalInteractiveAdmissionPublicationV1(commandID: UUID(),
                menuAppGeneration: interactive.effects.menuGeneration, revision: 2, selectedDisplayID: nil)
            _ = try await menu.publishInteractiveAdmission(withdrawn)
            emit("race-admission-withdrawn")
            await interactive.effects.resumeDesktop()
            emit("race-desktop-released")
            let denialDeadline = ContinuousClock.now + .seconds(5)
            var denied = false
            while ContinuousClock.now < denialDeadline {
                if case .remoteRejected = network.primaryState.snapshot().controlState { denied = true; break }
                try await Task.sleep(for: .milliseconds(20))
            }
            guard denied, await interactive.runtime.state() == .idle,
                  await interactive.effects.snapshot().started == 0,
                  network.primaryState.snapshot().connectionID == primaryID else { throw Failure.notConnected }
            emit("race-control-rejection-verified")
            try await observeAfterControl(network, emit: emit)
            emit("production-final-admission-race-rejected")
            return
        }
        let installDeadline = ContinuousClock.now + .seconds(8)
        var ready = false
        while ContinuousClock.now < installDeadline {
            if case .roleChannelsReady = await network.interactiveRoles.state,
               case .active = await interactive.runtime.state() { ready = true; break }
            if case let .remoteRejected(error) = network.primaryState.snapshot().controlState {
                FileHandle.standardOutput.write(Data("control-rejected:\(error.code)\n".utf8))
                throw Failure.notConnected
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard ready else { throw Failure.notConnected }
        emit("production-lease-and-role-authentication-verified")
        var nativeSession: (retire: @Sendable () -> Void, verify: @Sendable () async throws -> Void)?
        defer { nativeSession?.retire() }
        if interactive.scenario == .native {
            nativeSession = try await ProbeNativeFlow.run(network: network, signer: signer, emit: emit)
        }
        if interactive.scenario == .revoke {
            let abandoned: LocalDeviceRevocationCommandV0 = try readPrivate(directory.appendingPathComponent("abandoned-revocation-review.json"))
            do { _ = try await menu.revokeDevice(abandoned); throw Failure.unexpectedReview }
            catch MacLocalXPCMenuPairingCommandErrorV1.commandFailed { emit("prior-menu-revocation-review-rejected") }
            let request = try LocalDeviceRevocationReviewRequestV1(commandID: UUID(), deviceID: deviceID,
                requestedAtUnixMilliseconds: wall())
            let first = try await menu.makeDeviceRevocationReview(request)
            guard try await menu.makeDeviceRevocationReview(request) == first else { throw Failure.unexpectedReview }
            do {
                _ = try await menu.makeDeviceRevocationReview(.init(commandID: request.commandID,
                    deviceID: request.deviceID, requestedAtUnixMilliseconds: request.requestedAtUnixMilliseconds - 1))
                throw Failure.unexpectedReview
            } catch MacLocalXPCMenuPairingCommandErrorV1.commandFailed { emit("changed-review-request-replay-rejected") }
            let fresh = try await menu.makeDeviceRevocationReview(.init(commandID: UUID(), deviceID: deviceID,
                requestedAtUnixMilliseconds: wall()))
            guard fresh.review.reviewID != first.review.reviewID else { throw Failure.unexpectedReview }
            do {
                _ = try await menu.revokeDevice(.init(commandID: UUID(), review: first.review, confirmedAtUnixMilliseconds: wall()))
                throw Failure.unexpectedReview
            } catch MacLocalXPCMenuPairingCommandErrorV1.commandFailed { emit("replaced-review-revocation-rejected") }
            guard network.primaryState.snapshot().connectionID == primaryID,
                  case .active = await interactive.runtime.state() else { throw Failure.notConnected }
            let command = try LocalDeviceRevocationCommandV0(commandID: UUID(), review: fresh.review,
                confirmedAtUnixMilliseconds: wall())
            let receipt = try await menu.revokeDevice(command)
            let revokeDeadline = ContinuousClock.now + .seconds(5)
            while (await interactive.runtime.state() != .idle || network.primaryState.snapshot().connectionID != nil),
                  ContinuousClock.now < revokeDeadline { try await Task.sleep(for: .milliseconds(20)) }
            let effects = await interactive.effects.snapshot()
            guard await interactive.runtime.state() == .idle, network.primaryState.snapshot().connectionID == nil,
                  effects.started == 1, effects.stopped == 1, effects.released >= 1,
                  effects.blanked >= 1, effects.cleared >= 1 else { throw Failure.notConnected }
            guard try await menu.revokeDevice(command) == receipt else { throw Failure.unexpectedReview }
            do {
                _ = try await menu.revokeDevice(.init(commandID: command.commandID, review: command.review,
                    confirmedAtUnixMilliseconds: command.confirmedAtUnixMilliseconds + 1))
                throw Failure.unexpectedReview
            } catch MacLocalXPCMenuPairingCommandErrorV1.commandFailed { emit("changed-revocation-replay-rejected") }
            try writePrivate(RevocationCheckpoint(command: command, receipt: receipt),
                to: directory.appendingPathComponent("revocation-receipt.json"))
            emit("signed-revocation-retires-primary-and-control")
            return
        }
        if interactive.scenario == .menuLoss {
            menu.cancel()
            let lossDeadline = ContinuousClock.now + .seconds(5)
            while await interactive.runtime.state() != .idle, ContinuousClock.now < lossDeadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let retired = await interactive.effects.snapshot()
            guard await interactive.runtime.state() == .idle,
                  retired.started == 1, retired.stopped == 1,
                  retired.released >= 1, retired.blanked >= 1, retired.cleared >= 1,
                  network.primaryState.snapshot().connectionID == primaryID else { throw Failure.notConnected }
            try await observeAfterControl(network, emit: emit)
            emit("production-menu-loss-retires-runtime-preserves-observe")
            return
        }
        let renewalDeadline = ContinuousClock.now + .seconds(20)
        while await interactive.effects.snapshot().renewed < 2, ContinuousClock.now < renewalDeadline {
            guard case .active = await interactive.runtime.state() else { throw Failure.notConnected }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard await interactive.effects.snapshot().renewed >= 2 else { throw Failure.notConnected }
        emit("production-signed-lease-renewal-verified")
        if let nativeSession {
            try await nativeSession.verify()
            emit("native-enrollment-survives-lease-renewals")
        }
        _ = try await network.primaryState.endInteractiveControl()
        let stopDeadline = ContinuousClock.now + .seconds(5)
        while network.primaryState.snapshot().controlState != .inactive, ContinuousClock.now < stopDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let stopped = await interactive.effects.snapshot()
        guard network.primaryState.snapshot().controlState == .inactive,
              network.primaryState.snapshot().connectionID == primaryID,
              await interactive.runtime.state() == .idle,
              stopped.started == 1, stopped.stopped == 1,
              stopped.released >= 1, stopped.blanked >= 1, stopped.cleared >= 1 else { throw Failure.notConnected }
        try await observeAfterControl(network, emit: emit)
        if interactive.scenario == .native { try ProbeNativeFlow.requireCleanup(); emit("native-host-stop-cleanup-verified") }
        emit("production-stop-preserves-observe-verified")
    }

    private static func writePrivate<Value: Encodable>(_ value: Value, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private static func readPrivate<Value: Decodable>(_ url: URL) throws -> Value {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw Failure.unsafeStorage }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    private static func observeAfterControl(_ network: NetworkClientConfiguredRouteApplicationProductV1,
        emit: @escaping @Sendable (String) -> Void) async throws {
        let prior = network.primaryState.snapshot().observedStatus
        try await network.primaryState.refreshStatus()
        _ = try await observation(network.primaryState, after: prior)
        emit("observe-after-control-boundary-verified")
    }

    private static func observation(_ state: NetworkClientPrimaryApplicationStateV0,
                                    after prior: ClientObservedStatusV0? = nil) async throws -> ClientObservedStatusV0 {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            let snapshot = state.snapshot()
            guard snapshot.availability == .connected, snapshot.statusError == nil else { throw Failure.noObservation }
            if let observed = snapshot.observedStatus, observed != prior { return observed }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.noObservation
    }
}
