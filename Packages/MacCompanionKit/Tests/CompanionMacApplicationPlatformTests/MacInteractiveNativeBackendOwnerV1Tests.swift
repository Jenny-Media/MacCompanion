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

private actor NativeBackendGateV1 {
    private(set) var entered = false
    private var released = false
    private var wait: CheckedContinuation<Void, Never>?
    func suspend() async { entered = true; if released { return }; await withCheckedContinuation { wait = $0 } }
    func release() { released = true; wait?.resume(); wait = nil }
}
private actor NativeBackendProbeV1: InteractiveNativeVideoEnrollmentBackendV0 {
    private(set) var preparations = 0
    private(set) var activations = 0
    private(set) var retirements = 0
    private var evidence: InteractiveNativeVideoCaptureEvidenceV0?
    private let inputPermit: MacInteractiveNativeBackendPermitV1?
    private let prepareGate: NativeBackendGateV1?
    private let retireGate: NativeBackendGateV1?
    init(prepareGate: NativeBackendGateV1?, retireGate: NativeBackendGateV1?, inputPermit: MacInteractiveNativeBackendPermitV1? = nil) {
        self.prepareGate = prepareGate; self.retireGate = retireGate; self.inputPermit = inputPermit
    }
    func canPostInput(operationID: UUID) -> Bool { activations > 0 && retirements == 0 && inputPermit != nil }
    func postInputBatch(operationID: UUID, beforeDeadlineNanoseconds: UInt64, batch: @escaping @Sendable () throws -> Void) throws {
        guard canPostInput(operationID: operationID), let inputPermit else { throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable }
        try inputPermit.withCurrentInput(beforeDeadlineNanoseconds: beforeDeadlineNanoseconds, batch)
    }
    func prepare(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0, clientCertificateDER: Data) async -> Data {
        preparations += 1; await prepareGate?.suspend(); return Data([1, 2, 3])
    }
    func activate(operationID: UUID) throws -> InteractiveNativeVideoEndpointV0 { activations += 1; return try .init(portBase: 58989) }
    func isActive(operationID: UUID) -> Bool { activations > 0 && retirements == 0 }
    func captureEvidence(operationID: UUID) -> InteractiveNativeVideoCaptureEvidenceV0? { evidence }
    func setEvidence(_ value: InteractiveNativeVideoCaptureEvidenceV0) { evidence = value }
    func retire(operationID: UUID) async { retirements += 1; await retireGate?.suspend() }
}
private actor NativeBackendFactorySpyV1 {
    private(set) var created: [(NativeBackendProbeV1, MacInteractiveNativeBackendPermitV1)] = []
    func append(_ backend: NativeBackendProbeV1, permit: MacInteractiveNativeBackendPermitV1) { created.append((backend, permit)) }
}
private actor NativeBackendSnapshotReaderV1 {
    let command: InteractiveRuntimeInstallCommandV0
    let receipt: InteractiveRuntimeInstallReceiptV0
    var admitted = true
    private(set) var inputPaused = false
    private(set) var installedAuthorization: InteractiveRuntimeNativeInputPostingAuthorizationV0?
    private(set) var installations = 0
    func install(_ authorization: InteractiveRuntimeNativeInputPostingAuthorizationV0, fence: InteractiveNativeVideoRequestFenceV0, now: UInt64) throws {
        guard inputPaused, installedAuthorization == nil, try read(fence, now: now) != nil else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        installedAuthorization = authorization; installations += 1
    }
    init(command: InteractiveRuntimeInstallCommandV0, receipt: InteractiveRuntimeInstallReceiptV0) { self.command = command; self.receipt = receipt }
    func revoke() { admitted = false }
    func pause(_ fence: InteractiveNativeVideoRequestFenceV0, now: UInt64) throws {
        guard try read(fence, now: now) != nil else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        inputPaused = true
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
         supportsInput: Bool = false, installGate: NativeBackendGateV1? = nil) throws {
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
        }, factory: { physicalID, geometry, permit, _ in
            #expect(await reader.inputPaused)
            #expect(geometry.capturePixelWidth == 2560 && geometry.capturePixelHeight == 1440)
            #expect(geometry.logicalWidthPoints == 1280 && geometry.logicalHeightPoints == 720)
            guard physicalID == 1234 else { throw LocalInteractiveNativeBackendErrorV1.bindingMismatch }
            let backend = NativeBackendProbeV1(prepareGate: prepareGate, retireGate: retireGate, inputPermit: supportsInput ? permit : nil)
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
#endif
