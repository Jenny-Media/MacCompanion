#if os(macOS)
import CompanionDomain
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveHost
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CompanionInteractiveWire
@testable import CompanionMacApplicationPlatform
import CoreGraphics
import CryptoKit
import Foundation
import Testing

@Test func selectedWindowDescriptionMatchesOnlyExactOnScreenIdentity() {
    let target = CGRect(x: 120, y: 75, width: 800, height: 532)
    func description(_ windowID: UInt32, _ processID: Int32, _ frame: CGRect) -> [String: Any] {
        [kCGWindowNumber as String: NSNumber(value: windowID),
         kCGWindowOwnerPID as String: NSNumber(value: processID),
         kCGWindowBounds as String: frame.dictionaryRepresentation]
    }
    let sibling = description(22, 7, CGRect(x: 0, y: 0, width: 300, height: 200))
    let selected = description(21, 7, target)
    #expect(MacSelectedWindowDescriptionV1.bounds(in: [sibling, selected], windowID: 21, processID: 7) == target)
    #expect(MacSelectedWindowDescriptionV1.bounds(in: [sibling], windowID: 21, processID: 7) == nil)
    #expect(MacSelectedWindowDescriptionV1.bounds(in: [description(21, 8, target)], windowID: 21, processID: 7) == nil)
    #expect(MacSelectedWindowDescriptionV1.bounds(in: [selected, selected], windowID: 21, processID: 7) == nil)
}

@available(macOS 26.0, *)
@Test func nativeCaptureDisplayRoutingUsesIndexedCases() throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent()
        try #require(parent != root)
        root = parent
    }
    let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
        root.appendingPathComponent("spec/fixtures/native-selected-capture-context-v0.1.json"))) as? [String: Any])
    for row in try #require(fixture["captureDisplayCases"] as? [[String: Any]]) {
        let kindValue = try #require(row["kind"] as? String)
        let kind = try #require(InteractiveSurfaceKind(rawValue: kindValue))
        let lease = try #require(row["leasePhysicalDisplayID"] as? NSNumber).uint32Value
        let selected = (row["selectedPhysicalDisplayID"] as? NSNumber)?.uint32Value
        if row["denied"] as? Bool == true {
            #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
                try MacInteractiveNativeBackendOwnerV1.captureDisplayID(kind: kind, leaseDisplayID: lease, selectedDisplayID: selected)
            }
        } else {
            let expected = try #require(row["capturePhysicalDisplayID"] as? NSNumber).uint32Value
            #expect(try MacInteractiveNativeBackendOwnerV1.captureDisplayID(kind: kind, leaseDisplayID: lease, selectedDisplayID: selected) == expected)
        }
    }
}

@Test func applicationCropExcludesFinderDesktopAndOverlaysUsingIndexedCases() throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent(); try #require(parent != root); root = parent
    }
    let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
        root.appendingPathComponent("spec/fixtures/native-selected-capture-context-v0.1.json"))) as? [String: Any])
    func rect(_ values: [NSNumber]) -> CGRect {
        CGRect(x: values[0].doubleValue, y: values[1].doubleValue,
               width: values[2].doubleValue, height: values[3].doubleValue)
    }
    for row in try #require(fixture["applicationCropCases"] as? [[String: Any]]) {
        let display = rect(try #require(row["displayBounds"] as? [NSNumber]))
        let processID = try #require(row["processID"] as? NSNumber).int32Value
        let descriptions = try #require(row["windows"] as? [[String: Any]]).map { window -> [String: Any] in
            [kCGWindowOwnerPID as String: try #require(window["processID"] as? NSNumber),
             kCGWindowLayer as String: try #require(window["layer"] as? NSNumber),
             kCGWindowIsOnscreen as String: try #require(window["onScreen"] as? NSNumber),
             kCGWindowBounds as String: rect(try #require(window["bounds"] as? [NSNumber])).dictionaryRepresentation]
        }
        let actual = MacSelectedWindowDescriptionV1.applicationBounds(in: descriptions,
            processID: processID, displayBounds: display)
        if let expected = row["crop"] as? [NSNumber] { #expect(actual == rect(expected)) }
        else { #expect(actual == nil) }
    }
}

private actor NativeBackendGateV1 {
    private(set) var entered = false
    private var released = false
    private var wait: CheckedContinuation<Void, Never>?
    func suspend() async { entered = true; if released { return }; await withCheckedContinuation { wait = $0 } }
    func release() { released = true; wait?.resume(); wait = nil }
    func waitUntilEntered() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !entered, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(entered)
    }
}
private actor NativeBackendProbeV1: MacInteractiveNativeStreamReplacingV1 {
    private let continuity: Bool
    private var retained = false
    private var currentOperation: UUID?
    private(set) var preparations = 0
    private(set) var activations = 0
    private(set) var retirements = 0
    private var evidence: InteractiveNativeVideoCaptureEvidenceV0?
    private var nextEvidenceReadGate: NativeBackendGateV1?
    private let inputPermit: MacInteractiveNativeBackendPermitV1?
    private let prepareGate: NativeBackendGateV1?
    private let retireGate: NativeBackendGateV1?
    private let activateGate: NativeBackendGateV1?
    private let retainGate: NativeBackendGateV1?
    init(prepareGate: NativeBackendGateV1?, retireGate: NativeBackendGateV1?, inputPermit: MacInteractiveNativeBackendPermitV1? = nil, continuity: Bool = false, activateGate: NativeBackendGateV1? = nil, retainGate: NativeBackendGateV1? = nil) {
        self.continuity = continuity
        self.prepareGate = prepareGate; self.retireGate = retireGate; self.inputPermit = inputPermit
        self.activateGate = activateGate
        self.retainGate = retainGate
    }
    func canPostInput(operationID: UUID) -> Bool { activations > 0 && retirements == 0 && inputPermit != nil }
    func postInputBatch(operationID: UUID, beforeDeadlineNanoseconds: UInt64, batch: @escaping @Sendable () throws -> Void) throws {
        guard canPostInput(operationID: operationID), let inputPermit else { throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable }
        try inputPermit.withCurrentInput(beforeDeadlineNanoseconds: beforeDeadlineNanoseconds, batch)
    }
    func prepare(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0, clientCertificateDER: Data) async -> Data {
        preparations += 1; currentOperation = operationID; await prepareGate?.suspend(); return Data([1, 2, 3])
    }
    func activate(operationID: UUID) async throws -> InteractiveNativeVideoEndpointV0 {
        retained = false; activations += 1; await activateGate?.suspend()
        return try .init(portBase: 58989)
    }
    func isActive(operationID: UUID) -> Bool { activations > 0 && retirements == 0 }
    func captureEvidence(operationID: UUID) async -> InteractiveNativeVideoCaptureEvidenceV0? {
        let gate = nextEvidenceReadGate; nextEvidenceReadGate = nil
        await gate?.suspend()
        return evidence
    }
    func suspendNextEvidenceRead(_ gate: NativeBackendGateV1) { nextEvidenceReadGate = gate }
    func setEvidence(_ value: InteractiveNativeVideoCaptureEvidenceV0) { evidence = value }
    func retire(operationID: UUID) async {
        if continuity && currentOperation != operationID { return }
        retirements += 1; retained = false; await retireGate?.suspend()
    }
    func supportsStreamContinuity(operationID: UUID) -> Bool { continuity && currentOperation == operationID && !retained }
    func retainStream(operationID: UUID) async throws {
        guard continuity, currentOperation == operationID, retirements == 0 else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        retained = true
        await retainGate?.suspend()
    }
    func isStreamRetained(operationID: UUID) -> Bool { continuity && retained && currentOperation == operationID && retirements == 0 }
    func configureRetainedReplacement(predecessorOperationID: UUID, authority: InteractiveNativeVideoAuthorityV0,
        physicalDisplayID: UInt32, geometry: InteractiveNativeVideoContentGeometryV0, selected: MacManagedNativeSelectedCaptureV1?) throws {
        guard retained, currentOperation == predecessorOperationID else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
    }
}
private actor NativeBackendFactorySpyV1 {
    private(set) var created: [(NativeBackendProbeV1, MacInteractiveNativeBackendPermitV1)] = []
    func append(_ backend: NativeBackendProbeV1, permit: MacInteractiveNativeBackendPermitV1) { created.append((backend, permit)) }
}
private actor NativeBackendSnapshotReaderV1 {
    var command: InteractiveRuntimeInstallCommandV0
    var receipt: InteractiveRuntimeInstallReceiptV0
    var admitted = true
    private(set) var inputPaused = false
    private(set) var installedAuthorization: InteractiveRuntimeNativeInputPostingAuthorizationV0?
    private(set) var installations = 0
    private var nextOriginalReadGate: NativeBackendGateV1?
    func suspendNextOriginalRead(_ gate: NativeBackendGateV1) { nextOriginalReadGate = gate }
    func install(_ authorization: InteractiveRuntimeNativeInputPostingAuthorizationV0, fence: InteractiveNativeVideoRequestFenceV0, now: UInt64) throws {
        guard inputPaused, installedAuthorization == nil, try read(fence, now: now) != nil else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        installedAuthorization = authorization; installations += 1
    }
    init(command: InteractiveRuntimeInstallCommandV0, receipt: InteractiveRuntimeInstallReceiptV0) { self.command = command; self.receipt = receipt }
    func revoke() { admitted = false }
    func originalCurrent(_ scope: LocalInteractiveNativeBackendScopeV1, now: UInt64) async -> Bool {
        let current = admitted && command.commandID == scope.controlGeneration && receipt.menuAppGeneration == scope.menuAppGeneration
            && command.sessionDeadlineMonotonicNanoseconds / 1_000_000 == scope.expiresAtMonotonicMilliseconds
            && now < command.sessionDeadlineMonotonicNanoseconds
        let gate = nextOriginalReadGate; nextOriginalReadGate = nil
        await gate?.suspend()
        return current
    }
    func rebase(_ scope: LocalInteractiveNativeBackendScopeV1) throws {
        let previous = command.lease
        let lease = try InteractiveExecutionLease(leaseID: UUID(), hostID: previous.hostID, deviceID: previous.deviceID,
            interactiveSessionID: previous.interactiveSessionID, authorizationEpoch: previous.authorizationEpoch,
            selectedDisplayID: scope.selectedDisplayID, surfaceID: scope.surfaceID,
            surfaceRevision: .init(rawValue: UInt64(scope.surfaceRevision)), coordinateRevision: .init(rawValue: UInt64(scope.coordinateSpaceRevision)),
            allowedInteractionClasses: Set(previous.allowedInteractionClasses), renewalCounter: previous.renewalCounter,
            issuedAtMonotonicNanoseconds: previous.issuedAtMonotonicNanoseconds, expiresAtMonotonicNanoseconds: previous.expiresAtMonotonicNanoseconds)
        let descriptor = try AdaptiveSurfaceDescriptor(interactiveSessionID: scope.interactiveSessionID,
            authorizationEpoch: previous.authorizationEpoch, surfaceID: scope.surfaceID, kind: .desktop,
            surfaceRevision: .init(rawValue: lease.surfaceRevision.rawValue), coordinateSpaceRevision: .init(rawValue: lease.coordinateRevision.rawValue),
            encodedWidth: UInt16(scope.encodedWidth), encodedHeight: UInt16(scope.encodedHeight),
            logicalWidthPoints: scope.logicalWidthPoints, logicalHeightPoints: scope.logicalHeightPoints,
            interactionClasses: Set(previous.allowedInteractionClasses), privacyProfile: .visualOnly, metadataFields: [],
            createdAtMonotonicMilliseconds: 1, expiresAtMonotonicMilliseconds: 30_000)
        command = try .init(commandID: command.commandID, lease: lease, deviceDisplayName: command.deviceDisplayName,
            surfaceDescriptor: descriptor, sessionDeadlineMonotonicNanoseconds: command.sessionDeadlineMonotonicNanoseconds)
        receipt = try .init(correlationID: command.commandID, leaseID: lease.leaseID, interactiveSessionID: lease.interactiveSessionID,
            selectedDisplayID: lease.selectedDisplayID, menuAppGeneration: receipt.menuAppGeneration, menuAppRevision: scope.menuAppRevision,
            readyInteractionClasses: Set(receipt.readyInteractionClasses), indicatorVisible: true)
    }
    func pause(_ fence: InteractiveNativeVideoRequestFenceV0, now: UInt64) throws {
        guard try read(fence, now: now) != nil else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        inputPaused = true; installedAuthorization?.revoke(); installedAuthorization = nil
    }
    func read(_ fence: InteractiveNativeVideoRequestFenceV0, now: UInt64) throws -> LocalInteractiveNativeRuntimeSnapshotV1? {
        guard admitted else { return nil }
        let snapshot = try LocalInteractiveNativeRuntimeSnapshotV1(command: command, receipt: receipt, fence: fence)
        return snapshot.isCurrent(nowMonotonicNanoseconds: now) ? snapshot : nil
    }
}
private final class NativeCaptureGeometryReaderV1: @unchecked Sendable {
    private let lock = NSLock()
    private var width = 2560
    private var height = 1440
    private var available = true
    func change(width: Int, height: Int, available: Bool = true) {
        lock.withLock { self.width = width; self.height = height; self.available = available }
    }
    func read(_ scope: LocalInteractiveNativeBackendScopeV1) throws -> InteractiveNativeVideoContentGeometryV0 {
        let facts = lock.withLock { (width, height, available) }
        guard facts.2 else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        return try MacInteractiveNativeCaptureGeometryV1.project(scope: scope,
            bounds: CGRect(x: 0, y: 0, width: 1280, height: 720), capturePixelWidth: facts.0,
            capturePixelHeight: facts.1, rotationDegrees: 0)
    }
}
@available(macOS 26.0, *)
private struct NativeBackendWorldV1 {
    let owner: MacInteractiveNativeBackendOwnerV1
    let scope: LocalInteractiveNativeBackendScopeV1
    let reader: NativeBackendSnapshotReaderV1
    let spy = NativeBackendFactorySpyV1()
    let geometryReader = NativeCaptureGeometryReaderV1()
    init(factoryGate: NativeBackendGateV1? = nil, prepareGate: NativeBackendGateV1? = nil, retireGate: NativeBackendGateV1? = nil,
         denyInputPause: Bool = false, denySelectedCapture: Bool = false,
         supportsInput: Bool = false, continuity: Bool = false, installGate: NativeBackendGateV1? = nil, activateGate: NativeBackendGateV1? = nil, retainGate: NativeBackendGateV1? = nil) throws {
        let now = DispatchTime.now().uptimeNanoseconds
        let hostID = UUID(), sessionID = UUID(), displayID = UUID(), generation = UUID()
        let binding = try InteractiveNativeVideoBindingV0(hostID: hostID, hostFingerprint: Data(repeating: 1, count: 32), clientID: UUID(),
            primaryConnectionID: Data(repeating: 2, count: 16), interactiveSessionID: sessionID, authorizationEpoch: 1,
            grantRevision: 1, policyRevision: 1, controlGeneration: generation, expiresAtMonotonicMilliseconds: now / 1_000_000 + 30_000)
        let surface = try InteractiveNativeVideoSurfaceV0(surfaceID: UUID(), surfaceRevision: 1, coordinateSpaceRevision: 1, encodedWidth: 1280, encodedHeight: 720)
        let lease = try InteractiveExecutionLease(leaseID: UUID(), hostID: hostID, deviceID: UUID(), interactiveSessionID: sessionID,
            authorizationEpoch: .init(rawValue: 1), selectedDisplayID: displayID, surfaceID: surface.surfaceID,
            surfaceRevision: .init(rawValue: 1), coordinateRevision: .init(rawValue: 1), allowedInteractionClasses: [.view],
            renewalCounter: 0, issuedAtMonotonicNanoseconds: now, expiresAtMonotonicNanoseconds: now + 10_000_000_000)
        let descriptor = try AdaptiveSurfaceDescriptor(interactiveSessionID: sessionID, authorizationEpoch: lease.authorizationEpoch,
            surfaceID: surface.surfaceID, kind: .desktop, surfaceRevision: .init(rawValue: 1), coordinateSpaceRevision: .init(rawValue: 1),
            encodedWidth: 1280, encodedHeight: 720, logicalWidthPoints: 1280, logicalHeightPoints: 720,
            interactionClasses: [.view], privacyProfile: .visualOnly, metadataFields: [], createdAtMonotonicMilliseconds: 1, expiresAtMonotonicMilliseconds: 30_000)
        let install = try InteractiveRuntimeInstallCommandV0(commandID: generation, lease: lease, deviceDisplayName: .init("Native QA"),
            surfaceDescriptor: descriptor, sessionDeadlineMonotonicNanoseconds: binding.expiresAtMonotonicMilliseconds * 1_000_000)
        let installed = try InteractiveRuntimeInstallReceiptV0(correlationID: generation, leaseID: lease.leaseID,
            interactiveSessionID: sessionID, selectedDisplayID: displayID, menuAppGeneration: UUID(), menuAppRevision: 1,
            readyInteractionClasses: [.view], indicatorVisible: true)
        scope = try .init(binding: binding, surface: surface,
            logicalWidthPoints: 1280, logicalHeightPoints: 720, rotation: .degrees0, selectedDisplayID: displayID,
            menuAppGeneration: installed.menuAppGeneration, menuAppRevision: 1,
            sessionPublicKeyX963: P256.Signing.PrivateKey().publicKey.x963Representation)
        reader = NativeBackendSnapshotReaderV1(command: install, receipt: installed)
        let reader = self.reader, spy = self.spy, geometryReader = self.geometryReader
        let originalControl: (@Sendable (LocalInteractiveNativeBackendScopeV1, UInt64) async throws -> Bool)? = continuity ? { @Sendable scope, now in await reader.originalCurrent(scope, now: now) } : nil
        owner = .init(readSnapshot: { try await reader.read($0, now: $1) },
            pauseInput: {
                guard !denyInputPause else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                try await reader.pause($0, now: $1)
            }, installInput: { authorization, fence, now in
                await installGate?.suspend()
                try await reader.install(authorization, fence: fence, now: now)
            }, resolveDisplay: {
            guard $0 == displayID else { throw LocalInteractiveNativeBackendErrorV1.bindingMismatch }; return 1234
        }, readCaptureGeometry: { _, scope in try geometryReader.read(scope) },
        readSelectedCapture: { _, _ in
            guard !denySelectedCapture else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
            return nil
        }, readOriginalControl: originalControl, factory: { physicalID, geometry, permit, _ in
            #expect(await reader.inputPaused)
            #expect(geometry.capturePixelWidth == 2560 && geometry.capturePixelHeight == 1440)
            #expect(geometry.logicalWidthPoints == 1280 && geometry.logicalHeightPoints == 720)
            guard physicalID == 1234 else { throw LocalInteractiveNativeBackendErrorV1.bindingMismatch }
            let backend = NativeBackendProbeV1(prepareGate: prepareGate, retireGate: retireGate, inputPermit: supportsInput ? permit : nil, continuity: continuity, activateGate: activateGate, retainGate: retainGate)
            await spy.append(backend, permit: permit)
            await factoryGate?.suspend()
            return backend
        })
    }
    func command(_ operation: LocalInteractiveNativeBackendOperationV1, backendID: UUID, operationID: UUID) throws -> LocalInteractiveNativeBackendCommandV1 {
        try .init(commandID: UUID(), backendID: backendID, operationID: operationID, operation: operation, scope: scope,
            clientCertificateDER: operation == .prepare ? Data([4, 5, 6]) : nil)
    }
}

@available(macOS 26.0, *)
@Test func nativeBackendInputPauseFailureCreatesNoBackend() async throws {
    let world = try NativeBackendWorldV1(denyInputPause: true)
    let command = try world.command(.prepare, backendID: UUID(), operationID: UUID())
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
        try await world.owner.handle(command)
    }
    #expect(await world.spy.created.isEmpty)
    #expect(await world.reader.inputPaused == false)
    await world.owner.retire()
}

@available(macOS 26.0, *)
@Test func nativeBackendTargetResolutionFailureCreatesNoBackend() async throws {
    let world = try NativeBackendWorldV1(denySelectedCapture: true)
    let command = try world.command(.prepare, backendID: UUID(), operationID: UUID())
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
        try await world.owner.handle(command)
    }
    #expect(await world.reader.inputPaused)
    #expect(await world.spy.created.isEmpty)
    await world.owner.retire()
}
@available(macOS 26.0, *)
@Test func nativeCaptureProjectionUsesModePixelsAndRejectsInvalidOrChangedDisplayFacts() throws {
    let scope = try NativeBackendWorldV1().scope
    let bounds = CGRect(x: 100, y: -300, width: 1280, height: 720)
    let geometry = try MacInteractiveNativeCaptureGeometryV1.project(scope: scope, bounds: bounds,
        capturePixelWidth: 2560, capturePixelHeight: 1440, rotationDegrees: 0)
    #expect(geometry.capturePixelWidth == 2560 && geometry.capturePixelHeight == 1440)
    #expect(geometry.logicalWidthPoints == 1280 && geometry.logicalHeightPoints == 720)
    #expect(geometry.contentWidth == 1280 && geometry.contentHeight == 720)
    for rotation in [90.0, 180, 270, 45, Double.nan] {
        #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
            try MacInteractiveNativeCaptureGeometryV1.project(scope: scope, bounds: bounds,
                capturePixelWidth: 2560, capturePixelHeight: 1440, rotationDegrees: rotation)
        }
    }
    for pixels in [(0, 1440), (2560, 0), (32769, 1440), (2560, 32769)] {
        #expect(throws: InteractiveNativeVideoContentGeometryErrorV0.invalidDimensions) {
            try MacInteractiveNativeCaptureGeometryV1.project(scope: scope, bounds: bounds,
                capturePixelWidth: pixels.0, capturePixelHeight: pixels.1, rotationDegrees: 0)
        }
    }
    for rect in [CGRect(x: 0, y: 0, width: 1281, height: 720), CGRect(x: 0, y: 0, width: 1280, height: 721),
                 CGRect(x: 0, y: 0, width: 0, height: 720), CGRect(x: CGFloat.infinity, y: 0, width: 1280, height: 720)] {
        #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
            try MacInteractiveNativeCaptureGeometryV1.project(scope: scope, bounds: rect,
                capturePixelWidth: 2560, capturePixelHeight: 1440, rotationDegrees: 0)
        }
    }
}

private func selectedNativeDescriptor(
    scope: LocalInteractiveNativeBackendScopeV1,
    kind: InteractiveSurfaceKind = .window
) throws -> AdaptiveSurfaceDescriptor {
    try .init(interactiveSessionID: scope.interactiveSessionID,
        authorizationEpoch: .init(rawValue: UInt64(scope.authorizationEpoch)),
        surfaceID: scope.surfaceID, kind: kind,
        surfaceRevision: .init(rawValue: UInt64(scope.surfaceRevision)),
        coordinateSpaceRevision: .init(rawValue: UInt64(scope.coordinateSpaceRevision)),
        applicationToken: kind == .desktop ? nil : UUID(),
        windowToken: kind == .window ? UUID() : nil,
        encodedWidth: UInt16(scope.encodedWidth), encodedHeight: UInt16(scope.encodedHeight),
        logicalWidthPoints: scope.logicalWidthPoints, logicalHeightPoints: scope.logicalHeightPoints,
        rotation: scope.rotation, interactionClasses: [.view], privacyProfile: .visualOnly,
        metadataFields: [], createdAtMonotonicMilliseconds: 1, expiresAtMonotonicMilliseconds: 30_000)
}

@available(macOS 26.0, *)
@Test(arguments: [1.0, 2.0], [InteractiveSurfaceKind.window, .application])
func nativeSelectedCaptureUsesSelectedBoundsAndBackingScale(scale: Double, kind: InteractiveSurfaceKind) throws {
    let scope = try NativeBackendWorldV1().scope
    let descriptor = try selectedNativeDescriptor(scope: scope, kind: kind)
    let bounds = CGRect(x: -1800, y: 300, width: 1280, height: 720)
    let target: ScreenCaptureKitLocalActivationTargetV0 = kind == .window
        ? .window(windowID: 42, processID: 123, bundleIdentifier: "test.selected", globalBounds: bounds)
        : .application(processID: 123, bundleIdentifier: "test.selected")
    let geometry = try MacInteractiveNativeCaptureGeometryV1.projectSelectedSurface(
        scope: scope, descriptor: descriptor, bounds: bounds, backingScale: scale, activationTarget: target)
    #expect(geometry.capturePixelWidth == Int(1280 * scale))
    #expect(geometry.capturePixelHeight == Int(720 * scale))
    #expect(geometry.logicalWidthPoints == 1280 && geometry.logicalHeightPoints == 720)
    #expect(geometry.contentWidth == 1280 && geometry.contentHeight == 720)
}

@available(macOS 26.0, *)
@Test func nativeSelectedCaptureRejectsChangedSurfaceBinding() throws {
    let scope = try NativeBackendWorldV1().scope
    let descriptor = try selectedNativeDescriptor(scope: scope)
    let bounds = CGRect(x: 0, y: 0, width: 1280, height: 720)
    let target = ScreenCaptureKitLocalActivationTargetV0.window(
        windowID: 42, processID: 123, bundleIdentifier: "test.selected", globalBounds: bounds)
    let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(descriptor)) as? [String: Any])
    let changes: [(String, Any)] = [
        ("interactiveSessionID", UUID().uuidString), ("surfaceID", UUID().uuidString),
        ("authorizationEpoch", 2), ("surfaceRevision", 2),
        ("coordinateSpaceRevision", 2), ("encodedWidth", 1279), ("encodedHeight", 719),
        ("logicalWidthPoints", 1279), ("logicalHeightPoints", 719), ("rotation", 90),
    ]
    for (field, value) in changes {
        var object = original; object[field] = value
        let changed = try JSONDecoder().decode(AdaptiveSurfaceDescriptor.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(throws: LocalInteractiveNativeBackendErrorV1.bindingMismatch) {
            try MacInteractiveNativeCaptureGeometryV1.projectSelectedSurface(
                scope: scope, descriptor: changed, bounds: bounds, backingScale: 2, activationTarget: target)
        }
    }
}

@available(macOS 26.0, *)
@Test func nativeSelectedCaptureRejectsInvalidOwnerBoundsAndScale() throws {
    let scope = try NativeBackendWorldV1().scope
    let descriptor = try selectedNativeDescriptor(scope: scope)
    let bounds = CGRect(x: 0, y: 0, width: 1280, height: 720)
    let targets: [ScreenCaptureKitLocalActivationTargetV0?] = [nil,
        .application(processID: 123, bundleIdentifier: "test.selected"),
        .window(windowID: 0, processID: 123, bundleIdentifier: "test.selected", globalBounds: bounds),
        .window(windowID: 42, processID: 0, bundleIdentifier: "test.selected", globalBounds: bounds),
        .window(windowID: 42, processID: 123, bundleIdentifier: "", globalBounds: bounds),
        .window(windowID: 42, processID: 123, bundleIdentifier: "test.selected", globalBounds: bounds.offsetBy(dx: 1, dy: 0))]
    for target in targets {
        #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
            try MacInteractiveNativeCaptureGeometryV1.projectSelectedSurface(
                scope: scope, descriptor: descriptor, bounds: bounds, backingScale: 2, activationTarget: target)
        }
    }
    let target = ScreenCaptureKitLocalActivationTargetV0.window(
        windowID: 42, processID: 123, bundleIdentifier: "test.selected", globalBounds: bounds)
    for scale in [0, -1, Double.nan, Double.infinity] {
        #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
            try MacInteractiveNativeCaptureGeometryV1.projectSelectedSurface(
                scope: scope, descriptor: descriptor, bounds: bounds, backingScale: scale, activationTarget: target)
        }
    }
    #expect(throws: InteractiveNativeVideoContentGeometryErrorV0.invalidDimensions) {
        try MacInteractiveNativeCaptureGeometryV1.projectSelectedSurface(
            scope: scope, descriptor: descriptor, bounds: bounds, backingScale: 30, activationTarget: target)
    }
    for changedBounds in [CGRect(x: 0, y: 0, width: 1281, height: 720),
        CGRect(x: 0, y: 0, width: 1280, height: 721),
        CGRect(x: CGFloat.infinity, y: 0, width: 1280, height: 720)] {
        let changedTarget = ScreenCaptureKitLocalActivationTargetV0.window(
            windowID: 42, processID: 123, bundleIdentifier: "test.selected", globalBounds: changedBounds)
        #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
            try MacInteractiveNativeCaptureGeometryV1.projectSelectedSurface(
                scope: scope, descriptor: descriptor, bounds: changedBounds, backingScale: 2, activationTarget: changedTarget)
        }
    }
    for kind in [InteractiveSurfaceKind.application, .desktop] {
        let changed = try selectedNativeDescriptor(scope: scope, kind: kind)
        #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
            try MacInteractiveNativeCaptureGeometryV1.projectSelectedSurface(
                scope: scope, descriptor: changed, bounds: bounds, backingScale: 2, activationTarget: target)
        }
    }
}

@available(macOS 26.0, *)
@Test func nativeSelectedCaptureRequiresCommittedSelection() async throws {
    let owner = MacInteractiveSurfaceTargetOwnerV1()
    let scope = try NativeBackendWorldV1().scope
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
        try await owner.nativeCaptureTarget(scope: scope, nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
    }
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
        try await owner.nativeCaptureSurface(scope: scope, nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
    }
    await owner.invalidate()
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
        try await owner.nativeCaptureSurface(scope: scope, nowMonotonicNanoseconds: UInt64.max)
    }
}

@available(macOS 26.0, *)
@Test func nativeSelectedPrivateContextMatchesIndexedFixture() throws {
    var root = URL(fileURLWithPath: #filePath)
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent()
        #expect(parent != root)
        root = parent
    }
    let fixtureURL = root.appendingPathComponent("spec/fixtures/native-selected-capture-context-v0.1.json")
    let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
    let expected = try #require(fixture["windowContext"] as? [String: Any])
    let geometry = try InteractiveNativeVideoContentGeometryV0(encodedWidth: 640, encodedHeight: 360,
        capturePixelWidth: 640, capturePixelHeight: 360, logicalWidthPoints: 320, logicalHeightPoints: 180)
    let data = try MacManagedNativeSelectedCaptureV1.encodeContext(
        operationID: UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!, kind: "window",
        physicalDisplayID: 1, windowID: 42, processID: 123, bundleIdentifier: "test.selected",
        processLaunchMilliseconds: 1000, bounds: CGRect(x: -320, y: 40, width: 320, height: 180),
        backingScale: 2, geometry: geometry, expiryNanoseconds: 31_000_000_000)
    #expect(data == (try JSONSerialization.data(withJSONObject: expected,
        options: [.sortedKeys, .withoutEscapingSlashes])))
}

@available(macOS 26.0, *)
@Test func nativeBackendLogicalScopeRequiresCanonicalGeometryAndExactRuntimeMatch() async throws {
    let world = try NativeBackendWorldV1()
    let encoded = try LocalInteractiveLeaseWireCodecV1.encodeNativeBackendCommand(
        world.command(.prepare, backendID: UUID(), operationID: UUID()))
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let scopeObject = try #require(object["scope"] as? [String: Any])
    for field in ["logicalWidthPoints", "logicalHeightPoints", "rotation"] {
        var changed = object, scope = scopeObject
        scope.removeValue(forKey: field); changed["scope"] = scope
        let bytes = try JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: LocalInteractiveLeaseWireCodecErrorV1.invalidPayload) {
            try LocalInteractiveLeaseWireCodecV1.decodeNativeBackendCommand(bytes)
        }
    }
    for (field, value) in [("logicalWidthPoints", 0), ("logicalHeightPoints", -1),
                           ("logicalWidthPoints", 4_294_967_296), ("rotation", 45)] {
        var changed = object, scope = scopeObject
        scope[field] = value; changed["scope"] = scope
        let bytes = try JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: (any Error).self) { try LocalInteractiveLeaseWireCodecV1.decodeNativeBackendCommand(bytes) }
    }
    for (width, height, rotation) in [(UInt32(1279), UInt32(720), SurfaceRotation.degrees0),
                                     (1280, 719, .degrees0), (1280, 720, .degrees90)] {
        let scope = try LocalInteractiveNativeBackendScopeV1(binding: world.scope.binding(), surface: world.scope.surface(),
            logicalWidthPoints: width, logicalHeightPoints: height, rotation: rotation,
            selectedDisplayID: world.scope.selectedDisplayID, menuAppGeneration: world.scope.menuAppGeneration,
            menuAppRevision: world.scope.menuAppRevision, sessionPublicKeyX963: world.scope.sessionPublicKeyX963())
        let command = try LocalInteractiveNativeBackendCommandV1(commandID: UUID(), backendID: UUID(), operationID: UUID(),
            operation: .prepare, scope: scope, clientCertificateDER: Data([1]))
        await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) { try await world.owner.handle(command) }
    }
    #expect(await world.spy.created.isEmpty)
    #expect(await world.reader.inputPaused == false)
    await world.owner.retire()
}

@available(macOS 26.0, *)
@Test func nativeBackendMissingCaptureModeCreatesNoBackend() async throws {
    let world = try NativeBackendWorldV1()
    world.geometryReader.change(width: 2560, height: 1440, available: false)
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
        try await world.owner.handle(world.command(.prepare, backendID: UUID(), operationID: UUID()))
    }
    #expect(await world.spy.created.isEmpty)
    #expect(await world.reader.inputPaused)
    await world.owner.retire()
}

@available(macOS 26.0, *)
@Test func nativeBackendCaptureModeChangeDuringFactoryRetiresLateBackendWithoutPreparingCredentials() async throws {
    let gate = NativeBackendGateV1(), world = try NativeBackendWorldV1(factoryGate: gate)
    let preparing = Task { try await world.owner.handle(world.command(.prepare, backendID: UUID(), operationID: UUID())) }
    await waitNativeGateV1(gate)
    let first = try #require(await world.spy.created.first)
    world.geometryReader.change(width: 2562, height: 1440)
    let deadline = ContinuousClock.now + .seconds(2)
    while first.1.isCurrent, ContinuousClock.now < deadline { await Task.yield() }
    #expect(!first.1.isCurrent)
    await gate.release()
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) { try await preparing.value }
    #expect(await first.0.preparations == 0)
    #expect(await first.0.retirements == 1)
    await world.owner.retire()
}

@available(macOS 26.0, *)
@Test func nativeBackendCaptureModeLossWatchdogRevokesActivePermitAndDrains() async throws {
    let world = try NativeBackendWorldV1(), backendID = UUID(), operationID = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: backendID, operationID: operationID))
    _ = try await world.owner.handle(world.command(.activate, backendID: backendID, operationID: operationID))
    let first = try #require(await world.spy.created.first)
    world.geometryReader.change(width: 2560, height: 1440, available: false)
    let deadline = ContinuousClock.now + .seconds(2)
    while await first.0.retirements == 0, ContinuousClock.now < deadline { await Task.yield() }
    #expect(!first.1.isCurrent)
    #expect(await first.0.retirements == 1)
    #expect(await first.0.activations == 1)
    await world.owner.retire()
}

@available(macOS 26.0, *)
@Test func retiredHealthIsBoundToOldScopeAndCannotRetireFreshBackend() async throws {
    let world = try NativeBackendWorldV1(), oldID = UUID(), oldOperation = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: oldID, operationID: oldOperation))
    _ = try await world.owner.handle(world.command(.activate, backendID: oldID, operationID: oldOperation))
    world.geometryReader.change(width: 2560, height: 1440, available: false)
    let retired = try await world.owner.handle(world.command(.health, backendID: oldID, operationID: oldOperation))
    #expect(retired.active == false)
    #expect(retired.captureEvidence == nil && retired.portBase == nil && retired.hostCertificateDERBase64 == nil)
    let old = try #require(await world.spy.created.first)
    #expect(await old.0.retirements == 1)
    world.geometryReader.change(width: 2560, height: 1440)
    let freshID = UUID(), freshOperation = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: freshID, operationID: freshOperation))
    _ = try await world.owner.handle(world.command(.activate, backendID: freshID, operationID: freshOperation))
    #expect(try await world.owner.handle(world.command(.health, backendID: oldID, operationID: oldOperation)).active == false)
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
        try await world.owner.handle(world.command(.health, backendID: oldID, operationID: UUID()))
    }
    #expect(try await world.owner.handle(world.command(.health, backendID: freshID, operationID: freshOperation)).active == true)
    let fresh = try #require(await world.spy.created.last)
    #expect(fresh.1.isCurrent)
    #expect(await fresh.0.retirements == 0)
    await world.owner.retire()
}

@available(macOS 26.0, *)
@Test func healthDuringRetirementWaitsForNativeDrainBeforeInactiveReceipt() async throws {
    let gate = NativeBackendGateV1(), id = UUID(), operation = UUID()
    let world = try NativeBackendWorldV1(retireGate: gate)
    _ = try await world.owner.handle(world.command(.prepare, backendID: id, operationID: operation))
    _ = try await world.owner.handle(world.command(.activate, backendID: id, operationID: operation))
    let retirement = Task { await world.owner.retire() }
    await waitNativeGateV1(gate)
    let receipt = Task { try await world.owner.handle(world.command(.health, backendID: id, operationID: operation)) }
    await gate.release(); await retirement.value
    #expect(try await receipt.value.active == false)
}

@available(macOS 26.0, *)
@Test func inFlightHealthJoinsPublishedWatchdogRetirement() async throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent(); try #require(parent != root); root = parent
    }
    let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
        root.appendingPathComponent("spec/fixtures/local-xpc-native-backend-v0.1.json"))) as? [String: Any])
    #expect((fixture["retirementPublicationCases"] as? [String])?.contains(
        "in-flight-health-loses-capture-during-watchdog-retirement-returns-inactive") == true)
    for _ in 0..<32 {
        let evidenceGate = NativeBackendGateV1(), retireGate = NativeBackendGateV1()
        let world = try NativeBackendWorldV1(retireGate: retireGate), id = UUID(), operation = UUID()
        _ = try await world.owner.handle(world.command(.prepare, backendID: id, operationID: operation))
        _ = try await world.owner.handle(world.command(.activate, backendID: id, operationID: operation))
        let pair = try #require(await world.spy.created.first)
        await pair.0.suspendNextEvidenceRead(evidenceGate)
        let health = Task { try await world.owner.handle(world.command(.health, backendID: id, operationID: operation)) }
        await waitNativeGateV1(evidenceGate)
        world.geometryReader.change(width: 2560, height: 1440, available: false)
        let deadline = ContinuousClock.now + .seconds(2)
        while pair.1.isCurrent, ContinuousClock.now < deadline { await Task.yield() }
        #expect(!pair.1.isCurrent)
        await evidenceGate.release()
        await waitNativeGateV1(retireGate)
        await retireGate.release()
        // Await this health reader first: the watchdog is a separate drain
        // waiter and must not be required to publish cleanup after it resumes.
        do {
            let receipt = try await health.value
            #expect(receipt.active == false && receipt.captureEvidence == nil)
        } catch { Issue.record("Exact health escaped retirement as \(String(reflecting: type(of: error)))") }
        world.geometryReader.change(width: 2560, height: 1440)
        let freshID = UUID(), freshOperation = UUID()
        do {
            _ = try await world.owner.handle(world.command(.prepare, backendID: freshID, operationID: freshOperation))
        } catch { Issue.record("Health returned before retired ownership was published") }
        await world.owner.retire()
    }
}

private func backendSampleEvidenceV1(operationID: UUID) throws -> InteractiveNativeVideoCaptureEvidenceV0 {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent(); guard parent != root else { throw CocoaError(.fileNoSuchFile) }; root = parent
    }
    let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/valid/native-backend-capture-evidence.json"))) as? [String: Any])
    var record = try #require(fixture["record"] as? [String: Any])
    record["operationID"] = operationID.uuidString
    record["monotonicNanoseconds"] = DispatchTime.now().uptimeNanoseconds
    record["encodedWidth"] = 1280; record["encodedHeight"] = 720
    record["formatWidth"] = 1280; record["formatHeight"] = 720
    record["cleanWidth"] = 1280; record["cleanHeight"] = 720
    record["capturePixelWidth"] = 2560; record["capturePixelHeight"] = 1440
    return try .decode(JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes]))
}

@available(macOS 26.0, *)
@Test func nativeBackendActualSampleHealthReceiptRetainsInputPauseAndExactCorrelation() async throws {
    let world = try NativeBackendWorldV1(), backendID = UUID(), operationID = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: backendID, operationID: operationID))
    _ = try await world.owner.handle(world.command(.activate, backendID: backendID, operationID: operationID))
    let first = try #require(await world.spy.created.first)
    let evidence = try backendSampleEvidenceV1(operationID: operationID)
    await first.0.setEvidence(evidence)
    let command = try world.command(.health, backendID: backendID, operationID: operationID)
    let receipt = try await world.owner.handle(command)
    #expect(receipt.captureEvidence == evidence)
    try receipt.validate(against: command)
    let bytes = try LocalInteractiveLeaseWireCodecV1.encodeNativeBackendReceipt(receipt)
    #expect(try LocalInteractiveLeaseWireCodecV1.decodeNativeBackendReceipt(bytes) == receipt)
    #expect(await world.reader.inputPaused)
    #expect(throws: LocalInteractiveNativeBackendErrorV1.bindingMismatch) {
        try LocalInteractiveNativeBackendReceiptV1(command: world.command(.activate, backendID: backendID,
            operationID: operationID), portBase: 58989, captureEvidence: evidence)
    }
    await world.owner.retire()
}

@available(macOS 26.0, *)
@Test func nativeBackendWrongSampleOperationRevokesAndDrainsBeforeHealthReceipt() async throws {
    let world = try NativeBackendWorldV1(), backendID = UUID(), operationID = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: backendID, operationID: operationID))
    _ = try await world.owner.handle(world.command(.activate, backendID: backendID, operationID: operationID))
    let first = try #require(await world.spy.created.first)
    await first.0.setEvidence(try backendSampleEvidenceV1(operationID: UUID()))
    await #expect(throws: InteractiveNativeVideoCaptureEvidenceErrorV0.bindingMismatch) {
        try await world.owner.handle(world.command(.health, backendID: backendID, operationID: operationID))
    }
    #expect(!first.1.isCurrent)
    #expect(await first.0.retirements == 1)
    #expect(await world.reader.inputPaused)
    await world.owner.retire()
}

private func waitNativeGateV1(_ gate: NativeBackendGateV1) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await gate.entered), ContinuousClock.now < deadline { await Task.yield() }
    #expect(await gate.entered)
}

@available(macOS 26.0, *)
@Test func nativeBackendPrepareStaysInertAndReceiptsAreExactAndBounded() async throws {
    let world = try NativeBackendWorldV1(), backendID = UUID(), operationID = UUID()
    let prepare = try world.command(.prepare, backendID: backendID, operationID: operationID)
    let encoded = try LocalInteractiveLeaseWireCodecV1.encodeNativeBackendCommand(prepare)
    #expect(encoded.count < 4096)
    #expect(try LocalInteractiveLeaseWireCodecV1.decodeNativeBackendCommand(encoded) == prepare)
    let prepared = try await world.owner.handle(prepare)
    try prepared.validate(against: prepare)
    let wireReply = try LocalInteractiveLeaseWireCodecV1.encodeNativeBackendReceipt(prepared)
    #expect(try LocalInteractiveLeaseWireCodecV1.decodeNativeBackendReceipt(wireReply) == prepared)
    let first = try #require(await world.spy.created.first)
    #expect(await first.0.preparations == 1)
    #expect(await first.0.activations == 0)
    let activate = try world.command(.activate, backendID: backendID, operationID: operationID)
    #expect(throws: LocalInteractiveNativeBackendErrorV1.bindingMismatch) { try prepared.validate(against: activate) }
    let started = try await world.owner.handle(activate)
    #expect(started.portBase == 58989)
    #expect(try await world.owner.handle(world.command(.health, backendID: backendID, operationID: operationID)).active == true)
    let oversized = try LocalInteractiveNativeBackendCommandV1(commandID: UUID(), backendID: UUID(), operationID: UUID(),
        operation: .prepare, scope: world.scope, clientCertificateDER: Data(repeating: 1, count: 4096))
    #expect(throws: LocalInteractiveLeaseWireCodecErrorV1.payloadTooLarge) { try LocalInteractiveLeaseWireCodecV1.encodeNativeBackendCommand(oversized) }
    _ = try await world.owner.handle(world.command(.retire, backendID: backendID, operationID: operationID))
    #expect(!first.1.isCurrent)
    #expect(await first.0.retirements == 1)
}

@available(macOS 26.0, *)
@Test func nativeBackendStopJoinsLateFactoryAndStaleRetireCannotTouchReplacement() async throws {
    let gate = NativeBackendGateV1()
    let world = try NativeBackendWorldV1(factoryGate: gate), oldID = UUID(), oldOperation = UUID()
    let preparing = Task { try await world.owner.handle(world.command(.prepare, backendID: oldID, operationID: oldOperation)) }
    await waitNativeGateV1(gate)
    let first = try #require(await world.spy.created.first)
    let stopping = Task { await world.owner.retire() }
    let deadline = ContinuousClock.now + .seconds(2)
    while first.1.isCurrent, ContinuousClock.now < deadline { await Task.yield() }
    #expect(!first.1.isCurrent)
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
        try await world.owner.handle(world.command(.prepare, backendID: UUID(), operationID: UUID()))
    }
    await gate.release(); await stopping.value
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) { try await preparing.value }
    #expect(await first.0.preparations == 0)
    #expect(await first.0.retirements == 1)
    let newID = UUID(), newOperation = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: newID, operationID: newOperation))
    _ = try await world.owner.handle(world.command(.activate, backendID: newID, operationID: newOperation))
    _ = try await world.owner.handle(world.command(.retire, backendID: oldID, operationID: oldOperation))
    #expect(try await world.owner.handle(world.command(.health, backendID: newID, operationID: newOperation)).active == true)
    await world.owner.retire()
}

@available(macOS 26.0, *)
@Test func nativeBackendRevocationFencesPermitWhileRetirementIsPending() async throws {
    let gate = NativeBackendGateV1()
    let world = try NativeBackendWorldV1(retireGate: gate), backendID = UUID(), operationID = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: backendID, operationID: operationID))
    _ = try await world.owner.handle(world.command(.activate, backendID: backendID, operationID: operationID))
    let first = try #require(await world.spy.created.first)
    await world.reader.revoke()
    await waitNativeGateV1(gate)
    #expect(!first.1.isCurrent)
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
        try await world.owner.handle(world.command(.prepare, backendID: UUID(), operationID: UUID()))
    }
    await gate.release(); await world.owner.retire()
    #expect(await first.0.retirements == 1)
}

@available(macOS 26.0, *)
@Test func nativeBackendWrongScopeAndCrossOperationMaterialHaveNoEffects() async throws {
    let world = try NativeBackendWorldV1(), backendID = UUID(), operationID = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: backendID, operationID: operationID))
    let first = try #require(await world.spy.created.first)
    let wrongScope = try LocalInteractiveNativeBackendScopeV1(binding: world.scope.binding(), surface: world.scope.surface(),
        logicalWidthPoints: world.scope.logicalWidthPoints, logicalHeightPoints: world.scope.logicalHeightPoints, rotation: world.scope.rotation,
        selectedDisplayID: UUID(), menuAppGeneration: world.scope.menuAppGeneration, menuAppRevision: world.scope.menuAppRevision,
        sessionPublicKeyX963: world.scope.sessionPublicKeyX963())
    let activate = try LocalInteractiveNativeBackendCommandV1(commandID: UUID(), backendID: backendID, operationID: operationID,
        operation: .activate, scope: wrongScope)
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) { try await world.owner.handle(activate) }
    #expect(await first.0.activations == 0)
    #expect(await first.0.retirements == 0)
    #expect(throws: LocalInteractiveNativeBackendErrorV1.invalidMaterial) {
        try LocalInteractiveNativeBackendCommandV1(commandID: UUID(), backendID: backendID, operationID: operationID,
            operation: .activate, scope: world.scope, clientCertificateDER: Data([1]))
    }
    await world.owner.retire()
}
private final class NativeInputBatchCounterV1: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func post() { lock.withLock { value += 1 } }
    func count() -> Int { lock.withLock { value } }
}
@available(macOS 26.0, *)
@Test func nativeBackendAtomicInputPermitRemeasuresCaptureAndFencesExpiryAndRetirement() async throws {
    for loss in ["geometry", "missing", "retirement"] {
        let world = try NativeBackendWorldV1(), backendID = UUID(), operationID = UUID(), posted = NativeInputBatchCounterV1()
        _ = try await world.owner.handle(world.command(.prepare, backendID: backendID, operationID: operationID))
        _ = try await world.owner.handle(world.command(.activate, backendID: backendID, operationID: operationID))
        let permit = try #require(await world.spy.created.first).1
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        try permit.withCurrentInput(beforeDeadlineNanoseconds: deadline) { posted.post() }
        #expect(posted.count() == 1)
        #expect(throws: (any Error).self) {
            try permit.withCurrentInput(beforeDeadlineNanoseconds: 0) { posted.post() }
        }
        if loss == "geometry" { world.geometryReader.change(width: 1920, height: 1080) }
        else if loss == "missing" { world.geometryReader.change(width: 2560, height: 1440, available: false) }
        else { await world.owner.retire() }
        #expect(throws: (any Error).self) {
            try permit.withCurrentInput(beforeDeadlineNanoseconds: deadline) { posted.post() }
        }
        #expect(posted.count() == 1)
        #expect(!permit.isCurrent)
        world.geometryReader.change(width: 2560, height: 1440)
        #expect(throws: (any Error).self) {
            try permit.withCurrentInput(beforeDeadlineNanoseconds: deadline) { posted.post() }
        }
        await world.owner.retire()
    }
}

@available(macOS 26.0, *)
@Test func nativeBackendUnsupportedInputExecutorNeverInvokesBatch() async throws {
    let backend = NativeBackendProbeV1(prepareGate: nil, retireGate: nil), operationID = UUID()
    _ = try await backend.activate(operationID: operationID)
    let posted = NativeInputBatchCounterV1()
    await #expect(throws: InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable) {
        try await backend.postInputBatch(operationID: operationID,
            beforeDeadlineNanoseconds: DispatchTime.now().uptimeNanoseconds + 5_000_000_000) { posted.post() }
    }
    #expect(posted.count() == 0)
    await backend.retire(operationID: operationID)
}

@available(macOS 26.0, *)
private func nativePresentCommandV1(_ world: NativeBackendWorldV1, backendID: UUID, operationID: UUID,
    generation: Int64 = 1, id: UUID) throws -> LocalInteractiveNativeBackendCommandV1 {
    try .init(commandID: UUID(), backendID: backendID, operationID: operationID, operation: .present,
        scope: world.scope, nativeGeneration: generation, presentationID: id)
}
@available(macOS 26.0, *)
@Test func nativeBackendPresentationInstallsOnceAndCannotChangeGenerationOrReviveRevocation() async throws {
    for loss in ["generation", "challenge", "revoked"] {
        let world = try NativeBackendWorldV1(supportsInput: true), backendID = UUID(), operationID = UUID(), id = UUID()
        _ = try await world.owner.handle(world.command(.prepare, backendID: backendID, operationID: operationID))
        _ = try await world.owner.handle(world.command(.activate, backendID: backendID, operationID: operationID))
        let backend = try #require(await world.spy.created.first).0
        await backend.setEvidence(try backendSampleEvidenceV1(operationID: operationID))
        let command = try nativePresentCommandV1(world, backendID: backendID, operationID: operationID, id: id)
        let reply = try await world.owner.handle(command)
        #expect(reply.inputAdmitted == true && reply.active == true)
        #expect(reply.nativeGeneration == 1 && reply.presentationID == id)
        let decoded = try LocalInteractiveLeaseWireCodecV1.decodeNativeBackendReceipt(LocalInteractiveLeaseWireCodecV1.encodeNativeBackendReceipt(reply))
        try decoded.validate(against: command)
        _ = try await world.owner.handle(nativePresentCommandV1(world, backendID: backendID, operationID: operationID, id: id))
        #expect(await world.reader.installations == 1)
        let installed = try #require(await world.reader.installedAuthorization)
        if loss == "revoked" { installed.revoke() }
        await #expect(throws: (any Error).self) {
            _ = try await world.owner.handle(nativePresentCommandV1(world, backendID: backendID, operationID: operationID,
                generation: loss == "generation" ? 2 : 1, id: loss == "challenge" ? UUID() : id))
        }
        #expect(installed.isRevoked)
        #expect(await backend.retirements == 1)
        await world.owner.retire()
    }
}
@available(macOS 26.0, *)
@Test func nativeBackendPresentationRequiresActiveSupportedBackendAndActualSample() async throws {
    for loss in ["inactive", "unsupported", "sample"] {
        let world = try NativeBackendWorldV1(supportsInput: loss != "unsupported"), backendID = UUID(), operationID = UUID()
        _ = try await world.owner.handle(world.command(.prepare, backendID: backendID, operationID: operationID))
        if loss != "inactive" { _ = try await world.owner.handle(world.command(.activate, backendID: backendID, operationID: operationID)) }
        if loss != "sample" {
            let backend = try #require(await world.spy.created.first).0
            await backend.setEvidence(try backendSampleEvidenceV1(operationID: operationID))
        }
        await #expect(throws: (any Error).self) {
            _ = try await world.owner.handle(nativePresentCommandV1(world, backendID: backendID, operationID: operationID, id: UUID()))
        }
        #expect(await world.reader.installations == 0)
        await world.owner.retire()
    }
}
@available(macOS 26.0, *)
@Test func nativeBackendStopDuringPresentationRevokesLateInstalledPrimitive() async throws {
    let gate = NativeBackendGateV1(), world = try NativeBackendWorldV1(supportsInput: true, installGate: gate)
    let backendID = UUID(), operationID = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: backendID, operationID: operationID))
    _ = try await world.owner.handle(world.command(.activate, backendID: backendID, operationID: operationID))
    let backend = try #require(await world.spy.created.first).0
    await backend.setEvidence(try backendSampleEvidenceV1(operationID: operationID))
    let work = Task { try await world.owner.handle(nativePresentCommandV1(world, backendID: backendID, operationID: operationID, id: UUID())) }
    await waitNativeGateV1(gate)
    let stopping = Task { await world.owner.retire() }
    let permit = try #require(await world.spy.created.first).1
    while permit.isCurrent { await Task.yield() }
    await gate.release()
    await stopping.value
    await #expect(throws: (any Error).self) { _ = try await work.value }
    #expect(await world.reader.installedAuthorization?.isRevoked == true)
    #expect(await backend.retirements == 1)
}

@available(macOS 26.0, *)
@Test func nativeBackendPresentationWireFieldsAreClosedAndReceiptsCannotChangeGeneration() async throws {
    let world = try NativeBackendWorldV1(), backendID = UUID(), operationID = UUID(), id = UUID()
    #expect(throws: (any Error).self) {
        _ = try LocalInteractiveNativeBackendCommandV1(commandID: UUID(), backendID: backendID, operationID: operationID,
            operation: .present, scope: world.scope)
    }
    #expect(throws: (any Error).self) {
        _ = try LocalInteractiveNativeBackendCommandV1(commandID: UUID(), backendID: backendID, operationID: operationID,
            operation: .health, scope: world.scope, nativeGeneration: 1, presentationID: id)
    }
    let command = try nativePresentCommandV1(world, backendID: backendID, operationID: operationID, id: id)
    let evidence = try backendSampleEvidenceV1(operationID: operationID)
    #expect(throws: (any Error).self) {
        _ = try LocalInteractiveNativeBackendReceiptV1(command: command, active: true, captureEvidence: evidence, inputAdmitted: false)
    }
    let receipt = try LocalInteractiveNativeBackendReceiptV1(command: command, active: true, captureEvidence: evidence, inputAdmitted: true)
    var record = try #require(JSONSerialization.jsonObject(with: LocalInteractiveLeaseWireCodecV1.encodeNativeBackendReceipt(receipt)) as? [String: Any])
    record["nativeGeneration"] = 2
    let different = try LocalInteractiveLeaseWireCodecV1.decodeNativeBackendReceipt(JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
    #expect(throws: (any Error).self) { try different.validate(against: command) }
}

private enum ManagedArtifactRejectionV1: Error { case rejected, timeout }

@available(macOS 26.0, *)
@Test(.enabled(if: ProcessInfo.processInfo.environment["MACCOMPANION_TEST_OPENSSL"] != nil))
@MainActor
func managedEnrollmentUsesExplicitConfigurationWithoutDeveloperPrefix() async throws {
    let cli = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["MACCOMPANION_TEST_OPENSSL"]))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("maccompanion-enrollment-config-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    let configuration = root.appendingPathComponent("openssl.cnf")
    try Data("# Explicit certificate options only.\n".utf8).write(to: configuration)
    let key = root.appendingPathComponent("client-key.pem"), certificate = root.appendingPathComponent("client.pem")
    let der = root.appendingPathComponent("client.der")
    func run(_ arguments: [String]) throws {
        let child = Process()
        child.executableURL = cli; child.arguments = arguments
        child.environment = ["OPENSSL_CONF": root.appendingPathComponent("absent-developer-config").path]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        try child.run(); child.waitUntilExit()
        try #require(child.terminationStatus == 0)
    }
    try run(["req", "-config", configuration.path, "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "1",
             "-subj", "/CN=Native enrollment test", "-addext", "extendedKeyUsage=clientAuth", "-keyout", key.path, "-out", certificate.path])
    try run(["x509", "-in", certificate.path, "-outform", "DER", "-out", der.path])
    let world = try NativeBackendWorldV1()
    let authority = try InteractiveNativeVideoAuthorityV0(binding: world.scope.binding(), surface: world.scope.surface(),
                                                         sessionPublicKeyX963: world.scope.sessionPublicKeyX963())
    let geometry = try world.geometryReader.read(world.scope)
    // Preparation exercises the real relocated CLI without starting Sunshine.
    for config in [configuration, root.appendingPathComponent("missing-selected-config")] {
        let backend = try MacManagedSunshineEnrollmentBackendV1(root: root, sunshine: cli, supervisor: cli, openssl: cli,
            opensslConfiguration: config, port: 58989, approvedDesktopDisplayID: 1234,
            approvedCaptureGeometry: geometry, currentControl: { true })
        let operationID = UUID()
        do {
            let host = try await backend.prepare(operationID: operationID, authority: authority, clientCertificateDER: Data(contentsOf: der))
            #expect(config == configuration)
            #expect(!host.isEmpty)
        } catch let error as MacManagedSunshineEnrollmentBackendV1.Failure {
            #expect(config != configuration)
            #expect(String(describing: error) == "invalidCertificate")
        } catch {
            await backend.retire(operationID: operationID)
            throw error
        }
        await backend.retire(operationID: operationID)
    }
}

@available(macOS 26.0, *)
@Test func managedFactoryRejectsArtifactsBeforeEnrollmentOrChildConstruction() async throws {
    let world = try NativeBackendWorldV1()
    _ = try await world.owner.handle(world.command(.prepare, backendID: UUID(), operationID: UUID()))
    let permit = try #require(await world.spy.created.first?.1)
    let geometry = try world.geometryReader.read(world.scope)
    let missing = URL(fileURLWithPath: "/private/tmp/maccompanion-absent-" + UUID().uuidString)
    let factory = MacManagedSunshineBackendFactoryV1.make(root: missing, sunshine: missing,
        supervisor: missing, openssl: missing, port: 58989,
        validateArtifacts: { throw ManagedArtifactRejectionV1.rejected })
    await #expect(throws: ManagedArtifactRejectionV1.rejected) {
        _ = try await factory(1234, geometry, permit, nil)
    }
    #expect(!FileManager.default.fileExists(atPath: missing.path))
    await world.owner.retire()
    // Revoked permits reject before consulting even the artifact validator.
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
        _ = try await factory(1234, geometry, permit, nil)
    }
}

@available(macOS 26.0, *)
@Test func managedFactoryRejectsControlRevokedDuringArtifactValidation() async throws {
    let world = try NativeBackendWorldV1()
    _ = try await world.owner.handle(world.command(.prepare, backendID: UUID(), operationID: UUID()))
    let permit = try #require(await world.spy.created.first?.1)
    let geometry = try world.geometryReader.read(world.scope)
    let missing = URL(fileURLWithPath: "/private/tmp/maccompanion-absent-" + UUID().uuidString)
    let owner = world.owner
    let factory = MacManagedSunshineBackendFactoryV1.make(root: missing, sunshine: missing,
        supervisor: missing, openssl: missing, port: 58989, validateArtifacts: {
            let done = DispatchSemaphore(value: 0)
            Task.detached { await owner.retire(); done.signal() }
            guard done.wait(timeout: .now() + 5) == .success else { throw ManagedArtifactRejectionV1.timeout }
        })
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
        _ = try await factory(1234, geometry, permit, nil)
    }
    #expect(!permit.isCurrent)
    #expect(!FileManager.default.fileExists(atPath: missing.path))
    await world.owner.retire()
}
@available(macOS 26.0, *)
@Test func retainedMenuReplacementKeepsBackendAndFencesOldInputAndRetirement() async throws {
    let world = try NativeBackendWorldV1(supportsInput: true, continuity: true)
    let oldID = UUID(), oldOperation = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: oldID, operationID: oldOperation))
    _ = try await world.owner.handle(world.command(.activate, backendID: oldID, operationID: oldOperation))
    let (backend, permit) = try #require(await world.spy.created.first)
    await backend.setEvidence(try backendSampleEvidenceV1(operationID: oldOperation))
    _ = try await world.owner.handle(nativePresentCommandV1(world, backendID: oldID, operationID: oldOperation, id: UUID()))
    let oldAuthorization = try #require(await world.reader.installedAuthorization)
    #expect(try await world.owner.handle(world.command(.health, backendID: oldID, operationID: oldOperation)).streamContinuity == true)
    #expect(try await world.owner.handle(world.command(.retain, backendID: oldID, operationID: oldOperation)).streamRetained == true)
    #expect(oldAuthorization.isRevoked)
    #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) {
        try permit.withCurrentInput(beforeDeadlineNanoseconds: DispatchTime.now().uptimeNanoseconds + 1_000_000_000) { Issue.record("Old input escaped pause") }
    }
    await world.owner.prepareSurfaceChange()
    #expect(await backend.retirements == 0)
    let surface = try InteractiveNativeVideoSurfaceV0(surfaceID: UUID(), surfaceRevision: 2, coordinateSpaceRevision: 2, encodedWidth: 1280, encodedHeight: 720)
    let scope = try LocalInteractiveNativeBackendScopeV1(binding: world.scope.binding(), surface: surface,
        logicalWidthPoints: 1280, logicalHeightPoints: 720, rotation: .degrees0, selectedDisplayID: world.scope.selectedDisplayID,
        menuAppGeneration: world.scope.menuAppGeneration, menuAppRevision: 2, sessionPublicKeyX963: world.scope.sessionPublicKeyX963())
    try await world.reader.rebase(scope)
    let id = UUID(), operation = UUID()
    _ = try await world.owner.handle(.init(commandID: UUID(), backendID: id, operationID: operation, operation: .prepareReplacement,
        scope: scope, clientCertificateDER: Data([4,5,6]), previousBackendID: oldID, previousOperationID: oldOperation))
    _ = try await world.owner.handle(world.command(.retire, backendID: oldID, operationID: oldOperation))
    #expect(await world.spy.created.count == 1)
    #expect(await backend.retirements == 0)
    _ = try await world.owner.handle(.init(commandID: UUID(), backendID: id, operationID: operation, operation: .activate, scope: scope))
    await backend.setEvidence(try backendSampleEvidenceV1(operationID: operation))
    let receipt = try await world.owner.handle(.init(commandID: UUID(), backendID: id, operationID: operation, operation: .present,
        scope: scope, nativeGeneration: 2, presentationID: UUID()))
    #expect(receipt.inputAdmitted == true)
    #expect(await world.reader.installations == 2)
    try permit.withCurrentInput(beforeDeadlineNanoseconds: DispatchTime.now().uptimeNanoseconds + 1_000_000_000) {}
    await world.owner.retire()
    #expect(await backend.retirements == 1 && !permit.isCurrent)
}

@available(macOS 26.0, *)
private func requireBackendWatcherFixtureCaseV1(_ name: String) throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent(); try #require(parent != root); root = parent
    }
    let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
        root.appendingPathComponent("spec/fixtures/native-stream-continuity-v0.1.json"))) as? [String: Any])
    let cases = try #require(fixture["backendWatcherLifecycleCases"] as? [String])
    try #require(cases.contains(name))
}

@available(macOS 26.0, *)
@Test func staleRetainingWatcherCannotRetireCompletedRetention() async throws {
    try requireBackendWatcherFixtureCaseV1("stale-retaining-check-cannot-retire-completed-retention")
    let retainGate = NativeBackendGateV1(), watcherGate = NativeBackendGateV1()
    let world = try NativeBackendWorldV1(continuity: true, retainGate: retainGate)
    let id = UUID(), operation = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: id, operationID: operation))
    _ = try await world.owner.handle(world.command(.activate, backendID: id, operationID: operation))
    let backend = try #require(await world.spy.created.first).0
    let retention = Task { try await world.owner.handle(world.command(.retain, backendID: id, operationID: operation)) }
    try await retainGate.waitUntilEntered()
    await world.reader.suspendNextOriginalRead(watcherGate)
    try await watcherGate.waitUntilEntered()
    // The watcher observed .retaining; the same exact operation now becomes
    // .retained while its authority read remains suspended.
    await retainGate.release()
    #expect(try await retention.value.streamRetained == true)
    await watcherGate.release()
    try await Task.sleep(for: .milliseconds(200))
    #expect(await backend.retirements == 0)
    #expect(try await world.owner.handle(world.command(.retainedHealth, backendID: id, operationID: operation)).streamRetained == true)
    await world.owner.retire()
}

@available(macOS 26.0, *)
@Test func staleRetainingWatcherStillDrainsLostOriginalControl() async throws {
    try requireBackendWatcherFixtureCaseV1("original-control-loss-after-stale-check-still-drains")
    let retainGate = NativeBackendGateV1(), watcherGate = NativeBackendGateV1()
    let world = try NativeBackendWorldV1(continuity: true, retainGate: retainGate)
    let id = UUID(), operation = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: id, operationID: operation))
    _ = try await world.owner.handle(world.command(.activate, backendID: id, operationID: operation))
    let (backend, permit) = try #require(await world.spy.created.first)
    let retention = Task { try await world.owner.handle(world.command(.retain, backendID: id, operationID: operation)) }
    try await retainGate.waitUntilEntered()
    await world.reader.suspendNextOriginalRead(watcherGate)
    try await watcherGate.waitUntilEntered()
    await retainGate.release()
    #expect(try await retention.value.streamRetained == true)
    await world.reader.revoke()
    await watcherGate.release()
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while await backend.retirements == 0, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await backend.retirements == 1)
    #expect(!permit.isCurrent)
    await world.owner.retire()
}

@available(macOS 26.0, *)
@Test func retainedMenuOriginalControlLossDrainsSameBackend() async throws {
    let world = try NativeBackendWorldV1(continuity: true), id = UUID(), operation = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: id, operationID: operation))
    _ = try await world.owner.handle(world.command(.activate, backendID: id, operationID: operation))
    _ = try await world.owner.handle(world.command(.retain, backendID: id, operationID: operation))
    let (backend, permit) = try #require(await world.spy.created.first)
    await world.reader.revoke()
    await world.owner.prepareSurfaceChange()
    #expect(await backend.retirements == 1 && !permit.isCurrent)
}

@available(macOS 26.0, *)
@Test func polledNativeActivationLeavesCommandLaneFreeAndStartsOneWorker() async throws {
    let gate = NativeBackendGateV1(), world = try NativeBackendWorldV1(activateGate: gate)
    let backendID = UUID(), operationID = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: backendID, operationID: operationID))
    func poll() throws -> LocalInteractiveNativeBackendCommandV1 {
        try .init(commandID: UUID(), backendID: backendID, operationID: operationID,
            operation: .activate, scope: world.scope, pollActivation: true)
    }
    let first = try await world.owner.handle(poll())
    #expect(first.activationPending == true && first.portBase == nil)
    while !(await gate.entered) { await Task.yield() }
    let second = try await world.owner.handle(poll())
    #expect(second.activationPending == true)
    let observation = try await world.owner.handle(world.command(.health, backendID: backendID, operationID: operationID))
    #expect(observation.active == false)
    let backend = try #require(await world.spy.created.first).0
    #expect(await backend.activations == 1)
    await gate.release()
    var endpoint: UInt16?
    for _ in 0..<100 {
        endpoint = try await world.owner.handle(poll()).portBase
        if endpoint != nil { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(endpoint == 58989)
    #expect(await backend.activations == 1)
    await world.owner.retire()
}

@available(macOS 26.0, *)
@Test func polledNativeActivationStopFencesBeforeJoiningLateEndpoint() async throws {
    let gate = NativeBackendGateV1(), world = try NativeBackendWorldV1(activateGate: gate)
    let id = UUID(), op = UUID()
    _ = try await world.owner.handle(world.command(.prepare, backendID: id, operationID: op))
    let poll = try LocalInteractiveNativeBackendCommandV1(commandID: UUID(), backendID: id, operationID: op,
        operation: .activate, scope: world.scope, pollActivation: true)
    #expect(try await world.owner.handle(poll).activationPending == true)
    while !(await gate.entered) { await Task.yield() }
    let pair = try #require(await world.spy.created.first)
    let stop = Task { await world.owner.retire() }
    while pair.1.isCurrent { await Task.yield() }
    #expect(!pair.1.isCurrent)
    await gate.release(); await stop.value
    await #expect(throws: LocalInteractiveNativeBackendErrorV1.unavailable) { try await world.owner.handle(poll) }
    #expect(await pair.0.retirements == 1)
}

@available(macOS 26.0, *)
@Test func polledActivationWireRejectsPendingWithoutOptInAndWrongFields() throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent(); try #require(parent != root); root = parent
    }
    let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
        root.appendingPathComponent("spec/fixtures/local-xpc-native-backend-v0.1.json"))) as? [String: Any])
    let polling = try #require(fixture["activationPolling"] as? [String: Any])
    #expect((polling["maximumStartupMilliseconds"] as? NSNumber)?.uint64Value == LocalInteractiveNativeBackendOperationV1.activationStartupMilliseconds)
    #expect(polling["pollIntervalMilliseconds"] as? Int == LocalInteractiveNativeBackendOperationV1.activationPollMilliseconds)
    let world = try NativeBackendWorldV1(), id = UUID(), op = UUID()
    let legacy = try world.command(.activate, backendID: id, operationID: op)
    #expect(throws: LocalInteractiveNativeBackendErrorV1.invalidMaterial) {
        try LocalInteractiveNativeBackendReceiptV1(command: legacy, activationPending: true)
    }
    let opted = try LocalInteractiveNativeBackendCommandV1(commandID: UUID(), backendID: id, operationID: op,
        operation: .activate, scope: world.scope, pollActivation: true)
    let pending = try LocalInteractiveNativeBackendReceiptV1(command: opted, activationPending: true)
    #expect(try LocalInteractiveLeaseWireCodecV1.decodeNativeBackendReceipt(
        LocalInteractiveLeaseWireCodecV1.encodeNativeBackendReceipt(pending)) == pending)
    for value in [false, true] {
        #expect(throws: LocalInteractiveNativeBackendErrorV1.invalidMaterial) {
            try LocalInteractiveNativeBackendCommandV1(commandID: UUID(), backendID: id, operationID: op,
                operation: .health, scope: world.scope, pollActivation: value)
        }
    }
    #expect(throws: LocalInteractiveNativeBackendErrorV1.invalidMaterial) {
        try LocalInteractiveNativeBackendReceiptV1(command: opted, portBase: 58989, activationPending: true)
    }
    #expect(throws: LocalInteractiveNativeBackendErrorV1.invalidMaterial) {
        try LocalInteractiveNativeBackendReceiptV1(command: opted, activationPending: false)
    }
}

#endif
