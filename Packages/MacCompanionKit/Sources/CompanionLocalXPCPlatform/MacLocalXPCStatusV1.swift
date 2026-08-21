#if os(macOS)
import CompanionIPC
import CompanionLocalXPCPlatformC

public enum MacLocalXPCStatusReadErrorV1: Error, Equatable, Sendable {
    case sourceUnavailable
}

public enum MacLocalXPCStatusWireV1 {
    public static let maximumPayloadBytes =
        Int(MCLocalXPCMaximumStatusPayloadBytes)
}

public protocol MacLocalXPCStatusReadingV1: Sendable {
    func readStatus() async
        -> Result<LocalAgentStatusSnapshot, MacLocalXPCStatusReadErrorV1>
}

/// One operation may be active at a time. Monotonic operation identities fence
/// timeout, cancellation, and completion callbacks from later reads.
struct MacLocalXPCStatusReadTransactionGateV1: Sendable {
    private(set) var currentGeneration: UInt64?
    private(set) var currentOperation: UInt64?
    private var nextOperation: UInt64 = 0

    mutating func bind(generation: UInt64) -> Bool {
        guard generation > 0,
              currentGeneration == nil,
              currentOperation == nil else {
            return false
        }
        currentGeneration = generation
        return true
    }

    mutating func begin(
        generation: UInt64,
        permitted: Bool
    ) -> UInt64? {
        guard permitted,
              currentGeneration == generation,
              currentOperation == nil,
              nextOperation < UInt64.max else {
            return nil
        }
        nextOperation += 1
        currentOperation = nextOperation
        return nextOperation
    }

    func admits(
        generation: UInt64,
        operation: UInt64
    ) -> Bool {
        currentGeneration == generation
            && currentOperation == operation
    }

    mutating func finish(
        generation: UInt64,
        operation: UInt64
    ) -> Bool {
        guard admits(generation: generation, operation: operation) else {
            return false
        }
        currentOperation = nil
        return true
    }

    @discardableResult
    mutating func invalidate(generation: UInt64) -> Bool {
        guard currentGeneration == generation else {
            return false
        }
        currentGeneration = nil
        currentOperation = nil
        return true
    }

    mutating func invalidateAll() {
        currentGeneration = nil
        currentOperation = nil
    }
}

/// Retains one incoming XPC request until exactly one terminal path either
/// transfers or releases it. Injected retain/release operations make the
/// ownership contract directly testable without constructing a live service.
@available(macOS 26.0, *)
final class MacLocalXPCStatusRequestLeaseV1<Request>: @unchecked Sendable {
    private var ownedRequest: Request?
    private let releaseRequest: (Request) -> Void

    init(
        request: Request,
        retainRequest: (Request) -> Void,
        releaseRequest: @escaping (Request) -> Void
    ) {
        retainRequest(request)
        ownedRequest = request
        self.releaseRequest = releaseRequest
    }

    func takeOwnedRequest() -> Request? {
        let request = ownedRequest
        ownedRequest = nil
        return request
    }

    func releaseIfOwned() {
        guard let request = takeOwnedRequest() else { return }
        releaseRequest(request)
    }

    deinit {
        releaseIfOwned()
    }
}

@available(macOS 26.0, *)
extension MacLocalXPCStatusRequestLeaseV1
where Request == MCLocalXPCMessageRef {
    convenience init(request: MCLocalXPCMessageRef) {
        self.init(
            request: request,
            retainRequest: MCLocalXPCMessageRetain,
            releaseRequest: MCLocalXPCMessageRelease
        )
    }
}
#endif
