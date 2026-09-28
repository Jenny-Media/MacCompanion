import Foundation

public struct WireVersion: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case major
        case minor
    }

    public let major: UInt16
    public let minor: UInt16

    public init(major: UInt16 = 0, minor: UInt16 = 1) {
        self.major = major
        self.minor = minor
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["major", "minor"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        major = try container.decode(UInt16.self, forKey: .major)
        minor = try container.decode(UInt16.self, forKey: .minor)
        guard major == 0, minor == 1 else {
            throw WireError.unsupportedVersion(major: major, minor: minor)
        }
    }
}

public struct WireUUID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue.uuidString.lowercased()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard text.utf8.count == 36,
              text == text.lowercased(),
              let value = UUID(uuidString: text),
              value.uuidString.lowercased() == text else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "expected lowercase canonical UUID"
            )
        }
        rawValue = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public enum WireChannel: String, Codable, Sendable {
    case command
    case events
}

public enum WireMessageKind: String, Codable, CaseIterable, Sendable {
    case authHello = "auth.hello"
    case authChallenge = "auth.challenge"
    case authProof = "auth.proof"
    case sessionDescribeResponse = "session.describe.response"
    case routeObservation = "route.observation"
    case routeObservationAck = "route.observation.ack"
    case pairingBegin = "pairing.begin"
    case pairingChallenge = "pairing.challenge"
    case pairingProve = "pairing.prove"
    case pairingPendingApproval = "pairing.pendingApproval"
    case pairingComplete = "pairing.complete"
    case pairingResume = "pairing.resume"
    case pairingResumeChallenge = "pairing.resumeChallenge"
    case pairingResumeProve = "pairing.resumeProve"
    case statusSnapshotRequest = "status.snapshot.request"
    case statusSnapshotResponse = "status.snapshot.response"
    case capabilityRegistryRequest = "capability.registry.request"
    case capabilityRegistryResponse = "capability.registry.response"
    case auditListRequest = "audit.list.request"
    case auditListResponse = "audit.list.response"
    case keepalivePing = "keepalive.ping"
    case keepalivePong = "keepalive.pong"
    case interactiveDisplayCatalogRequest =
        "interactive.display.catalog.request"
    case interactiveDisplayCatalogResponse =
        "interactive.display.catalog.response"
    case interactiveDisplaySelect = "interactive.display.select"
    case interactiveDisplaySelected = "interactive.display.selected"
    case interactiveSessionRequest = "interactive.session.request"
    case interactiveSessionApprovalRequired = "interactive.session.approvalRequired"
    case interactiveSessionApprove = "interactive.session.approve"
    case interactiveSessionAccepted = "interactive.session.accepted"
    case interactiveSessionEnd = "interactive.session.end"
    case interactiveSessionEnded = "interactive.session.ended"
    case interactiveMediaOfferRequest = "interactive.media.offer.request"
    case interactiveMediaOffer = "interactive.media.offer"
    case interactiveMediaAnswer = "interactive.media.answer"
    case interactiveMediaReady = "interactive.media.ready"
    case nativeEnrollRequest = "interactive.native.enroll.request"
    case nativeEnrollChallenge = "interactive.native.enroll.challenge"
    case nativeEnrollProof = "interactive.native.enroll.proof"
    case nativeReady = "interactive.native.ready"
    case nativePresentRequest = "interactive.native.present.request"
    case nativePresentReceipt = "interactive.native.present.receipt"
    case nativeCancel = "interactive.native.cancel"
    case nativeCancelled = "interactive.native.cancelled"
    case interactiveInitialSurfaceRequest = "interactive.surface.initial.request"
    case interactiveInitialSurfaceDescriptor = "interactive.surface.initial.descriptor"
    case interactiveInitialSurfaceAcknowledgement = "interactive.surface.initial.ack"
    case interactiveInitialSurfaceAcknowledged = "interactive.surface.initial.acknowledged"
    case interactiveSurfaceTargetsRequest = "interactive.surface.targets.request"
    case interactiveSurfaceTargetsResponse = "interactive.surface.targets.response"
    case interactiveSurfaceSelect = "interactive.surface.select"
    case interactiveSurfaceSelected = "interactive.surface.selected"
    case interactiveSurfaceAcknowledgement = "interactive.surface.ack"
    case interactiveSurfaceAcknowledged = "interactive.surface.acknowledged"
    case interactiveSurfaceFocusChanged = "interactive.surface.focusChanged"
    case operationInvoke = "operation.invoke"
    case operationApprovalRequired = "operation.approvalRequired"
    case operationApprove = "operation.approve"
    case operationStatusRequest = "operation.status.request"
    case operationStatusResponse = "operation.status.response"
    case operationCancel = "operation.cancel"
    case error
}

public protocol WireBody: Codable, Equatable, Sendable {
    static var kind: WireMessageKind { get }
    func validate() throws
}

public struct WireEnvelope<Body: WireBody>: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case version
        case messageID
        case correlationID
        case channel
        case kind
        case sentAtUnixMilliseconds
        case body
    }

    public let version: WireVersion
    public let messageID: WireUUID
    public let correlationID: WireUUID?
    public let channel: WireChannel
    public let kind: WireMessageKind
    public let sentAtUnixMilliseconds: Int64
    public let body: Body

    public init(
        version: WireVersion = .init(),
        messageID: WireUUID,
        correlationID: WireUUID?,
        channel: WireChannel = .command,
        sentAtUnixMilliseconds: Int64,
        body: Body
    ) throws {
        self.version = version
        self.messageID = messageID
        self.correlationID = correlationID
        self.channel = channel
        self.kind = Body.kind
        self.sentAtUnixMilliseconds = sentAtUnixMilliseconds
        self.body = body
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(messageID, forKey: .messageID)
        if let correlationID {
            try container.encode(correlationID, forKey: .correlationID)
        } else {
            try container.encodeNil(forKey: .correlationID)
        }
        try container.encode(channel, forKey: .channel)
        try container.encode(kind, forKey: .kind)
        try container.encode(sentAtUnixMilliseconds, forKey: .sentAtUnixMilliseconds)
        try container.encode(body, forKey: .body)
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "version", "messageID", "correlationID", "channel",
                "kind", "sentAtUnixMilliseconds", "body",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(WireVersion.self, forKey: .version)
        messageID = try container.decode(WireUUID.self, forKey: .messageID)
        correlationID = try container.decodeIfPresent(WireUUID.self, forKey: .correlationID)
        channel = try container.decode(WireChannel.self, forKey: .channel)
        kind = try container.decode(WireMessageKind.self, forKey: .kind)
        sentAtUnixMilliseconds = try container.decode(Int64.self, forKey: .sentAtUnixMilliseconds)
        body = try container.decode(Body.self, forKey: .body)
        try validate()
    }

    private func validate() throws {
        guard kind == Body.kind else {
            throw WireError.kindMismatch(
                expected: Body.kind.rawValue,
                actual: kind.rawValue
            )
        }
        guard sentAtUnixMilliseconds >= 0,
              sentAtUnixMilliseconds <= WireLimits.maximumSafeInteger else {
            throw WireError.boundsExceeded(
                field: "sentAtUnixMilliseconds",
                limit: Int(WireLimits.maximumSafeInteger)
            )
        }
        switch channel {
        case .events:
            guard kind == .interactiveSurfaceFocusChanged,
                  correlationID == nil else {
                throw WireError.invalidFrame(
                    reason: "invalid event kind or correlation"
                )
            }
        case .command:
            guard kind != .interactiveSurfaceFocusChanged else {
                throw WireError.invalidFrame(reason: "event on command channel")
            }
            switch kind {
            case .authHello, .pairingBegin, .pairingResume, .routeObservation,
                 .statusSnapshotRequest,
                 .capabilityRegistryRequest, .auditListRequest, .keepalivePing,
                 .interactiveDisplayCatalogRequest,
                 .interactiveDisplaySelect,
                 .interactiveSessionRequest, .interactiveSessionEnd,
                 .interactiveMediaOfferRequest, .interactiveMediaAnswer,
                 .nativeEnrollRequest, .nativeEnrollProof, .nativePresentRequest, .nativeCancel,
                 .operationInvoke, .operationApprove,
                 .operationStatusRequest, .operationCancel,
                 .interactiveInitialSurfaceRequest,
                 .interactiveInitialSurfaceAcknowledgement,
                 .interactiveSurfaceTargetsRequest,
                 .interactiveSurfaceSelect,
                 .interactiveSurfaceAcknowledgement:
                guard correlationID == nil else {
                    throw WireError.invalidFrame(
                        reason: "original request must have null correlationID"
                    )
                }
            case .error:
                break
            default:
                guard correlationID != nil else {
                    throw WireError.invalidFrame(
                        reason: "reply must have correlationID"
                    )
                }
            }
        }
        try body.validate()
    }
}

public enum WireCodec {
    /// Parses only the closed envelope fields needed for connection-scoped
    /// request/reply routing. The path owner must still decode the exact body.
    public static func routingMetadata(
        from data: Data
    ) throws -> WireRoutingMetadata {
        try WireRoutingMetadata(data: data)
    }

    public static func messageKind(from data: Data) throws -> WireMessageKind {
        guard case let .object(members) = try CanonicalJSON.parse(data),
              let member = members.first(where: { $0.key == "kind" }),
              case let .string(rawKind) = member.value else {
            throw WireError.invalidFrame(reason: "missing message kind")
        }
        guard let kind = WireMessageKind(rawValue: rawKind) else {
            throw WireError.unknownKind(rawKind)
        }
        return kind
    }

    public static func decode<Body: WireBody>(
        _ type: WireEnvelope<Body>.Type,
        from data: Data
    ) throws -> WireEnvelope<Body> {
        try StrictJSON.validate(data)
        return try JSONDecoder().decode(type, from: data)
    }

    public static func encode<Body: WireBody>(
        _ envelope: WireEnvelope<Body>
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard data.count <= WireLimits.maximumFrameBytes else {
            throw WireError.boundsExceeded(
                field: "frame",
                limit: WireLimits.maximumFrameBytes
            )
        }
        return data
    }
}

public struct WireRoutingMetadata: Equatable, Sendable {
    public let messageID: WireUUID
    public let correlationID: WireUUID?
    public let channel: WireChannel
    public let kind: WireMessageKind
    public let sentAtUnixMilliseconds: Int64

    fileprivate init(data: Data) throws {
        guard case let .object(members) = try CanonicalJSON.parse(data),
              Set(members.map(\.key)) == [
                  "version", "messageID", "correlationID", "channel",
                  "kind", "sentAtUnixMilliseconds", "body",
              ] else {
            throw WireError.invalidFrame(reason: "invalid routing envelope")
        }
        func value(_ key: String) -> CanonicalJSONValue? {
            members.first(where: { $0.key == key })?.value
        }
        guard case let .object(versionMembers) = value("version"),
              Set(versionMembers.map(\.key)) == ["major", "minor"],
              versionMembers.first(where: { $0.key == "major" })?.value
                == .integer(0),
              versionMembers.first(where: { $0.key == "minor" })?.value
                == .integer(1),
              case let .string(rawChannel) = value("channel"),
              let parsedChannel = WireChannel(rawValue: rawChannel),
              case let .string(rawMessageID) = value("messageID"),
              let parsedMessageID = Self.canonicalUUID(rawMessageID),
              case let .string(rawKind) = value("kind"),
              let parsedKind = WireMessageKind(rawValue: rawKind),
              case let .integer(parsedTime) = value(
                "sentAtUnixMilliseconds"
              ),
              (0...WireLimits.maximumSafeInteger).contains(parsedTime),
              case .object = value("body") else {
            throw WireError.invalidFrame(reason: "invalid routing envelope")
        }
        let parsedCorrelationID: WireUUID?
        switch value("correlationID") {
        case .null:
            parsedCorrelationID = nil
        case let .string(rawCorrelationID):
            guard let value = Self.canonicalUUID(rawCorrelationID) else {
                throw WireError.invalidFrame(
                    reason: "invalid routing correlation"
                )
            }
            parsedCorrelationID = value
        default:
            throw WireError.invalidFrame(reason: "invalid routing correlation")
        }
        switch parsedChannel {
        case .events:
            guard parsedKind == .interactiveSurfaceFocusChanged,
                  parsedCorrelationID == nil else {
                throw WireError.invalidFrame(
                    reason: "invalid event kind or correlation"
                )
            }
        case .command:
            guard parsedKind != .interactiveSurfaceFocusChanged else {
                throw WireError.invalidFrame(
                    reason: "event on command channel"
                )
            }
            switch parsedKind {
            case .authHello, .pairingBegin, .pairingResume, .routeObservation,
                 .statusSnapshotRequest, .capabilityRegistryRequest,
                 .auditListRequest, .keepalivePing,
                 .interactiveDisplayCatalogRequest,
                 .interactiveDisplaySelect,
                 .interactiveSessionRequest, .interactiveSessionEnd,
                 .interactiveMediaOfferRequest, .interactiveMediaAnswer,
                 .nativeEnrollRequest, .nativeEnrollProof, .nativePresentRequest, .nativeCancel,
                 .operationInvoke, .operationApprove,
                 .operationStatusRequest, .operationCancel,
                 .interactiveInitialSurfaceRequest,
                 .interactiveInitialSurfaceAcknowledgement,
                 .interactiveSurfaceTargetsRequest,
                 .interactiveSurfaceSelect,
                 .interactiveSurfaceAcknowledgement:
                guard parsedCorrelationID == nil else {
                    throw WireError.invalidFrame(
                        reason: "original request must have null correlationID"
                    )
                }
            case .error:
                break
            default:
                guard parsedCorrelationID != nil else {
                    throw WireError.invalidFrame(
                        reason: "reply must have correlationID"
                    )
                }
            }
        }
        messageID = parsedMessageID
        correlationID = parsedCorrelationID
        channel = parsedChannel
        kind = parsedKind
        sentAtUnixMilliseconds = parsedTime
    }

    private static func canonicalUUID(_ text: String) -> WireUUID? {
        guard text.utf8.count == 36,
              text == text.lowercased(),
              let value = UUID(uuidString: text),
              value.uuidString.lowercased() == text else {
            return nil
        }
        return WireUUID(value)
    }
}
