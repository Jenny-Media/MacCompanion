#if os(macOS)
import CompanionIPC
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionLocalXPCPlatform
@testable import CompanionAgentProductPlatform
import CryptoKit
import Foundation
import Testing

private actor NativeProxySenderV1: MacLocalXPCInteractiveLeaseSendingV1 {
    private(set) var commands: [LocalInteractiveNativeBackendCommandV1] = []
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var cancellationObserved = false
    private func markCancellation() { cancellationObserved = true }
    private let pausePresentation: Bool
    private let pauseHealth: Bool
    private let pause: Bool
    private let wrongReply: Bool
    private var activationPendingCount: Int
    init(pause: Bool = false, wrongReply: Bool = false, pauseHealth: Bool = false, pausePresentation: Bool = false, activationPendingCount: Int = 0) {
        self.pause = pause; self.wrongReply = wrongReply; self.pauseHealth = pauseHealth; self.pausePresentation = pausePresentation
        self.activationPendingCount = activationPendingCount
    }
    func release() { waiter?.resume(); waiter = nil }
    func nativeBackend(_ command: LocalInteractiveNativeBackendCommandV1) async throws -> LocalInteractiveNativeBackendReceiptV1 {
        commands.append(command)
        if command.operation == .activate {
            if activationPendingCount > 0 {
                activationPendingCount -= 1
                return try .init(command: command, activationPending: true)
            }
            return try .init(command: command, portBase: 58989)
        }
        if command.operation == .prepare {
            if pause {
                await withTaskCancellationHandler(operation: { await withCheckedContinuation { waiter = $0 } },
                    onCancel: { Task { await self.markCancellation() } })
            }
            let replyCommand = wrongReply ? try LocalInteractiveNativeBackendCommandV1(commandID: UUID(), backendID: command.backendID,
                operationID: command.operationID, operation: .prepare, scope: command.scope, clientCertificateDER: Data([1])) : command
            return try .init(command: replyCommand, hostCertificateDER: Data([1, 2, 3]))
        }
        if command.operation == .present {
            if pausePresentation {
                await withTaskCancellationHandler(operation: { await withCheckedContinuation { waiter = $0 } },
                    onCancel: { Task { await self.markCancellation() } })
            }
            let evidence = try nativeProxySampleV1(command)
            return try .init(command: command, active: true, captureEvidence: evidence, inputAdmitted: true)
        }
        if command.operation == .health {
            if pauseHealth {
                await withTaskCancellationHandler(operation: { await withCheckedContinuation { waiter = $0 } },
                    onCancel: { Task { await self.markCancellation() } })
            }
            return try .init(command: command, active: true)
        }
        return try .init(command: command)
    }
    func prepareInitialInteractiveDesktop(_ command: LocalInteractiveInitialDesktopPreparationCommandV1) throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 { throw LocalInteractiveNativeBackendErrorV1.unavailable }
    func installInteractiveLease(_ command: InteractiveRuntimeInstallCommandV0) throws -> InteractiveRuntimeInstallReceiptV0 { throw LocalInteractiveNativeBackendErrorV1.unavailable }
    func renewInteractiveLease(_ command: InteractiveRuntimeLeaseRenewalV0) throws { throw LocalInteractiveNativeBackendErrorV1.unavailable }
    func revokeInteractiveLease(_ command: InteractiveRuntimeRevokeCommandV0) throws -> InteractiveRuntimeRevokedReceiptV0 { throw LocalInteractiveNativeBackendErrorV1.unavailable }
}
@available(macOS 26.0, *)
private func nativeProxyWorldV1(_ sender: NativeProxySenderV1) throws -> (MacLocalXPCNativeEnrollmentBackendV1, InteractiveNativeVideoAuthorityV0) {
    let binding = try InteractiveNativeVideoBindingV0(hostID: UUID(), hostFingerprint: Data(repeating: 1, count: 32), clientID: UUID(),
        primaryConnectionID: Data(repeating: 2, count: 16), interactiveSessionID: UUID(), authorizationEpoch: 1, grantRevision: 1,
        policyRevision: 1, controlGeneration: UUID(), expiresAtMonotonicMilliseconds: DispatchTime.now().uptimeNanoseconds / 1_000_000 + 30_000)
    let surface = try InteractiveNativeVideoSurfaceV0(surfaceID: UUID(), surfaceRevision: 1, coordinateSpaceRevision: 1, encodedWidth: 1280, encodedHeight: 720)
    let snapshot = InteractiveNativeVideoRuntimeSnapshotV0(binding: binding, surface: surface,
        logicalWidthPoints: 2560, logicalHeightPoints: 1440, rotation: .degrees0, selectedDisplayID: UUID(),
        visibleMenuAppGeneration: UUID(), visibleMenuAppRevision: 1)
    let authority = try InteractiveNativeVideoAuthorityV0(binding: binding, surface: surface, sessionPublicKeyX963: P256.Signing.PrivateKey().publicKey.x963Representation)
    return (.init(sender: sender, snapshot: snapshot), authority)
}
@Test @available(macOS 26.0, *)
func nativeProxyRetireJoinsPendingPrepareAndRejectsLateCertificate() async throws {
    let sender = NativeProxySenderV1(pause: true)
    let (proxy, authority) = try nativeProxyWorldV1(sender)
    let operationID = UUID()
    let prepare = Task { try await proxy.prepare(operationID: operationID, authority: authority, clientCertificateDER: Data([1])) }
    while await sender.commands.isEmpty { await Task.yield() }
    let retire = Task { await proxy.retire(operationID: operationID) }
    // Health is immediately fenced, even while the uncancellable sender is draining.
    while await !sender.cancellationObserved { await Task.yield() }
    #expect(await proxy.isActive(operationID: operationID) == false)
    await sender.release()
    await retire.value
    await #expect(throws: (any Error).self) { try await prepare.value }
    let commands = await sender.commands
    #expect(commands[0].scope.logicalWidthPoints == 2560 && commands[0].scope.logicalHeightPoints == 1440)
    #expect(commands[0].scope.rotation == .degrees0)
    #expect(commands.map(\.operation) == [.prepare, .retire])
    #expect(commands[0].backendID == commands[1].backendID)
    #expect(commands[0].operationID == commands[1].operationID)
    #expect(commands[0].scope == commands[1].scope)
    #expect(await proxy.isActive(operationID: operationID) == false)
}
@Test @available(macOS 26.0, *)
func nativeProxyRejectsMismatchedReplyAndRetiresExactScope() async throws {
    let sender = NativeProxySenderV1(wrongReply: true)
    let (proxy, authority) = try nativeProxyWorldV1(sender)
    let operationID = UUID()
    await #expect(throws: (any Error).self) {
        try await proxy.prepare(operationID: operationID, authority: authority, clientCertificateDER: Data([1]))
    }
    await proxy.retire(operationID: operationID)
    let commands = await sender.commands
    #expect(commands.map(\.operation) == [.prepare, .retire])
    #expect(commands[0].scope == commands[1].scope)
}
@Test @available(macOS 26.0, *)
func nativeProxyConcurrentHealthReadsJoinWithoutFalseBackendLoss() async throws {
    let sender = NativeProxySenderV1(pauseHealth: true)
    let (proxy, authority) = try nativeProxyWorldV1(sender), operationID = UUID()
    _ = try await proxy.prepare(operationID: operationID, authority: authority, clientCertificateDER: Data([1]))
    let sample = Task { try await proxy.captureEvidence(operationID: operationID) }
    while await !sender.commands.contains(where: { $0.operation == .health }) { await Task.yield() }
    let watchdog = Task { await proxy.isActive(operationID: operationID) }
    // Give the concurrent actor call time to reach the retained read.
    try await Task.sleep(for: .milliseconds(10))
    await sender.release()
    _ = try await sample.value
    #expect(await watchdog.value == true)
    #expect(await sender.commands.filter { $0.operation == .health }.count == 1)
    await proxy.retire(operationID: operationID)
}
@Test @available(macOS 26.0, *)
func nativeProxyRetirementFencesSharedHealthBeforeJoiningLateResult() async throws {
    let sender = NativeProxySenderV1(pauseHealth: true)
    let (proxy, authority) = try nativeProxyWorldV1(sender), operationID = UUID()
    _ = try await proxy.prepare(operationID: operationID, authority: authority, clientCertificateDER: Data([1]))
    let sample = Task { try await proxy.captureEvidence(operationID: operationID) }
    while await !sender.commands.contains(where: { $0.operation == .health }) { await Task.yield() }
    let watcher = Task { await proxy.isActive(operationID: operationID) }
    try await Task.sleep(for: .milliseconds(10))
    let retiring = Task { await proxy.retire(operationID: operationID) }
    while await !sender.cancellationObserved { await Task.yield() }
    #expect(await proxy.isActive(operationID: operationID) == false)
    await sender.release()
    await retiring.value
    await #expect(throws: (any Error).self) { try await sample.value }
    #expect(await watcher.value == false)
    #expect(await sender.commands.map(\.operation) == [.prepare, .health, .retire])
}
private func nativeProxySampleV1(_ command: LocalInteractiveNativeBackendCommandV1) throws -> InteractiveNativeVideoCaptureEvidenceV0 {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent(); guard parent != root else { throw CocoaError(.fileNoSuchFile) }; root = parent
    }
    let path = "valid/native-backend-capture-evidence.json"
    let index = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/manifest.json"))) as! [String: Any]
    guard (index["fixtures"] as! [[String: Any]]).filter({ $0["path"] as? String == path }).count == 1 else { throw CocoaError(.fileNoSuchFile) }
    let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/" + path))) as! [String: Any]
    var record = fixture["record"] as! [String: Any]
    record["operationID"] = command.operationID.uuidString
    record["monotonicNanoseconds"] = DispatchTime.now().uptimeNanoseconds
    record["encodedWidth"] = command.scope.encodedWidth; record["encodedHeight"] = command.scope.encodedHeight
    record["formatWidth"] = command.scope.encodedWidth; record["formatHeight"] = command.scope.encodedHeight
    record["cleanWidth"] = command.scope.encodedWidth; record["cleanHeight"] = command.scope.encodedHeight
    return try .decode(JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes]))
}
@Test @available(macOS 26.0, *)
func nativeProxyHealthWaitsForPresentationThenMakesFreshRead() async throws {
    let sender = NativeProxySenderV1(pausePresentation: true)
    let (proxy, authority) = try nativeProxyWorldV1(sender), operationID = UUID(), id = UUID()
    _ = try await proxy.prepare(operationID: operationID, authority: authority, clientCertificateDER: Data([1]))
    let presenting = Task { try await proxy.admitPresentation(operationID: operationID, nativeGeneration: 1, presentationID: id) }
    while await !sender.commands.contains(where: { $0.operation == .present }) { await Task.yield() }
    let health = Task { await proxy.isActive(operationID: operationID) }
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.bindingMismatch) {
        _ = try await proxy.admitPresentation(operationID: operationID, nativeGeneration: 2, presentationID: id)
    }
    try await Task.sleep(for: .milliseconds(10))
    #expect(await sender.commands.filter { $0.operation == .health }.isEmpty)
    await sender.release()
    #expect(try await presenting.value)
    #expect(await health.value)
    #expect(await sender.commands.map(\.operation) == [.prepare, .present, .health])
    await proxy.retire(operationID: operationID)
}
@Test @available(macOS 26.0, *)
func nativeProxyRetirementFencesPresentationAndWaitingHealth() async throws {
    let sender = NativeProxySenderV1(pausePresentation: true)
    let (proxy, authority) = try nativeProxyWorldV1(sender), operationID = UUID()
    _ = try await proxy.prepare(operationID: operationID, authority: authority, clientCertificateDER: Data([1]))
    let presenting = Task { try await proxy.admitPresentation(operationID: operationID, nativeGeneration: 1, presentationID: UUID()) }
    while await !sender.commands.contains(where: { $0.operation == .present }) { await Task.yield() }
    let health = Task { await proxy.isActive(operationID: operationID) }
    let retiring = Task { await proxy.retire(operationID: operationID) }
    while await !sender.cancellationObserved { await Task.yield() }
    #expect(await proxy.isActive(operationID: operationID) == false)
    await sender.release(); await retiring.value
    await #expect(throws: (any Error).self) { _ = try await presenting.value }
    #expect(await health.value == false)
    #expect(await sender.commands.map(\.operation) == [.prepare, .present, .retire])
}

@Test @available(macOS 26.0, *)
func nativeProxyPolledActivationCorrelatesEachReplyAndKeepsOriginalScope() async throws {
    let sender = NativeProxySenderV1(activationPendingCount: 2)
    let (proxy, authority) = try nativeProxyWorldV1(sender), op = UUID()
    _ = try await proxy.prepare(operationID: op, authority: authority, clientCertificateDER: Data([1]))
    let endpoint = try await proxy.activate(operationID: op)
    #expect(endpoint.portBase == 58989)
    let polls = await sender.commands.filter { $0.operation == .activate }
    #expect(polls.count == 3 && Set(polls.map(\.commandID)).count == 3)
    #expect(polls.allSatisfy { $0.pollActivation == true && $0.scope == polls[0].scope && $0.operationID == op })
    await proxy.retire(operationID: op)
}
@Test @available(macOS 26.0, *)
func nativeProxyStopDuringPolledActivationCannotReturnLateEndpoint() async throws {
    let sender = NativeProxySenderV1(activationPendingCount: 100)
    let (proxy, authority) = try nativeProxyWorldV1(sender), op = UUID()
    _ = try await proxy.prepare(operationID: op, authority: authority, clientCertificateDER: Data([1]))
    let start = Task { try await proxy.activate(operationID: op) }
    while await !sender.commands.contains(where: { $0.operation == .activate }) { await Task.yield() }
    await proxy.retire(operationID: op)
    await #expect(throws: (any Error).self) { try await start.value }
    #expect(await sender.commands.filter { $0.operation == .retire }.count == 1)
    #expect(await proxy.isActive(operationID: op) == false)
}

#endif
