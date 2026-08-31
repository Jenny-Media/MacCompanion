import CompanionInteractiveWire
import Foundation

public enum BoundedInteractiveMediaQueueErrorV0: Error, Equatable, Sendable {
    case invalidBounds
}

public struct QueuedInteractiveMediaRecordV0: Equatable, Sendable {
    public let header: MediaRecordHeader
    public let payload: Data

    public init(header: MediaRecordHeader, payload: Data) throws {
        try header.validate()
        guard payload.count == Int(header.payloadLength) else {
            throw InteractiveMenuRuntimeErrorV0.bindingMismatch
        }
        self.header = header
        self.payload = payload
    }
}

/// A small handoff queue for the menu-app runtime. It never drops an older
/// encoded record or breaks decoder continuity. The runtime-facing async path
/// suspends one producer behind bounded capacity while the encoder's own
/// latency policy keeps only its newest not-yet-encoded source frame.
public final class BoundedInteractiveMediaQueueV0:
    InteractiveRuntimeMediaEnqueuingV0, @unchecked Sendable
{
    public static let maximumRecordLimit = 64
    public static let maximumByteLimit = 64 * 1_024 * 1_024

    private let lock = NSLock()
    private let maximumRecords: Int
    private let maximumBytes: Int
    private var records: [QueuedInteractiveMediaRecordV0] = []
    private var byteCount = 0
    private var enqueuedHandler:
        (token: UUID, action: @Sendable () -> Void)?
    private var pendingEnqueue: (
        record: QueuedInteractiveMediaRecordV0,
        continuation: CheckedContinuation<Bool, Never>
    )?

    public init(maximumRecords: Int = 8, maximumBytes: Int = 16 * 1_024 * 1_024) throws {
        guard (1...Self.maximumRecordLimit).contains(maximumRecords),
              (1...Self.maximumByteLimit).contains(maximumBytes) else {
            throw BoundedInteractiveMediaQueueErrorV0.invalidBounds
        }
        self.maximumRecords = maximumRecords
        self.maximumBytes = maximumBytes
    }

    public func enqueueInteractiveMedia(
        header: MediaRecordHeader,
        payload: Data
    ) -> Bool {
        guard let record = try? QueuedInteractiveMediaRecordV0(
            header: header,
            payload: payload
        ) else { return false }
        let result = lock.withLock {
            guard records.count < maximumRecords,
                  payload.count <= maximumBytes - byteCount,
                  records.first.map({
                      $0.header.interactiveSessionID
                        == header.interactiveSessionID
                  }) ?? true else {
                return (false, nil as (@Sendable () -> Void)?)
            }
            records.append(record)
            byteCount += payload.count
            return (true, enqueuedHandler?.action)
        }
        result.1?()
        return result.0
    }

    public func enqueueInteractiveMediaAwaitingCapacity(
        header: MediaRecordHeader,
        payload: Data
    ) async -> Bool {
        guard let record = try? QueuedInteractiveMediaRecordV0(
            header: header,
            payload: payload
        ), payload.count <= maximumBytes else { return false }

        return await withCheckedContinuation { continuation in
            let result = lock.withLock {
                let sameSession = records.first.map {
                    $0.header.interactiveSessionID
                        == header.interactiveSessionID
                } ?? pendingEnqueue.map {
                    $0.record.header.interactiveSessionID
                        == header.interactiveSessionID
                } ?? true
                guard sameSession, pendingEnqueue == nil else {
                    return (false, false, nil as (@Sendable () -> Void)?)
                }
                if records.count < maximumRecords,
                   payload.count <= maximumBytes - byteCount {
                    records.append(record)
                    byteCount += payload.count
                    return (true, true, enqueuedHandler?.action)
                }
                pendingEnqueue = (record, continuation)
                return (true, false, nil)
            }
            guard result.0 else {
                continuation.resume(returning: false)
                return
            }
            if result.1 {
                continuation.resume(returning: true)
                result.2?()
            }
        }
    }

    /// Transfers one complete record to the downstream adapter. A record
    /// already transferred is downstream in-flight and remains fenced by its
    /// header plus channel/session teardown; `purge()` covers retained queue
    /// ownership only.
    public func dequeue() -> QueuedInteractiveMediaRecordV0? {
        let result: (
            QueuedInteractiveMediaRecordV0,
            CheckedContinuation<Bool, Never>?,
            (@Sendable () -> Void)?
        )? = lock.withLock {
            guard !records.isEmpty else { return nil }
            let record = records.removeFirst()
            byteCount -= record.payload.count
            var admitted: CheckedContinuation<Bool, Never>?
            var action: (@Sendable () -> Void)?
            if let pendingEnqueue,
               records.count < maximumRecords,
               pendingEnqueue.record.payload.count
                    <= maximumBytes - byteCount,
               records.first.map({
                   $0.header.interactiveSessionID
                        == pendingEnqueue.record.header.interactiveSessionID
               }) ?? true {
                records.append(pendingEnqueue.record)
                byteCount += pendingEnqueue.record.payload.count
                admitted = pendingEnqueue.continuation
                self.pendingEnqueue = nil
                action = enqueuedHandler?.action
            }
            return (record, admitted, action)
        }
        result?.1?.resume(returning: true)
        result?.2?()
        return result?.0
    }

    @discardableResult
    public func purge() -> Int {
        let result = lock.withLock {
            let removed = records.count
            records.removeAll(keepingCapacity: true)
            byteCount = 0
            let pending = pendingEnqueue?.continuation
            pendingEnqueue = nil
            return (removed, pending)
        }
        result.1?.resume(returning: false)
        return result.0
    }

    public func status() -> (recordCount: Int, byteCount: Int) {
        lock.withLock { (records.count, byteCount) }
    }

    /// Installs the sole downstream wakeup without transferring record
    /// ownership. If records already exist, the handler is invoked after the
    /// lock is released so the drain cannot miss its initial edge.
    public func installEnqueuedHandler(
        token: UUID,
        _ action: @escaping @Sendable () -> Void
    ) -> Bool {
        let shouldSignal = lock.withLock {
            guard enqueuedHandler == nil else { return nil as Bool? }
            enqueuedHandler = (token, action)
            return !records.isEmpty
        }
        guard let shouldSignal else { return false }
        if shouldSignal { action() }
        return true
    }

    public func removeEnqueuedHandler(token: UUID) {
        lock.withLock {
            guard enqueuedHandler?.token == token else { return }
            enqueuedHandler = nil
        }
    }
}

public protocol InteractiveRuntimeRenderedFrameBlankingV0: Sendable {
    func blankRenderedInteractiveFrame() async throws
}

/// Production composition uses this as the runtime's frame controller so
/// queued encoded bytes are purged before rendered content is reported blank.
public struct QueuePurgingInteractiveFrameControllerV0:
    InteractiveRuntimeFrameControllingV0, Sendable
{
    private let queue: BoundedInteractiveMediaQueueV0
    private let renderer: any InteractiveRuntimeRenderedFrameBlankingV0

    public init(
        queue: BoundedInteractiveMediaQueueV0,
        renderer: any InteractiveRuntimeRenderedFrameBlankingV0
    ) {
        self.queue = queue
        self.renderer = renderer
    }

    public func blankLastInteractiveFrame() async throws {
        queue.purge()
        try await renderer.blankRenderedInteractiveFrame()
    }
}
