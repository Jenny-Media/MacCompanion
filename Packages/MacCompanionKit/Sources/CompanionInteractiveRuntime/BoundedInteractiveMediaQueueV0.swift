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

/// A small synchronous handoff queue for the menu-app runtime. It never drops
/// an older record to make room: overflow is a definitive rejection so the
/// runtime can terminate rather than silently corrupt decoder continuity.
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
        return lock.withLock {
            guard records.count < maximumRecords,
                  payload.count <= maximumBytes - byteCount,
                  records.first.map({
                      $0.header.interactiveSessionID
                        == header.interactiveSessionID
                  }) ?? true else {
                return false
            }
            records.append(record)
            byteCount += payload.count
            return true
        }
    }

    /// Transfers one complete record to the downstream adapter. A record
    /// already transferred is downstream in-flight and remains fenced by its
    /// header plus channel/session teardown; `purge()` covers retained queue
    /// ownership only.
    public func dequeue() -> QueuedInteractiveMediaRecordV0? {
        lock.withLock {
            guard !records.isEmpty else { return nil }
            let record = records.removeFirst()
            byteCount -= record.payload.count
            return record
        }
    }

    @discardableResult
    public func purge() -> Int {
        lock.withLock {
            let removed = records.count
            records.removeAll(keepingCapacity: true)
            byteCount = 0
            return removed
        }
    }

    public func status() -> (recordCount: Int, byteCount: Int) {
        lock.withLock { (records.count, byteCount) }
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
