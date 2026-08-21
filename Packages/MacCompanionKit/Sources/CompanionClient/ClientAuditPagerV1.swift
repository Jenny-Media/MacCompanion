import CompanionWire
import Foundation

public enum ClientAuditPagerStateV1: String, Equatable, Sendable {
    case idle
    case awaitingPage
    case readyForContinuation
    case exhausted
    case invalidated
}

public enum ClientAuditPagerErrorV1: Error, Equatable, Sendable {
    case invalidState(ClientAuditPagerStateV1)
    case invalidCorrelation
    case unexpectedMessage(WireMessageKind)
    case cursorViolation
}

/// Owns only audit page correlation and cursor continuity. It deliberately
/// does not accumulate an unbounded history or infer that an empty page means
/// no activity; each validated page retains its scoped gap metadata.
public struct ClientAuditPagerV1: Sendable {
    public private(set) var state: ClientAuditPagerStateV1 = .idle
    public private(set) var nextBeforeSequence: Int64?

    private var pendingMessageID: WireUUID?
    private var pendingBeforeSequence: Int64?

    public init() {}

    public mutating func requestNextPage(
        messageID: WireUUID,
        limit: UInt8,
        sentAtUnixMilliseconds: Int64
    ) throws -> Data {
        let before: Int64?
        switch state {
        case .idle:
            before = nil
        case .readyForContinuation:
            guard let nextBeforeSequence else {
                invalidate()
                throw ClientAuditPagerErrorV1.cursorViolation
            }
            before = nextBeforeSequence
        case .awaitingPage, .exhausted, .invalidated:
            throw ClientAuditPagerErrorV1.invalidState(state)
        }
        let envelope = try WireEnvelope(
            messageID: messageID,
            correlationID: nil,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: AuditListRequestBodyV1(
                beforeSequence: before,
                limit: limit
            )
        )
        pendingMessageID = messageID
        pendingBeforeSequence = before
        state = .awaitingPage
        return try WireCodec.encode(envelope)
    }

    @discardableResult
    public mutating func acceptPage(
        _ responseJSON: Data
    ) throws -> AuditListResponseBodyV1 {
        guard state == .awaitingPage else {
            throw ClientAuditPagerErrorV1.invalidState(state)
        }
        do {
            let kind = try WireCodec.messageKind(from: responseJSON)
            guard kind == .auditListResponse else {
                throw ClientAuditPagerErrorV1.unexpectedMessage(kind)
            }
            let response = try WireCodec.decode(
                WireEnvelope<AuditListResponseBodyV1>.self,
                from: responseJSON
            )
            guard response.correlationID == pendingMessageID else {
                throw ClientAuditPagerErrorV1.invalidCorrelation
            }
            if let pendingBeforeSequence {
                guard response.body.events.allSatisfy({
                    $0.sequence < pendingBeforeSequence
                }),
                response.body.nextBeforeSequence.map({
                    $0 < pendingBeforeSequence
                }) ?? true else {
                    throw ClientAuditPagerErrorV1.cursorViolation
                }
            }
            pendingMessageID = nil
            pendingBeforeSequence = nil
            nextBeforeSequence = response.body.nextBeforeSequence
            state = nextBeforeSequence == nil
                ? .exhausted
                : .readyForContinuation
            return response.body
        } catch {
            invalidate()
            throw error
        }
    }

    public mutating func reset() {
        state = .idle
        nextBeforeSequence = nil
        pendingMessageID = nil
        pendingBeforeSequence = nil
    }

    public mutating func invalidate() {
        state = .invalidated
        nextBeforeSequence = nil
        pendingMessageID = nil
        pendingBeforeSequence = nil
    }
}
