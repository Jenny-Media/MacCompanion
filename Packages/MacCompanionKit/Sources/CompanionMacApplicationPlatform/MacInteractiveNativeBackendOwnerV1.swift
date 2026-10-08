#if os(macOS)
import CompanionIPC
import CompanionInteractiveShared
import CompanionInteractiveHost
import CompanionInteractiveRuntime
import CompanionInteractiveWire
import Foundation
import OSLog

private let macInteractiveNativeBackendOwnerLoggerV1 = Logger(
    subsystem: "media.jenny.maccompanion.mac",
    category: "interactive-native-backend"
)

/// Menu-local revocable process permit. It is never serialized or provided by
/// a client; the native backend may only start while its owner keeps it current.
public final class MacInteractiveNativeBackendPermitV1: @unchecked Sendable {
    private let lock = NSLock()
    private var admitted = true
    private var inputPaused = false
    private let deadline: UInt64
    private var revalidateCapture: (@Sendable () throws -> Bool)?
    fileprivate init(deadline: UInt64) { self.deadline = deadline }
    public var isCurrent: Bool {
        lock.withLock { admitted && DispatchTime.now().uptimeNanoseconds / 1_000_000 < deadline }
    }
    fileprivate func bindCapture(_ revalidate: @escaping @Sendable () throws -> Bool) throws {
        try lock.withLock {
            guard admitted, revalidateCapture == nil else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
            revalidateCapture = revalidate
        }
    }
    fileprivate func pauseInput() { lock.withLock { inputPaused = true } }
    fileprivate func rebindPausedCapture(_ revalidate: @escaping @Sendable () throws -> Bool) throws {
        try lock.withLock {
            guard admitted, inputPaused, revalidateCapture != nil,
                  DispatchTime.now().uptimeNanoseconds / 1_000_000 < deadline else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
            revalidateCapture = revalidate
        }
    }
    fileprivate func admitFreshInput() throws {
        try lock.withLock {
            guard admitted, revalidateCapture != nil, DispatchTime.now().uptimeNanoseconds / 1_000_000 < deadline else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            inputPaused = false
        }
    }
    /// A bounded local batch only. The caller separately needs presentation
    /// admission and the runtime posting authorization. Do not reenter this
    /// permit's status getter from the synchronous body.
    public func withCurrentInput(beforeDeadlineNanoseconds: UInt64, _ batch: () throws -> Void) throws {
        try lock.withLock {
            guard admitted, !inputPaused, let revalidateCapture,
                  DispatchTime.now().uptimeNanoseconds / 1_000_000 < deadline,
                  DispatchTime.now().uptimeNanoseconds < beforeDeadlineNanoseconds else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            do {
                guard try revalidateCapture() else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
            } catch {
                admitted = false
                throw error
            }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now / 1_000_000 < deadline, now < beforeDeadlineNanoseconds else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            try batch()
        }
    }
    fileprivate func revoke() { lock.withLock { admitted = false } }
}
public typealias MacInteractiveNativeBackendFactoryV1 = @Sendable (
    UInt32, InteractiveNativeVideoContentGeometryV0, MacInteractiveNativeBackendPermitV1,
    MacManagedNativeSelectedCaptureV1?
) async throws -> any InteractiveNativeVideoEnrollmentBackendV0

public protocol MacInteractiveNativeStreamReplacingV1: InteractiveNativeVideoEnrollmentBackendV0 {
    func configureRetainedReplacement(predecessorOperationID: UUID,
        authority: InteractiveNativeVideoAuthorityV0, physicalDisplayID: UInt32,
        geometry: InteractiveNativeVideoContentGeometryV0, selected: MacManagedNativeSelectedCaptureV1?) async throws
}

/// Menu-owned lifecycle. Only an authenticated local Agent command can reach
/// this owner. The Agent retains durable admission and attestation verification.
@available(macOS 26.0, *)
public actor MacInteractiveNativeBackendOwnerV1 {
    private enum Phase { case preparing, prepared, activating, active, retaining, retained }
    private struct Owned {
        let backendID: UUID
        let operationID: UUID
        let scope: LocalInteractiveNativeBackendScopeV1
        let permit: MacInteractiveNativeBackendPermitV1
        let leasePhysicalDisplayID: UInt32
        let physicalDisplayID: UInt32
        let captureGeometry: InteractiveNativeVideoContentGeometryV0?
        let selectedCapture: MacManagedNativeSelectedCaptureV1?
        var backend: (any InteractiveNativeVideoEnrollmentBackendV0)?
        var phase: Phase {
            didSet { if phase != oldValue { validationGeneration = UUID() } }
        }
        var validationGeneration = UUID()
        var nativeAuthorization: InteractiveRuntimeNativeInputPostingAuthorizationV0? = nil
        var rendererGeneration: Int64? = nil
        var presentationID: UUID? = nil
        var retainedUntil: UInt64? = nil
        var predecessorOperationID: UUID? = nil
        var activationEndpoint: InteractiveNativeVideoEndpointV0? = nil
        var activationUntil: UInt64? = nil
        var activationFailed = false
    }
    private let readSnapshot: @Sendable (InteractiveNativeVideoRequestFenceV0, UInt64) async throws -> LocalInteractiveNativeRuntimeSnapshotV1?
    private let pauseInput: @Sendable (InteractiveNativeVideoRequestFenceV0, UInt64) async throws -> Void
    private let installInput: @Sendable (InteractiveRuntimeNativeInputPostingAuthorizationV0, InteractiveNativeVideoRequestFenceV0, UInt64) async throws -> Void
    private let resolveDisplay: @Sendable (UUID) throws -> UInt32
    private let readCaptureGeometry: @Sendable (UInt32, LocalInteractiveNativeBackendScopeV1) throws -> InteractiveNativeVideoContentGeometryV0
    private let readSelectedCapture: @Sendable (LocalInteractiveNativeBackendScopeV1, UInt32) async throws -> MacManagedNativeSelectedCaptureV1?
    private let factory: MacInteractiveNativeBackendFactoryV1
    private let readOriginalControl: (@Sendable (LocalInteractiveNativeBackendScopeV1, UInt64) async throws -> Bool)?
    private var owned: Owned?
    private var pending: Task<LocalInteractiveNativeBackendReceiptV1, Error>?
    private var activationWorker: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private var drain: Task<Void, Never>?
    private var retiredIDs: [UUID] = []
    private var retiredScopes: [(backendID: UUID, operationID: UUID, scope: LocalInteractiveNativeBackendScopeV1)] = []

    public static func make(
        displaySelection: MacInteractiveOpaqueDisplaySelectionV1,
        readSnapshot: @escaping @Sendable (InteractiveNativeVideoRequestFenceV0, UInt64) async throws -> LocalInteractiveNativeRuntimeSnapshotV1?,
        pauseInput: @escaping @Sendable (InteractiveNativeVideoRequestFenceV0, UInt64) async throws -> Void,
        installInput: @escaping @Sendable (InteractiveRuntimeNativeInputPostingAuthorizationV0, InteractiveNativeVideoRequestFenceV0, UInt64) async throws -> Void = { _, _, _ in throw LocalInteractiveNativeBackendErrorV1.unavailable },
        factory: @escaping MacInteractiveNativeBackendFactoryV1
    ) -> MacInteractiveNativeBackendOwnerV1 {
        .init(readSnapshot: readSnapshot, pauseInput: pauseInput, installInput: installInput,
              resolveDisplay: { try displaySelection.resolvePhysicalDisplayID(selectedDisplayID: $0) }, factory: factory)
    }

    public init(
        readSnapshot: @escaping @Sendable (InteractiveNativeVideoRequestFenceV0, UInt64) async throws -> LocalInteractiveNativeRuntimeSnapshotV1?,
        pauseInput: @escaping @Sendable (InteractiveNativeVideoRequestFenceV0, UInt64) async throws -> Void,
        installInput: @escaping @Sendable (InteractiveRuntimeNativeInputPostingAuthorizationV0, InteractiveNativeVideoRequestFenceV0, UInt64) async throws -> Void = { _, _, _ in throw LocalInteractiveNativeBackendErrorV1.unavailable },
        resolveDisplay: @escaping @Sendable (UUID) throws -> UInt32,
        readCaptureGeometry: @escaping @Sendable (UInt32, LocalInteractiveNativeBackendScopeV1) throws -> InteractiveNativeVideoContentGeometryV0 = {
            try MacInteractiveNativeCaptureGeometryV1.read(physicalDisplayID: $0, scope: $1)
        },
        readSelectedCapture: @escaping @Sendable (LocalInteractiveNativeBackendScopeV1, UInt32) async throws -> MacManagedNativeSelectedCaptureV1? = { _, _ in nil },
        readOriginalControl: (@Sendable (LocalInteractiveNativeBackendScopeV1, UInt64) async throws -> Bool)? = nil,
        factory: @escaping MacInteractiveNativeBackendFactoryV1
    ) {
        self.readSnapshot = readSnapshot; self.resolveDisplay = resolveDisplay; self.factory = factory
        self.pauseInput = pauseInput; self.readCaptureGeometry = readCaptureGeometry
        self.readSelectedCapture = readSelectedCapture; self.installInput = installInput
        self.readOriginalControl = readOriginalControl
    }

    public func handle(_ command: LocalInteractiveNativeBackendCommandV1) async throws -> LocalInteractiveNativeBackendReceiptV1 {
        do { return try await handleCommand(command) }
        catch {
            let phase = owned.map { String(describing: $0.phase) } ?? "idle"
            macInteractiveNativeBackendOwnerLoggerV1.error("native-command-rejected operation=\(command.operation.rawValue, privacy: .public) stage=command-admission phase=\(phase, privacy: .public) reason=\(MacNativeFailureDiagnosticsV1.reason(error), privacy: .public)")
            throw error
        }
    }

    private func handleCommand(_ command: LocalInteractiveNativeBackendCommandV1) async throws -> LocalInteractiveNativeBackendReceiptV1 {
        try command.validate()
        if (command.operation == .health || command.operation == .retainedHealth),
           retiredScopes.contains(where: { $0.backendID == command.backendID
               && $0.operationID == command.operationID && $0.scope == command.scope }) {
            return try command.operation == .health ? .init(command: command, active: false) : .init(command: command, streamRetained: false)
        }
        if command.operation == .health, let current = owned, exact(command, current), let drain {
            await drain.value
            return try .init(command: command, active: false)
        }
        if command.operation == .health, let current = owned, exact(command, current), !current.permit.isCurrent {
            await retire()
            return try .init(command: command, active: false)
        }
        if command.operation == .retire {
            if let current = owned, current.backendID == command.backendID {
                guard current.operationID == command.operationID, current.scope == command.scope else {
                    throw LocalInteractiveNativeBackendErrorV1.bindingMismatch
                }
                await retire()
            } else if let drain { await drain.value }
            remember(command.backendID)
            return try .init(command: command)
        }
        guard drain == nil, pending == nil else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        if command.operation == .prepareReplacement {
            guard let previous = owned, previous.phase == .retained, previous.permit.isCurrent,
                  command.previousBackendID == previous.backendID, command.previousOperationID == previous.operationID,
                  command.scope.retainsOriginalControl(of: previous.scope), !retiredIDs.contains(command.backendID),
                  let backend = previous.backend, backend is any MacInteractiveNativeStreamReplacingV1,
                  let retainedUntil = previous.retainedUntil, DispatchTime.now().uptimeNanoseconds / 1_000_000 < retainedUntil else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            previous.nativeAuthorization?.revoke(); previous.permit.pauseInput()
            owned = .init(backendID: command.backendID, operationID: command.operationID, scope: command.scope,
                permit: previous.permit, leasePhysicalDisplayID: 0, physicalDisplayID: 0,
                captureGeometry: nil, selectedCapture: nil, backend: backend, phase: .preparing,
                retainedUntil: retainedUntil, predecessorOperationID: previous.operationID)
            retiredScopes.append((previous.backendID, previous.operationID, previous.scope))
            if retiredScopes.count > 64 { retiredScopes.removeFirst(retiredScopes.count-64) }
            remember(previous.backendID)
        } else if command.operation == .prepare {
            guard owned == nil, !retiredIDs.contains(command.backendID) else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
            // Validate the registered curve point before any private preparation.
            _ = try authority(command.scope)
            // Reserve before the first suspension; physical mapping is joined
            // later inside the retained task while Stop can already fence it.
            owned = .init(backendID: command.backendID, operationID: command.operationID, scope: command.scope,
                permit: .init(deadline: command.scope.expiresAtMonotonicMilliseconds), leasePhysicalDisplayID: 0,
                physicalDisplayID: 0, captureGeometry: nil,
                selectedCapture: nil,
                backend: nil, phase: .preparing)
            startWatcher()
        } else {
            guard let current = owned, exact(command, current), current.permit.isCurrent else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            if command.operation == .retain {
                guard current.phase == .active, readOriginalControl != nil,
                      current.backend is any MacInteractiveNativeStreamReplacingV1 else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                current.nativeAuthorization?.revoke(); current.permit.pauseInput()
                owned?.nativeAuthorization = nil; owned?.rendererGeneration = nil; owned?.presentationID = nil
                owned?.phase = .retaining
                owned?.retainedUntil = min(current.scope.expiresAtMonotonicMilliseconds,
                    DispatchTime.now().uptimeNanoseconds / 1_000_000 + 15_000)
            }
            if command.operation == .activate {
                guard current.phase == .prepared || (command.pollActivation == true
                    && (current.phase == .activating || current.phase == .active)) else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                if current.phase == .prepared { owned?.phase = .activating }
            }
        }
        let task = Task { try await self.perform(command) }
        pending = task
        do {
            let receipt = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard !Task.isCancelled, let current = owned, exact(command, current), current.permit.isCurrent else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            pending = nil
            return receipt
        } catch {
            // The worker has completed before this drain joins its handle.
            if let current = owned, exact(command, current) { await retire() }
            if command.operation == .health, error as? LocalInteractiveNativeBackendErrorV1 == .unavailable,
               retiredScopes.contains(where: { $0.backendID == command.backendID
                   && $0.operationID == command.operationID && $0.scope == command.scope }) {
                return try .init(command: command, active: false)
            }
            throw error
        }
    }

    public func retire(interactiveSessionID: UUID) async {
        guard owned?.scope.interactiveSessionID == interactiveSessionID else { return }
        await retire()
    }

    /// Only a confirmed retained owner may survive the trusted menu's ordinary
    /// surface/display transition. Every other change joins full retirement.
    /// Trusted local canvas observation; never accepts a client-declared reuse claim.
    public func retainedCanvas() async -> (width: Int, height: Int)? {
        guard let current = owned, current.phase == .retained, pending == nil, drain == nil,
              current.permit.isCurrent, let readOriginalControl,
              let until = current.retainedUntil, DispatchTime.now().uptimeNanoseconds / 1_000_000 < until,
              (try? await readOriginalControl(current.scope, DispatchTime.now().uptimeNanoseconds)) == true,
              let backend = current.backend, await backend.isStreamRetained(operationID: current.operationID),
              owned?.backendID == current.backendID, owned?.phase == .retained, pending == nil, drain == nil else { return nil }
        return (current.scope.encodedWidth, current.scope.encodedHeight)
    }

    public func prepareSurfaceChange(_ transition: InteractiveRuntimeSurfaceTransitionCommandV0? = nil) async {
        if let current = owned, current.phase == .retained, pending == nil, drain == nil,
           current.permit.isCurrent, let readOriginalControl,
           transition == nil || (transition?.replacement.interactiveSessionID == current.scope.interactiveSessionID
                && transition?.replacement.authorizationEpoch.rawValue == UInt64(current.scope.authorizationEpoch)
                && transition?.descriptor.kind != .focusedRegion),
           (try? await readOriginalControl(current.scope, DispatchTime.now().uptimeNanoseconds)) == true,
           let backend = current.backend, await backend.isStreamRetained(operationID: current.operationID),
           owned?.backendID == current.backendID, owned?.operationID == current.operationID,
           owned?.phase == .retained, pending == nil, drain == nil, current.permit.isCurrent { return }
        await retire()
    }

    public func retire() async {
        if let drain { await drain.value; return }
        guard let current = owned else { return }
        current.nativeAuthorization?.revoke()
        current.permit.revoke()
        watcher?.cancel(); watcher = nil
        let worker = pending
        worker?.cancel()
        let activation = activationWorker
        activation?.cancel()
        let task = Task { [self] in
            _ = try? await worker?.value
            // A late inert factory is either published into this exact owned
            // slot or retired by its worker before returning.
            if let backend = owned?.backend {
                await backend.retire(operationID: current.operationID)
                if let predecessor = current.predecessorOperationID { await backend.retire(operationID: predecessor) }
            }
            await activation?.value
            // Publish retirement inside the shared task. A health reader or
            // another Stop waiter can resume before the caller that created
            // this drain; each must observe the exact tombstone and cleared
            // ownership as part of joined cleanup.
            remember(current.backendID)
            retiredScopes.append((current.backendID, current.operationID, current.scope))
            if retiredScopes.count > 64 { retiredScopes.removeFirst(retiredScopes.count - 64) }
            owned = nil; pending = nil; activationWorker = nil; drain = nil
        }
        drain = task
        await task.value
    }

    private func perform(_ command: LocalInteractiveNativeBackendCommandV1) async throws -> LocalInteractiveNativeBackendReceiptV1 {
        var diagnosticStage = "initial-check"
        do {
            try await check(command)
            switch command.operation {
            case .prepare, .prepareReplacement:
                diagnosticStage = "pause-input"
                try await pauseInput(command.scope.runtimeFence(backendID: command.backendID),
                    DispatchTime.now().uptimeNanoseconds)
                try await check(command)
                diagnosticStage = "resolve-display"
                let leasePhysical = try resolveDisplay(command.scope.selectedDisplayID)
                diagnosticStage = "read-selection"
                let selected = try await readSelectedCapture(command.scope, leasePhysical)
                diagnosticStage = "read-snapshot"
                let snapshot = try await readSnapshot(command.scope.runtimeFence(backendID: command.backendID),
                    DispatchTime.now().uptimeNanoseconds)
                diagnosticStage = "snapshot-validation"
                guard leasePhysical != 0, let snapshot, command.scope.matches(snapshot),
                      snapshot.isCurrent(nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds),
                      let current = owned, exact(command, current), current.permit.isCurrent else {
                    throw LocalInteractiveNativeBackendErrorV1.unavailable
                }
                diagnosticStage = "selection-validation"
                guard selectionMatches(snapshot: snapshot, selected: selected) else {
                    throw LocalInteractiveNativeBackendErrorV1.unavailable
                }
                let physical = try Self.captureDisplayID(kind: snapshot.surfaceKind, leaseDisplayID: leasePhysical,
                    selectedDisplayID: selected?.physicalDisplayID)
                diagnosticStage = "measure-geometry"
                let geometry = try measureGeometry(physical, scope: command.scope, selected: selected)
                let resolve = resolveDisplay, readGeometry = readCaptureGeometry, scope = command.scope
                let captureCheck: @Sendable () throws -> Bool = {
                    guard try resolve(scope.selectedDisplayID) == leasePhysical else { return false }
                    if let selected { return selected.isCurrent && selected.geometry == geometry }
                    return try readGeometry(physical, scope) == geometry
                }
                diagnosticStage = "bind-capture"
                if command.operation == .prepareReplacement { try current.permit.rebindPausedCapture(captureCheck) }
                else { try current.permit.bindCapture(captureCheck) }
                let retainedBackend = current.backend
                owned = .init(backendID: current.backendID, operationID: current.operationID, scope: current.scope,
                    permit: current.permit, leasePhysicalDisplayID: leasePhysical,
                    physicalDisplayID: physical, captureGeometry: geometry,
                    selectedCapture: selected, backend: retainedBackend, phase: .preparing,
                    retainedUntil: current.retainedUntil, predecessorOperationID: current.predecessorOperationID)
                try await check(command)
                let backend: any InteractiveNativeVideoEnrollmentBackendV0
                if command.operation == .prepareReplacement {
                    guard let retainedBackend = retainedBackend as? any MacInteractiveNativeStreamReplacingV1,
                          let previousOperation = current.predecessorOperationID else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                    diagnosticStage = "configure-replacement"
                    try await retainedBackend.configureRetainedReplacement(predecessorOperationID: previousOperation,
                        authority: authority(command.scope), physicalDisplayID: physical, geometry: geometry, selected: selected)
                    try await check(command)
                    backend = retainedBackend
                } else { backend = try await factory(physical, geometry, current.permit, selected) }
                guard !Task.isCancelled, let latest = owned, exact(command, latest), latest.permit.isCurrent else {
                    await backend.retire(operationID: command.operationID)
                    throw LocalInteractiveNativeBackendErrorV1.unavailable
                }
                owned?.backend = backend
                try await check(command)
                guard let encoded = command.clientCertificateDERBase64 else { throw LocalInteractiveNativeBackendErrorV1.invalidMaterial }
                diagnosticStage = "backend-prepare"
                let der = try await backend.prepare(operationID: command.operationID, authority: authority(command.scope),
                    clientCertificateDER: LocalInteractiveNativeBackendScopeV1.bytes(encoded, count: 1...4096))
                try await check(command)
                owned?.phase = .prepared
                owned?.predecessorOperationID = nil
                return try .init(command: command, hostCertificateDER: der)
            case .activate:
                guard let backend = owned?.backend else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                if command.pollActivation == true {
                    guard owned?.activationFailed == false else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                    if let endpoint = owned?.activationEndpoint { return try .init(command: command, portBase: endpoint.portBase) }
                    if activationWorker == nil {
                        owned?.activationUntil = min(command.scope.expiresAtMonotonicMilliseconds,
                            DispatchTime.now().uptimeNanoseconds / 1_000_000 + LocalInteractiveNativeBackendOperationV1.activationStartupMilliseconds)
                        activationWorker = Task { [weak self] in
                            do {
                                let endpoint = try await backend.activate(operationID: command.operationID)
                                guard let self else { await backend.retire(operationID: command.operationID); return }
                                try await self.completeActivation(command, endpoint: endpoint)
                            } catch {
                                macInteractiveNativeBackendOwnerLoggerV1.error("native-command-rejected operation=activate stage=activation-worker reason=\(MacNativeFailureDiagnosticsV1.reason(error), privacy: .public)")
                                await self?.failActivation(command)
                            }
                        }
                    }
                    return try .init(command: command, activationPending: true)
                }
                let endpoint = try await backend.activate(operationID: command.operationID)
                try await check(command)
                owned?.phase = .active; owned?.retainedUntil = nil
                return try .init(command: command, portBase: endpoint.portBase)
            case .present:
                guard let current = owned, current.phase == .active, let backend = current.backend,
                      let generation = command.nativeGeneration, let presentationID = command.presentationID,
                      await backend.canPostInput(operationID: command.operationID) else {
                    throw LocalInteractiveNativeBackendErrorV1.unavailable
                }
                try await check(command)
                guard let evidence = try await backend.captureEvidence(operationID: command.operationID),
                      let geometry = owned?.captureGeometry else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                try await check(command)
                try evidence.validate(operationID: command.operationID, geometry: geometry,
                    nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
                if let installed = owned?.nativeAuthorization {
                    guard owned?.rendererGeneration == generation, owned?.presentationID == presentationID, !installed.isRevoked else {
                        throw LocalInteractiveNativeBackendErrorV1.bindingMismatch
                    }
                } else {
                    let authorization = InteractiveRuntimeNativeInputPostingAuthorizationV0(binding: try command.scope.binding(),
                        surface: try command.scope.surface()) { deadline, batch in
                        try await backend.postInputBatch(operationID: command.operationID,
                            beforeDeadlineNanoseconds: deadline, batch: batch)
                    }
                    owned?.nativeAuthorization = authorization
                    owned?.rendererGeneration = generation; owned?.presentationID = presentationID
                    try await installInput(authorization, command.scope.runtimeFence(backendID: command.backendID),
                        DispatchTime.now().uptimeNanoseconds)
                    guard !authorization.isRevoked else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                }
                try await check(command)
                guard await backend.isActive(operationID: command.operationID) else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                try await check(command)
                try evidence.validate(operationID: command.operationID, geometry: geometry,
                    nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
                try current.permit.admitFreshInput()
                return try .init(command: command, active: true, captureEvidence: evidence, inputAdmitted: true)
            case .health:
                guard let current = owned, let backend = current.backend, current.phase == .active else {
                    return try .init(command: command, active: false)
                }
                let active = await backend.isActive(operationID: command.operationID)
                try await check(command)
                guard active else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                let evidence = try await backend.captureEvidence(operationID: command.operationID)
                try await check(command)
                if let evidence {
                    guard let geometry = owned?.captureGeometry else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                    try evidence.validate(operationID: command.operationID, geometry: geometry,
                        nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
                }
                var supportsContinuity = false
                if readOriginalControl != nil, backend is any MacInteractiveNativeStreamReplacingV1 {
                    supportsContinuity = await backend.supportsStreamContinuity(operationID: command.operationID)
                    try await check(command)
                }
                return try .init(command: command, active: true, captureEvidence: evidence,
                    streamContinuity: supportsContinuity ? true : nil)
            case .retain:
                guard let current = owned, current.phase == .retaining, let backend = current.backend,
                      await backend.supportsStreamContinuity(operationID: command.operationID) else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                try await check(command)
                try await pauseInput(command.scope.runtimeFence(backendID: command.backendID), DispatchTime.now().uptimeNanoseconds)
                try await check(command)
                try await backend.retainStream(operationID: command.operationID)
                try await check(command)
                guard await backend.isStreamRetained(operationID: command.operationID) else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                try await check(command); owned?.phase = .retained
                return try .init(command: command, streamRetained: true)
            case .retainedHealth:
                guard let current = owned, current.phase == .retained, let backend = current.backend else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                let retained = await backend.isStreamRetained(operationID: command.operationID)
                try await check(command)
                guard retained else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                return try .init(command: command, streamRetained: true)
            case .retire:
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
        } catch {
            macInteractiveNativeBackendOwnerLoggerV1.error("native-command-rejected operation=\(command.operation.rawValue, privacy: .public) stage=\(diagnosticStage, privacy: .public) reason=\(MacNativeFailureDiagnosticsV1.reason(error), privacy: .public)")
            throw error
        }
    }

    private func check(_ command: LocalInteractiveNativeBackendCommandV1) async throws {
        guard !Task.isCancelled, let current = owned, exact(command, current), current.permit.isCurrent else {
            macInteractiveNativeBackendOwnerLoggerV1.error("backend check rejected reason=owner-or-permit")
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        if current.activationFailed || (current.phase == .activating
            && current.activationUntil.map { DispatchTime.now().uptimeNanoseconds / 1_000_000 >= $0 } == true) {
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        if current.phase == .retaining || current.phase == .retained {
            guard let readOriginalControl, let retainedUntil = current.retainedUntil,
                  DispatchTime.now().uptimeNanoseconds / 1_000_000 < retainedUntil,
                  try await readOriginalControl(current.scope, DispatchTime.now().uptimeNanoseconds),
                  !Task.isCancelled, let latest = owned, exact(command, latest), latest.permit.isCurrent,
                  latest.phase == current.phase, DispatchTime.now().uptimeNanoseconds / 1_000_000 < retainedUntil else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            return
        }
        if let retainedUntil = current.retainedUntil,
           DispatchTime.now().uptimeNanoseconds / 1_000_000 >= retainedUntil { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        let fence = try command.scope.runtimeFence(backendID: command.backendID)
        let currentSnapshot = try await readSnapshot(fence, DispatchTime.now().uptimeNanoseconds)
        guard let snapshot = currentSnapshot,
              command.scope.matches(snapshot), snapshot.isCurrent(nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds),
              !Task.isCancelled, let latest = owned, exact(command, latest), latest.permit.isCurrent else {
            macInteractiveNativeBackendOwnerLoggerV1.error("backend check rejected reason=runtime-snapshot")
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        if latest.physicalDisplayID != 0 {
            guard selectionMatches(snapshot: snapshot, selected: latest.selectedCapture) else {
                macInteractiveNativeBackendOwnerLoggerV1.error("backend check rejected reason=surface-selection")
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            guard try resolveDisplay(command.scope.selectedDisplayID) == latest.leasePhysicalDisplayID,
                  let expected = latest.captureGeometry else {
                macInteractiveNativeBackendOwnerLoggerV1.error("backend check rejected reason=display-binding")
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            let selected = try await readSelectedCapture(command.scope, latest.leasePhysicalDisplayID)
            guard !Task.isCancelled, let current = owned, exact(command, current), current.permit.isCurrent,
                  selectionMatches(snapshot: snapshot, selected: selected),
                  try Self.captureDisplayID(kind: snapshot.surfaceKind,
                      leaseDisplayID: current.leasePhysicalDisplayID,
                      selectedDisplayID: selected?.physicalDisplayID) == current.physicalDisplayID,
                  selected == current.selectedCapture,
                  try measureGeometry(current.physicalDisplayID, scope: command.scope, selected: selected) == expected else {
                macInteractiveNativeBackendOwnerLoggerV1.error("backend check rejected reason=capture-binding-or-geometry")
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
        }
    }

    private func completeActivation(_ command: LocalInteractiveNativeBackendCommandV1,
        endpoint: InteractiveNativeVideoEndpointV0) async throws {
        try await check(command)
        guard !Task.isCancelled, let current = owned, exact(command, current), current.phase == .activating,
              let until = current.activationUntil, DispatchTime.now().uptimeNanoseconds / 1_000_000 < until else {
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        owned?.activationEndpoint = endpoint; owned?.activationUntil = nil
        owned?.phase = .active; owned?.retainedUntil = nil
        activationWorker = nil
    }
    private func failActivation(_ command: LocalInteractiveNativeBackendCommandV1) {
        if let current = owned, exact(command, current), current.phase == .activating {
            owned?.activationFailed = true; activationWorker = nil
        }
    }
    nonisolated package static func captureDisplayID(kind: InteractiveSurfaceKind,
        leaseDisplayID: UInt32, selectedDisplayID: UInt32?) throws -> UInt32 {
        guard leaseDisplayID != 0 else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        switch kind {
        case .desktop:
            guard selectedDisplayID == nil else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        case .window:
            guard let selectedDisplayID, selectedDisplayID != 0 else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            return selectedDisplayID
        case .application:
            guard selectedDisplayID == leaseDisplayID else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        case .focusedRegion:
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        return leaseDisplayID
    }

    private func selectionMatches(snapshot: LocalInteractiveNativeRuntimeSnapshotV1,
                                  selected: MacManagedNativeSelectedCaptureV1?) -> Bool {
        if snapshot.surfaceKind == .desktop { return selected == nil }
        return selected?.surfaceKind == snapshot.surfaceKind
    }
    private func measureGeometry(_ physicalDisplayID: UInt32, scope: LocalInteractiveNativeBackendScopeV1,
                                 selected: MacManagedNativeSelectedCaptureV1?) throws -> InteractiveNativeVideoContentGeometryV0 {
        let geometry = try selected?.geometry ?? readCaptureGeometry(physicalDisplayID, scope)
        guard scope.rotation == .degrees0,
              geometry.encodedWidth == scope.encodedWidth, geometry.encodedHeight == scope.encodedHeight,
              geometry.logicalWidthPoints == Int(scope.logicalWidthPoints),
              geometry.logicalHeightPoints == Int(scope.logicalHeightPoints) else {
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        return geometry
    }
    private func startWatcher() {
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                await self.revalidate()
            }
        }
    }
    private func revalidate() async {
        guard let current = owned else { return }
        do {
            let command = try LocalInteractiveNativeBackendCommandV1(commandID: UUID(), backendID: current.backendID,
                operationID: current.operationID, operation: current.phase == .retained ? .retainedHealth : .health, scope: current.scope)
            try await check(command)
            if current.phase == .retained, let backend = current.backend,
               !(await backend.isStreamRetained(operationID: current.operationID)) { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        } catch {
            // A suspension can cross a local phase change without changing
            // operation ID (for example, retaining -> retained). That result
            // cannot retire the owner validated by the newer phase. The next
            // bounded iteration checks its current authority and deadline.
            guard let latest = owned, latest.backendID == current.backendID,
                  latest.operationID == current.operationID, latest.scope == current.scope,
                  latest.validationGeneration == current.validationGeneration else { return }
            macInteractiveNativeBackendOwnerLoggerV1.error(
                "backend watcher retired current operation errorType=\(String(reflecting: type(of: error)), privacy: .public) permitCurrent=\(current.permit.isCurrent, privacy: .public) selectedCaptureCurrent=\(current.selectedCapture?.isCurrent ?? true, privacy: .public)"
            )
            await retire()
        }
    }
    private func authority(_ scope: LocalInteractiveNativeBackendScopeV1) throws -> InteractiveNativeVideoAuthorityV0 {
        try .init(binding: scope.binding(), surface: scope.surface(), sessionPublicKeyX963: scope.sessionPublicKeyX963())
    }
    private func exact(_ command: LocalInteractiveNativeBackendCommandV1, _ current: Owned) -> Bool {
        command.backendID == current.backendID && command.operationID == current.operationID && command.scope == current.scope
    }
    private func remember(_ id: UUID) {
        if !retiredIDs.contains(id) { retiredIDs.append(id) }
        if retiredIDs.count > 64 { retiredIDs.removeFirst(retiredIDs.count - 64) }
    }
}
#endif
