import Foundation
import CompanionInteractiveShared
import CompanionInteractiveWire

public enum InteractiveRuntimeNativeInputPostingErrorV0: Error, Equatable, Sendable {
    case bindingMismatch, expired, unavailable, notPosted
}

/// A local execution primitive, not an input grant. Only a trusted native
/// composition may install its backend executor after presentation admission.
public struct InteractiveRuntimeNativeInputPostingAuthorizationV0: Sendable {
    public typealias Batch = @Sendable () throws -> Void
    public typealias Executor = @Sendable (UInt64, @escaping Batch) async throws -> Void
    public let binding: InteractiveNativeVideoBindingV0
    public let surface: InteractiveNativeVideoSurfaceV0
    private let executor: Executor
    private let now: @Sendable () -> UInt64
    private let initialNow: UInt64
    private let admission = Admission()

    public var isRevoked: Bool { admission.isRevoked }
    public func revoke() { admission.revoke() }

    public init(binding: InteractiveNativeVideoBindingV0, surface: InteractiveNativeVideoSurfaceV0,
                monotonicNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
                postWhileBackendCurrent: @escaping Executor) {
        self.binding = binding; self.surface = surface
        now = monotonicNanoseconds; initialNow = monotonicNanoseconds()
        executor = postWhileBackendCurrent
    }

    public func perform(_ envelope: InteractiveInputEnvelope, beforeDeadlineNanoseconds: UInt64,
                        batch: @escaping Batch) async throws {
        let invocation = Invocation()
        defer { invocation.invalidate() }
        try await withTaskCancellationHandler {
            guard !Task.isCancelled else { throw InteractiveRuntimeNativeInputPostingErrorV0.unavailable }
            try validate(envelope, deadline: beforeDeadlineNanoseconds)
            try await executor(beforeDeadlineNanoseconds) {
                try invocation.run {
                    // Window activation and backend inspection may have suspended
                    // since the initial scope check. Validate at the actual post.
                    try self.admission.perform {
                        try self.validate(envelope, deadline: beforeDeadlineNanoseconds)
                        try batch()
                    }
                }
            }
            try invocation.finish()
        } onCancel: { invocation.invalidate() }
    }

    private func validate(_ envelope: InteractiveInputEnvelope, deadline: UInt64) throws {
        try envelope.validate()
        guard envelope.interactiveSessionID.rawValue == binding.interactiveSessionID,
              envelope.authorizationEpoch.rawValue == UInt64(binding.authorizationEpoch),
              envelope.surfaceID.rawValue == surface.surfaceID,
              envelope.surfaceRevision.rawValue == UInt64(surface.surfaceRevision),
              envelope.coordinateSpaceRevision.rawValue == UInt64(surface.coordinateSpaceRevision) else {
            throw InteractiveRuntimeNativeInputPostingErrorV0.bindingMismatch
        }
        let current = now()
        guard current >= initialNow, current < deadline,
              current / 1_000_000 < binding.expiresAtMonotonicMilliseconds else {
            throw InteractiveRuntimeNativeInputPostingErrorV0.expired
        }
    }

    private final class Admission: @unchecked Sendable {
        private let lock = NSLock()
        private var revoked = false
        var isRevoked: Bool { lock.withLock { revoked } }
        func revoke() { lock.withLock { revoked = true } }
        func perform(_ body: () throws -> Void) throws {
            try lock.withLock {
                guard !revoked else { throw InteractiveRuntimeNativeInputPostingErrorV0.unavailable }
                try body()
            }
        }
    }

    private final class Invocation: @unchecked Sendable {
        private let lock = NSLock()
        private var active = true, started = false, succeeded = false
        private var failure: (any Error)?
        func run(_ batch: () throws -> Void) throws {
            try lock.withLock {
                guard active, !started else { throw InteractiveRuntimeNativeInputPostingErrorV0.unavailable }
                started = true
                do { try batch(); succeeded = true }
                catch { failure = error; throw error }
            }
        }
        func invalidate() { lock.withLock { active = false } }
        func finish() throws {
            try lock.withLock {
                active = false
                if let failure { throw failure }
                guard succeeded else { throw InteractiveRuntimeNativeInputPostingErrorV0.notPosted }
            }
        }
    }
}
