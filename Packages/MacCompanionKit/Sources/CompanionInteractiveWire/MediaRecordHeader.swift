import CompanionDomain
import CompanionInteractiveShared
import Foundation

public enum MediaRecordType: UInt8, CaseIterable, Sendable {
    case decoderConfiguration = 1
    case videoAccessUnit = 2
    case discontinuity = 3
    case end = 4
}

public struct MediaRecordFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let cleanKeyframe = Self(rawValue: 1 << 0)
}

public enum MediaRecordError: Error, Equatable, Sendable {
    case truncated
    case invalidMagic
    case unsupportedVersion(UInt8)
    case unknownRecordType(UInt8)
    case invalidHeaderLength(UInt16)
    case reservedBitsSet
    case invalidFlags
    case invalidRevision
    case invalidDimensions
    case payloadBoundsExceeded
    case invalidPayloadLength
}

public struct MediaRecordHeader: Equatable, Sendable {
    public static let byteCount = 96
    public static let maximumAccessUnitBytes: UInt32 = 8 * 1_024 * 1_024
    public static let maximumConfigurationBytes: UInt32 = 4 * 1_024

    public let type: MediaRecordType
    public let flags: MediaRecordFlags
    public let payloadLength: UInt32
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let surfaceID: UUID
    public let surfaceRevision: SurfaceRevision
    public let coordinateSpaceRevision: CoordinateSpaceRevision
    public let mediaSequence: UInt64
    public let presentationTimeNanoseconds: UInt64
    public let encodedWidth: UInt16
    public let encodedHeight: UInt16

    public init(
        type: MediaRecordType,
        flags: MediaRecordFlags = [],
        payloadLength: UInt32,
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        surfaceID: UUID,
        surfaceRevision: SurfaceRevision,
        coordinateSpaceRevision: CoordinateSpaceRevision,
        mediaSequence: UInt64,
        presentationTimeNanoseconds: UInt64,
        encodedWidth: UInt16,
        encodedHeight: UInt16
    ) throws {
        self.type = type
        self.flags = flags
        self.payloadLength = payloadLength
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.coordinateSpaceRevision = coordinateSpaceRevision
        self.mediaSequence = mediaSequence
        self.presentationTimeNanoseconds = presentationTimeNanoseconds
        self.encodedWidth = encodedWidth
        self.encodedHeight = encodedHeight
        try validate()
    }

    public func encode() -> Data {
        var value = Data()
        value.reserveCapacity(Self.byteCount)
        value.append(contentsOf: [0x4d, 0x43, 0x4d, 0x31]) // MCM1
        value.append(1)
        value.append(type.rawValue)
        value.appendBigEndian(flags.rawValue)
        value.appendBigEndian(UInt16(Self.byteCount))
        value.appendBigEndian(UInt16(0))
        value.appendBigEndian(payloadLength)
        value.appendUUID(interactiveSessionID)
        value.appendBigEndian(authorizationEpoch.rawValue)
        value.appendUUID(surfaceID)
        value.appendBigEndian(surfaceRevision.rawValue)
        value.appendBigEndian(coordinateSpaceRevision.rawValue)
        value.appendBigEndian(mediaSequence)
        value.appendBigEndian(presentationTimeNanoseconds)
        value.appendBigEndian(encodedWidth)
        value.appendBigEndian(encodedHeight)
        value.appendBigEndian(UInt32(0))
        precondition(value.count == Self.byteCount)
        return value
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count >= byteCount else { throw MediaRecordError.truncated }
        let bytes = [UInt8](data.prefix(byteCount))
        guard Array(bytes[0..<4]) == [0x4d, 0x43, 0x4d, 0x31] else {
            throw MediaRecordError.invalidMagic
        }
        guard bytes[4] == 1 else { throw MediaRecordError.unsupportedVersion(bytes[4]) }
        guard let type = MediaRecordType(rawValue: bytes[5]) else {
            throw MediaRecordError.unknownRecordType(bytes[5])
        }
        let flags = MediaRecordFlags(rawValue: readUInt16(bytes, 6))
        let headerLength = readUInt16(bytes, 8)
        guard headerLength == UInt16(byteCount) else {
            throw MediaRecordError.invalidHeaderLength(headerLength)
        }
        guard readUInt16(bytes, 10) == 0, readUInt32(bytes, 92) == 0 else {
            throw MediaRecordError.reservedBitsSet
        }
        return try Self(
            type: type,
            flags: flags,
            payloadLength: readUInt32(bytes, 12),
            interactiveSessionID: readUUID(bytes, 16),
            authorizationEpoch: .init(rawValue: readUInt64(bytes, 32)),
            surfaceID: readUUID(bytes, 40),
            surfaceRevision: .init(rawValue: readUInt64(bytes, 56)),
            coordinateSpaceRevision: .init(rawValue: readUInt64(bytes, 64)),
            mediaSequence: readUInt64(bytes, 72),
            presentationTimeNanoseconds: readUInt64(bytes, 80),
            encodedWidth: readUInt16(bytes, 88),
            encodedHeight: readUInt16(bytes, 90)
        )
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1,
              surfaceRevision.rawValue >= 1,
              coordinateSpaceRevision.rawValue >= 1,
              mediaSequence >= 1 else {
            throw MediaRecordError.invalidRevision
        }
        guard flags.subtracting([.cleanKeyframe]).isEmpty else {
            throw MediaRecordError.reservedBitsSet
        }
        switch type {
        case .decoderConfiguration:
            guard flags.isEmpty else { throw MediaRecordError.invalidFlags }
            guard (1...Self.maximumConfigurationBytes).contains(payloadLength) else {
                throw MediaRecordError.payloadBoundsExceeded
            }
            try validateDimensions()
        case .videoAccessUnit:
            guard (1...Self.maximumAccessUnitBytes).contains(payloadLength) else {
                throw MediaRecordError.payloadBoundsExceeded
            }
            try validateDimensions()
        case .discontinuity, .end:
            guard flags.isEmpty else { throw MediaRecordError.invalidFlags }
            guard payloadLength == 0 else { throw MediaRecordError.invalidPayloadLength }
            guard encodedWidth == 0, encodedHeight == 0 else {
                throw MediaRecordError.invalidDimensions
            }
        }
    }

    private func validateDimensions() throws {
        guard encodedWidth > 0, encodedWidth <= 1_920,
              encodedHeight > 0, encodedHeight <= 1_200,
              UInt64(encodedWidth) * UInt64(encodedHeight) <= 2_304_000 else {
            throw MediaRecordError.invalidDimensions
        }
    }
}

private func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
}

private func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    (0..<4).reduce(0) { ($0 << 8) | UInt32(bytes[offset + $1]) }
}

private func readUInt64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
    (0..<8).reduce(0) { ($0 << 8) | UInt64(bytes[offset + $1]) }
}

private func readUUID(_ bytes: [UInt8], _ offset: Int) -> UUID {
    let value = Array(bytes[offset..<(offset + 16)])
    return UUID(uuid: (
        value[0], value[1], value[2], value[3], value[4], value[5], value[6], value[7],
        value[8], value[9], value[10], value[11], value[12], value[13], value[14], value[15]
    ))
}

private extension Data {
    mutating func appendBigEndian<Value: FixedWidthInteger>(_ value: Value) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendUUID(_ value: UUID) {
        var bytes = value.uuid
        Swift.withUnsafeBytes(of: &bytes) { append(contentsOf: $0) }
    }
}
