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
    /// A bounded local batch only. The caller separately needs presentation
    /// admission and the runtime posting authorization. Do not reenter this
    /// permit's status getter from the synchronous body.
    public func withCurrentInput(beforeDeadlineNanoseconds: UInt64, _ batch: () throws -> Void) throws {
        try lock.withLock {
            guard admitted, let revalidateCapture,
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

/// Menu-owned lifecycle. Only an authenticated local Agent command can reach
/// this owner. The Agent retains durable admission and attestation verification.
@available(macOS 26.0, *)
public actor MacInteractiveNativeBackendOwnerV1 {
    private enum Phase { case preparing, prepared, activating, active }
    private struct Owned {
        let backendID: UUID
        let operationID: UUID
        let scope: LocalInteractiveNativeBackendScopeV1
        let permit: MacInteractiveNativeBackendPermitV1
        let physicalDisplayID: UInt32
        let captureGeometry: InteractiveNativeVideoContentGeometryV0?
        let selectedCapture: MacManagedNativeSelectedCaptureV1?
        var backend: (any InteractiveNativeVideoEnrollmentBackendV0)?
        var phase: Phase
        var nativeAuthorization: InteractiveRuntimeNativeInputPostingAuthorizationV0? = nil
        var rendererGeneration: Int64? = nil
        var presentationID: UUID? = nil
    }
    private let readSnapshot: @Sendable (InteractiveNativeVideoRequestFenceV0, UInt64) async throws -> LocalInteractiveNativeRuntimeSnapshotV1?
    private let pauseInput: @Sendable (InteractiveNativeVideoRequestFenceV0, UInt64) async throws -> Void
    private let installInput: @Sendable (InteractiveRuntimeNativeInputPostingAuthorizationV0, InteractiveNativeVideoRequestFenceV0, UInt64) async throws -> Void
    private let resolveDisplay: @Sendable (UUID) throws -> UInt32
    private let readCaptureGeometry: @Sendable (UInt32, LocalInteractiveNativeBackendScopeV1) throws -> InteractiveNativeVideoContentGeometryV0
    private let readSelectedCapture: @Sendable (LocalInteractiveNativeBackendScopeV1, UInt32) async throws -> MacManagedNativeSelectedCaptureV1?
    private let factory: MacInteractiveNativeBackendFactoryV1
    private var owned: Owned?
    private var pending: Task<LocalInteractiveNativeBackendReceiptV1, Error>?
    private var watcher: Task<Void, Never>?
    private var drain: Task<Void, Never>?
    private var retiredIDs: [UUID] = []

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
        factory: @escaping MacInteractiveNativeBackendFactoryV1
    ) {
        self.readSnapshot = readSnapshot; self.resolveDisplay = resolveDisplay; self.factory = factory
        self.pauseInput = pauseInput; self.readCaptureGeometry = readCaptureGeometry
        self.readSelectedCapture = readSelectedCapture; self.installInput = installInput
    }

    public func handle(_ command: LocalInteractiveNativeBackendCommandV1) async throws -> LocalInteractiveNativeBackendReceiptV1 {
        try command.validate()
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
        if command.operation == .prepare {
            guard owned == nil, !retiredIDs.contains(command.backendID) else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
            // Validate the registered curve point before any private preparation.
            _ = try authority(command.scope)
            // Reserve before the first suspension; physical mapping is joined
            // later inside the retained task while Stop can already fence it.
            owned = .init(backendID: command.backendID, operationID: command.operationID, scope: command.scope,
                permit: .init(deadline: command.scope.expiresAtMonotonicMilliseconds), physicalDisplayID: 0, captureGeometry: nil,
                selectedCapture: nil,
                backend: nil, phase: .preparing)
            startWatcher()
        } else {
            guard let current = owned, exact(command, current), current.permit.isCurrent else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            if command.operation == .activate {
                guard current.phase == .prepared else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                owned?.phase = .activating
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
            throw error
        }
    }

    public func retire(interactiveSessionID: UUID) async {
        guard owned?.scope.interactiveSessionID == interactiveSessionID else { return }
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
        let task = Task { [self] in
            _ = try? await worker?.value
            // A late inert factory is either published into this exact owned
            // slot or retired by its worker before returning.
            if let backend = owned?.backend { await backend.retire(operationID: current.operationID) }
        }
        drain = task
        await task.value
        remember(current.backendID)
        owned = nil; pending = nil; drain = nil
    }

    private func perform(_ command: LocalInteractiveNativeBackendCommandV1) async throws -> LocalInteractiveNativeBackendReceiptV1 {
        try await check(command)
        switch command.operation {
        case .prepare:
            try await pauseInput(command.scope.runtimeFence(backendID: command.backendID),
                DispatchTime.now().uptimeNanoseconds)
            try await check(command)
            let physical = try resolveDisplay(command.scope.selectedDisplayID)
            let selected = try await readSelectedCapture(command.scope, physical)
            let snapshot = try await readSnapshot(command.scope.runtimeFence(backendID: command.backendID),
                DispatchTime.now().uptimeNanoseconds)
            guard physical != 0, let snapshot, command.scope.matches(snapshot),
                  snapshot.isCurrent(nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds),
                  let current = owned, exact(command, current), current.permit.isCurrent else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            guard selectionMatches(snapshot: snapshot, selected: selected),
                  selected == nil || selected?.physicalDisplayID == physical else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            let geometry = try measureGeometry(physical, scope: command.scope, selected: selected)
            let resolve = resolveDisplay, readGeometry = readCaptureGeometry, scope = command.scope
            try current.permit.bindCapture {
                guard try resolve(scope.selectedDisplayID) == physical else { return false }
                if let selected { return selected.isCurrent && selected.geometry == geometry }
                return try readGeometry(physical, scope) == geometry
            }
            owned = .init(backendID: current.backendID, operationID: current.operationID, scope: current.scope,
                permit: current.permit, physicalDisplayID: physical, captureGeometry: geometry,
                selectedCapture: selected, backend: nil, phase: .preparing)
            try await check(command)
            let backend = try await factory(physical, geometry, current.permit, selected)
            guard !Task.isCancelled, let latest = owned, exact(command, latest), latest.permit.isCurrent else {
                await backend.retire(operationID: command.operationID)
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            owned?.backend = backend
            try await check(command)
            guard let encoded = command.clientCertificateDERBase64 else { throw LocalInteractiveNativeBackendErrorV1.invalidMaterial }
            let der = try await backend.prepare(operationID: command.operationID, authority: authority(command.scope),
                clientCertificateDER: LocalInteractiveNativeBackendScopeV1.bytes(encoded, count: 1...4096))
            try await check(command)
            owned?.phase = .prepared
            return try .init(command: command, hostCertificateDER: der)
        case .activate:
            guard let backend = owned?.backend else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
            let endpoint = try await backend.activate(operationID: command.operationID)
            try await check(command)
            owned?.phase = .active
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
            return try .init(command: command, active: true, captureEvidence: evidence)
        case .retire:
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
    }

    private func check(_ command: LocalInteractiveNativeBackendCommandV1) async throws {
        guard !Task.isCancelled, let current = owned, exact(command, current), current.permit.isCurrent else {
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        let fence = try command.scope.runtimeFence(backendID: command.backendID)
        let currentSnapshot = try await readSnapshot(fence, DispatchTime.now().uptimeNanoseconds)
        guard let snapshot = currentSnapshot,
              command.scope.matches(snapshot), snapshot.isCurrent(nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds),
              !Task.isCancelled, let latest = owned, exact(command, latest), latest.permit.isCurrent else {
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        if latest.physicalDisplayID != 0 {
            guard selectionMatches(snapshot: snapshot, selected: latest.selectedCapture) else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            guard try resolveDisplay(command.scope.selectedDisplayID) == latest.physicalDisplayID,
                  let expected = latest.captureGeometry else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
            let selected = try await readSelectedCapture(command.scope, latest.physicalDisplayID)
            guard !Task.isCancelled, let current = owned, exact(command, current), current.permit.isCurrent,
                  selectionMatches(snapshot: snapshot, selected: selected),
                  selected == current.selectedCapture,
                  try measureGeometry(current.physicalDisplayID, scope: command.scope, selected: selected) == expected else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
        }
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
                operationID: current.operationID, operation: .health, scope: current.scope)
            try await check(command)
        } catch {
            macInteractiveNativeBackendOwnerLoggerV1.error(
                "backend watcher retired current operation errorType=\(String(reflecting: type(of: error)), privacy: .public) permitCurrent=\(current.permit.isCurrent, privacy: .public) selectedCaptureCurrent=\(current.selectedCapture?.isCurrent ?? true, privacy: .public)"
            )
            if let latest = owned, latest.backendID == current.backendID, latest.operationID == current.operationID { await retire() }
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
