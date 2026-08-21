import CompanionWire
import Foundation

public enum LocalAgentStatusWireCodecErrorV1: Error, Equatable, Sendable {
    case emptyPayload
    case payloadTooLarge
    case nonCanonicalPayload
    case invalidSnapshot
}

/// Closed, content-free encoding used only after local peer authentication and
/// method authorization have succeeded. Exact canonical re-encoding rejects
/// unknown members that synthesized `Decodable` implementations would ignore.
public enum LocalAgentStatusWireCodecV1 {
    public static let maximumEncodedBytes = 4_096

    public static func encode(
        _ snapshot: LocalAgentStatusSnapshot
    ) throws -> Data {
        do {
            try snapshot.validate()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(snapshot)
            guard !data.isEmpty else {
                throw LocalAgentStatusWireCodecErrorV1.emptyPayload
            }
            guard data.count <= maximumEncodedBytes else {
                throw LocalAgentStatusWireCodecErrorV1.payloadTooLarge
            }
            let parsed = try CanonicalJSON.parse(data)
            try CanonicalJSON.validate(parsed)
            guard CanonicalJSON.canonicalData(for: parsed) == data else {
                throw LocalAgentStatusWireCodecErrorV1.nonCanonicalPayload
            }
            return data
        } catch let error as LocalAgentStatusWireCodecErrorV1 {
            throw error
        } catch {
            throw LocalAgentStatusWireCodecErrorV1.invalidSnapshot
        }
    }

    public static func decode(_ data: Data) throws -> LocalAgentStatusSnapshot {
        guard !data.isEmpty else {
            throw LocalAgentStatusWireCodecErrorV1.emptyPayload
        }
        guard data.count <= maximumEncodedBytes else {
            throw LocalAgentStatusWireCodecErrorV1.payloadTooLarge
        }
        do {
            try StrictJSON.validate(data)
            let parsed = try CanonicalJSON.parse(data)
            try CanonicalJSON.validate(parsed)
            guard CanonicalJSON.canonicalData(for: parsed) == data else {
                throw LocalAgentStatusWireCodecErrorV1.nonCanonicalPayload
            }
            let snapshot = try JSONDecoder().decode(
                LocalAgentStatusSnapshot.self,
                from: data
            )
            try snapshot.validate()
            guard try encode(snapshot) == data else {
                throw LocalAgentStatusWireCodecErrorV1.nonCanonicalPayload
            }
            return snapshot
        } catch let error as LocalAgentStatusWireCodecErrorV1 {
            throw error
        } catch {
            throw LocalAgentStatusWireCodecErrorV1.invalidSnapshot
        }
    }
}
