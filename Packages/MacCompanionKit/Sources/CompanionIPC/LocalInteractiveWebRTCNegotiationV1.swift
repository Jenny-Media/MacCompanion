import CompanionInteractiveWire
import Foundation

public enum LocalInteractiveWebRTCNegotiationErrorV1:
    Error, Equatable, Sendable
{
    case invalidBinding
}

/// Agent-to-menu request issued only through a generation-bound local XPC
/// endpoint after the authenticated primary validates the same fence.
public struct LocalInteractiveWebRTCOfferCommandV1:
    Codable, Equatable, Sendable
{
    public let commandID: UUID
    public let fence: InteractiveWebRTCNegotiationFenceV0

    public init(commandID: UUID,
                fence: InteractiveWebRTCNegotiationFenceV0) throws {
        try fence.validate()
        self.commandID = commandID
        self.fence = fence
    }
}

public struct LocalInteractiveWebRTCOfferReceiptV1:
    Codable, Equatable, Sendable
{
    public let correlationID: UUID
    public let offer: InteractiveWebRTCOfferBodyV0

    public init(correlationID: UUID,
                offer: InteractiveWebRTCOfferBodyV0) throws {
        try offer.validate()
        self.correlationID = correlationID
        self.offer = offer
    }

    public func validate(
        against command: LocalInteractiveWebRTCOfferCommandV1
    ) throws {
        guard correlationID == command.commandID,
              offer.fence == command.fence else {
            throw LocalInteractiveWebRTCNegotiationErrorV1.invalidBinding
        }
        try offer.validate()
    }
}

public struct LocalInteractiveWebRTCAnswerCommandV1:
    Codable, Equatable, Sendable
{
    public let commandID: UUID
    public let answer: InteractiveWebRTCAnswerBodyV0

    public init(commandID: UUID,
                answer: InteractiveWebRTCAnswerBodyV0) throws {
        try answer.validate()
        self.commandID = commandID
        self.answer = answer
    }
}

public struct LocalInteractiveWebRTCCloseCommandV1:
    Codable, Equatable, Sendable
{
    public let commandID: UUID
    public let interactiveSessionID: UUID

    public init(commandID: UUID, interactiveSessionID: UUID) {
        self.commandID = commandID
        self.interactiveSessionID = interactiveSessionID
    }
}
