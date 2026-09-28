#if os(macOS)
import CompanionIPC
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionLocalXPCPlatform
import Foundation

/// Inert Agent-side proxy. Only the menu resolves the display or owns host
/// credentials/processes; the Agent coordinator retains golden proof validation.
@available(macOS 26.0, *)
public actor MacLocalXPCNativeEnrollmentBackendV1: InteractiveNativeVideoEnrollmentBackendV0 {
    private let sender: any MacLocalXPCInteractiveLeaseSendingV1
    private let snapshot: InteractiveNativeVideoRuntimeSnapshotV0
    private let backendID = UUID()
    private var operationID: UUID?
    private var scope: LocalInteractiveNativeBackendScopeV1?
    private var pending: Task<LocalInteractiveNativeBackendReceiptV1, Error>?
    private var pendingToken: UUID?
    private var healthRead: (token: UUID, task: Task<LocalInteractiveNativeBackendReceiptV1, Error>)?
    private var presentationRead: (token: UUID, generation: Int64, id: UUID, task: Task<LocalInteractiveNativeBackendReceiptV1, Error>)?
    private var retired = false
    private var drain: Task<Void, Never>?

    public init(sender: any MacLocalXPCInteractiveLeaseSendingV1, snapshot: InteractiveNativeVideoRuntimeSnapshotV0) {
        self.sender = sender; self.snapshot = snapshot
    }
    public func prepare(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0, clientCertificateDER: Data) async throws -> Data {
        guard !retired, self.operationID == nil, authority.binding == snapshot.binding, authority.surface == snapshot.surface else {
            throw LocalInteractiveNativeBackendErrorV1.bindingMismatch
        }
        let scope = try LocalInteractiveNativeBackendScopeV1(binding: authority.binding, surface: authority.surface,
            logicalWidthPoints: snapshot.logicalWidthPoints, logicalHeightPoints: snapshot.logicalHeightPoints, rotation: snapshot.rotation,
            selectedDisplayID: snapshot.selectedDisplayID, menuAppGeneration: snapshot.visibleMenuAppGeneration,
            menuAppRevision: snapshot.visibleMenuAppRevision, sessionPublicKeyX963: authority.sessionPublicKeyX963)
        self.operationID = operationID; self.scope = scope
        let reply = try await submit(.init(commandID: UUID(), backendID: backendID, operationID: operationID,
            operation: .prepare, scope: scope, clientCertificateDER: clientCertificateDER))
        guard let encoded = reply.hostCertificateDERBase64 else { throw LocalInteractiveNativeBackendErrorV1.invalidMaterial }
        return try LocalInteractiveNativeBackendScopeV1.bytes(encoded, count: 1...4096)
    }
    public func activate(operationID: UUID) async throws -> InteractiveNativeVideoEndpointV0 {
        guard self.operationID == operationID, let scope else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        let reply = try await submit(.init(commandID: UUID(), backendID: backendID, operationID: operationID,
            operation: .activate, scope: scope))
        guard let port = reply.portBase else { throw LocalInteractiveNativeBackendErrorV1.invalidMaterial }
        return try .init(portBase: port)
    }
    public func isActive(operationID: UUID) async -> Bool {
        guard !retired, self.operationID == operationID, scope != nil else { return false }
        do {
            let reply = try await health(operationID: operationID)
            return reply.active == true
        } catch { return false }
    }
    public func captureEvidence(operationID: UUID) async throws -> InteractiveNativeVideoCaptureEvidenceV0? {
        guard !retired, self.operationID == operationID, scope != nil else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        let reply = try await health(operationID: operationID)
        guard reply.active == true else { return nil }
        return reply.captureEvidence
    }
    public func admitPresentation(operationID: UUID, nativeGeneration: Int64, presentationID: UUID) async throws -> Bool {
        guard !retired, self.operationID == operationID, let scope else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        let read: (token: UUID, generation: Int64, id: UUID, task: Task<LocalInteractiveNativeBackendReceiptV1, Error>)
        if let current = presentationRead {
            guard current.generation == nativeGeneration, current.id == presentationID else { throw LocalInteractiveNativeBackendErrorV1.bindingMismatch }
            read = current
        } else {
            let command = try LocalInteractiveNativeBackendCommandV1(commandID: UUID(), backendID: backendID, operationID: operationID,
                operation: .present, scope: scope, nativeGeneration: nativeGeneration, presentationID: presentationID)
            read = (UUID(), nativeGeneration, presentationID, Task {
                if let observation = self.healthRead?.task { _ = try await observation.value }
                if let worker = self.pending { _ = try await worker.value }
                guard !Task.isCancelled, !self.retired, self.operationID == operationID, self.scope == scope else {
                    throw LocalInteractiveNativeBackendErrorV1.unavailable
                }
                return try await self.submit(command)
            })
            presentationRead = read
        }
        defer { if presentationRead?.token == read.token { presentationRead = nil } }
        let reply = try await withTaskCancellationHandler(operation: { try await read.task.value }, onCancel: { read.task.cancel() })
        guard !Task.isCancelled, !retired, self.operationID == operationID, self.scope == scope else {
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        return reply.inputAdmitted == true
    }

    private func health(operationID: UUID) async throws -> LocalInteractiveNativeBackendReceiptV1 {
        guard !retired, self.operationID == operationID, let scope else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        if let presentation = presentationRead?.task {
            _ = try await presentation.value
            guard !Task.isCancelled, !retired, self.operationID == operationID, self.scope == scope else {
                throw LocalInteractiveNativeBackendErrorV1.unavailable
            }
        }
        let read: (token: UUID, task: Task<LocalInteractiveNativeBackendReceiptV1, Error>)
        if let current = healthRead { read = current }
        else {
            guard pending == nil else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
            let command = try LocalInteractiveNativeBackendCommandV1(commandID: UUID(), backendID: backendID,
                operationID: operationID, operation: .health, scope: scope)
            read = (UUID(), Task { try await self.submit(command) })
            healthRead = read
        }
        defer { if healthRead?.token == read.token { healthRead = nil } }
        let reply = try await read.task.value
        guard !Task.isCancelled, !retired, self.operationID == operationID, self.scope == scope else {
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        return reply
    }

    public func retire(operationID: UUID) async {
        guard self.operationID == nil || self.operationID == operationID else { return }
        if let drain { await drain.value; return }
        retired = true
        let presentation = presentationRead?.task
        presentationRead = nil; presentation?.cancel()
        let observation = healthRead?.task
        healthRead = nil
        observation?.cancel()
        let worker = pending; worker?.cancel()
        let scope = self.scope, sender = self.sender, backendID = self.backendID
        let task = Task {
            _ = try? await presentation?.value
            _ = try? await observation?.value
            _ = try? await worker?.value
            if let scope, let command = try? LocalInteractiveNativeBackendCommandV1(commandID: UUID(), backendID: backendID,
                operationID: operationID, operation: .retire, scope: scope) {
                _ = try? await sender.nativeBackend(command)
            }
        }
        drain = task
        await task.value
        pending = nil; pendingToken = nil; self.scope = nil
    }
    private func submit(_ command: LocalInteractiveNativeBackendCommandV1) async throws -> LocalInteractiveNativeBackendReceiptV1 {
        guard !retired, pending == nil else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        let token = UUID(), sender = self.sender
        let task = Task { try await sender.nativeBackend(command) }
        pending = task; pendingToken = token
        defer { if pendingToken == token { pending = nil; pendingToken = nil } }
        let reply = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        try reply.validate(against: command)
        guard !Task.isCancelled, !retired, pendingToken == token else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        return reply
    }
}
#endif
