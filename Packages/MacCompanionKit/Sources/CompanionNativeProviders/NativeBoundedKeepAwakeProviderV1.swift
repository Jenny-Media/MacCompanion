import CompanionDomain
import CompanionOperations
import CompanionWire
import Foundation

#if os(macOS)
import IOKit.pwr_mgt
#endif

public enum NativeBoundedKeepAwakeCapabilityV1 {
    public static let startCapabilityID =
        "maccompanion.system.startKeepAwake"
    public static let stopCapabilityID =
        "maccompanion.system.stopKeepAwake"
    public static let providerID = "maccompanion.native.power"
    public static let providerVersion = "1.0.0"
    public static let providerGeneration = UUID(
        uuidString: "018f8300-0000-7000-8000-000000000002"
    )!
    public static let executionRevision = UUID(
        uuidString: "018f8400-0000-7000-8000-000000000002"
    )!
    public static let minimumDurationMilliseconds: Int64 = 60_000
    public static let maximumDurationMilliseconds: Int64 = 14_400_000

    public static func descriptors() throws -> [CapabilityDescriptorV1] {
        let until = try CapabilitySchemaPropertyV1(
            name: "untilUnixMilliseconds",
            required: true,
            schema: try .integer(
                minimum: 1,
                maximum: WireLimits.maximumSafeInteger
            )
        )
        let stopped = try CapabilitySchemaPropertyV1(
            name: "stopped",
            required: true,
            schema: .boolean()
        )
        let effects = try CapabilityEffectFacts(
            dataAccess: .none,
            changesLocalState: .reversible,
            mayDisruptUser: true,
            invokesExternalService: false,
            usesCredentials: false,
            destructive: false,
            requiresForegroundSession: false,
            allowedWhileLocked: false,
            cancellation: .notApplicable
        )
        return [
            try CapabilityDescriptorV1(
                capabilityID: startCapabilityID,
                schemaVersion: 1,
                providerID: providerID,
                providerVersion: providerVersion,
                providerGeneration: providerGeneration,
                executionRevision: executionRevision,
                englishTitle: "Start keep awake",
                englishSummary:
                    "Prevent automatic idle system sleep until a bounded time.",
                parameterSchema: .object(properties: [until]),
                resultSchema: .object(properties: [until]),
                effects: effects
            ),
            try CapabilityDescriptorV1(
                capabilityID: stopCapabilityID,
                schemaVersion: 1,
                providerID: providerID,
                providerVersion: providerVersion,
                providerGeneration: providerGeneration,
                executionRevision: executionRevision,
                englishTitle: "Stop keep awake",
                englishSummary:
                    "Release Mac Companion's current keep-awake request.",
                parameterSchema: .object(properties: []),
                resultSchema: .object(properties: [stopped]),
                effects: effects
            ),
        ]
    }
}

public protocol NativeKeepAwakeWallClockV1: Sendable {
    func nowUnixMilliseconds() -> Int64
}

public struct SystemNativeKeepAwakeWallClockV1:
    NativeKeepAwakeWallClockV1
{
    public init() {}

    public func nowUnixMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
    }
}

public enum BoundedKeepAwakeErrorV1: Error, Equatable, Sendable {
    case unavailable
    case rejected
    case executionFailed
    case outcomeUnknown
}

public protocol BoundedKeepAwakeControllingV1: Sendable {
    func start(
        untilUnixMilliseconds: Int64,
        nowUnixMilliseconds: Int64
    ) async throws -> Int64

    func stop(nowUnixMilliseconds: Int64) async throws
}

public protocol KeepAwakeAssertionBackendV1: Sendable {
    func createAssertion(timeoutSeconds: TimeInterval) throws -> UInt32
    func releaseAssertion(_ assertionID: UInt32) throws
}

/// Owns at most one process-scoped IOPM assertion. The system timeout is the
/// safety authority; this actor's deadline exists only for idempotency and
/// avoiding a release of an already-expired assertion.
public actor BoundedKeepAwakeControllerV1:
    BoundedKeepAwakeControllingV1
{
    private struct ActiveAssertion: Sendable {
        let assertionID: UInt32
        let untilUnixMilliseconds: Int64
    }

    private let backend: any KeepAwakeAssertionBackendV1
    private var active: ActiveAssertion?

    public init(backend: any KeepAwakeAssertionBackendV1) {
        self.backend = backend
    }

    public func start(
        untilUnixMilliseconds: Int64,
        nowUnixMilliseconds: Int64
    ) throws -> Int64 {
        guard nowUnixMilliseconds >= 0,
              untilUnixMilliseconds > nowUnixMilliseconds else {
            throw BoundedKeepAwakeErrorV1.rejected
        }
        discardExpired(nowUnixMilliseconds: nowUnixMilliseconds)
        if active?.untilUnixMilliseconds == untilUnixMilliseconds {
            return untilUnixMilliseconds
        }
        let (maximumUntil, overflow) = nowUnixMilliseconds
            .addingReportingOverflow(
                NativeBoundedKeepAwakeCapabilityV1
                    .maximumDurationMilliseconds
            )
        let (minimumUntil, minimumOverflow) = nowUnixMilliseconds
            .addingReportingOverflow(
                NativeBoundedKeepAwakeCapabilityV1
                    .minimumDurationMilliseconds
            )
        guard !overflow,
              !minimumOverflow,
              untilUnixMilliseconds >= minimumUntil,
              untilUnixMilliseconds <= maximumUntil else {
            throw BoundedKeepAwakeErrorV1.rejected
        }
        if let active {
            do {
                try backend.releaseAssertion(active.assertionID)
                self.active = nil
            } catch {
                throw BoundedKeepAwakeErrorV1.outcomeUnknown
            }
        }

        let timeout = TimeInterval(
            untilUnixMilliseconds - nowUnixMilliseconds
        ) / 1_000
        let assertionID: UInt32
        do {
            assertionID = try backend.createAssertion(timeoutSeconds: timeout)
        } catch let error as BoundedKeepAwakeErrorV1 {
            throw error
        } catch {
            throw BoundedKeepAwakeErrorV1.executionFailed
        }
        guard assertionID != 0 else {
            throw BoundedKeepAwakeErrorV1.executionFailed
        }
        active = ActiveAssertion(
            assertionID: assertionID,
            untilUnixMilliseconds: untilUnixMilliseconds
        )
        return untilUnixMilliseconds
    }

    public func stop(nowUnixMilliseconds: Int64) throws {
        guard nowUnixMilliseconds >= 0 else {
            throw BoundedKeepAwakeErrorV1.rejected
        }
        discardExpired(nowUnixMilliseconds: nowUnixMilliseconds)
        guard let active else { return }
        do {
            try backend.releaseAssertion(active.assertionID)
            self.active = nil
        } catch {
            throw BoundedKeepAwakeErrorV1.outcomeUnknown
        }
    }

    private func discardExpired(nowUnixMilliseconds: Int64) {
        if let active,
           nowUnixMilliseconds >= active.untilUnixMilliseconds {
            self.active = nil
        }
    }
}

public struct NativeBoundedKeepAwakeProviderV1: CapabilityProviderV1 {
    public let identity: CapabilityProviderIdentityV1
    private let controller: any BoundedKeepAwakeControllingV1
    private let wallClock: any NativeKeepAwakeWallClockV1

    public init(
        controller: any BoundedKeepAwakeControllingV1,
        wallClock: any NativeKeepAwakeWallClockV1 =
            SystemNativeKeepAwakeWallClockV1()
    ) {
        identity = CapabilityProviderIdentityV1(
            providerID: NativeBoundedKeepAwakeCapabilityV1.providerID,
            providerVersion: NativeBoundedKeepAwakeCapabilityV1.providerVersion,
            providerGeneration:
                NativeBoundedKeepAwakeCapabilityV1.providerGeneration,
            executionRevision:
                NativeBoundedKeepAwakeCapabilityV1.executionRevision
        )
        self.controller = controller
        self.wallClock = wallClock
    }

    public func execute(
        _ request: CapabilityProviderRequestV1
    ) async -> CapabilityProviderOutcomeV1 {
        let now = wallClock.nowUnixMilliseconds()
        guard now >= 0,
              now <= WireLimits.maximumSafeInteger else {
            return .failed(.executionFailed)
        }
        guard request.expiresAtUnixMilliseconds > now else {
            return .failed(.timedOut)
        }
        guard request.expiresAtUnixMilliseconds
                <= WireLimits.maximumSafeInteger else {
            return .failed(.rejected)
        }
        do {
            switch request.capabilityID {
            case NativeBoundedKeepAwakeCapabilityV1.startCapabilityID:
                let until = try startUntil(from: request.parameters)
                guard Self.validUntil(
                    until,
                    nowUnixMilliseconds: now
                ) else {
                    return .failed(.rejected)
                }
                let verified = try await controller.start(
                    untilUnixMilliseconds: until,
                    nowUnixMilliseconds: now
                )
                guard verified == until else { return .failed(.rejected) }
                return .succeeded(resultJSON: Data(
                    "{\"untilUnixMilliseconds\":\(verified)}".utf8
                ))
            case NativeBoundedKeepAwakeCapabilityV1.stopCapabilityID:
                guard request.parameters == .object([]) else {
                    return .failed(.rejected)
                }
                try await controller.stop(nowUnixMilliseconds: now)
                return .succeeded(resultJSON: Data("{\"stopped\":true}".utf8))
            default:
                return .failed(.rejected)
            }
        } catch BoundedKeepAwakeErrorV1.unavailable {
            return .failed(.unavailable)
        } catch BoundedKeepAwakeErrorV1.rejected {
            return .failed(.rejected)
        } catch BoundedKeepAwakeErrorV1.executionFailed {
            return .failed(.executionFailed)
        } catch BoundedKeepAwakeErrorV1.outcomeUnknown {
            return .outcomeUnknown
        } catch {
            return .failed(.executionFailed)
        }
    }

    private func startUntil(
        from parameters: CanonicalJSONValue
    ) throws -> Int64 {
        guard case let .object(members) = parameters,
              members.count == 1,
              members[0].key == "untilUnixMilliseconds",
              case let .integer(until) = members[0].value else {
            throw BoundedKeepAwakeErrorV1.rejected
        }
        return until
    }

    private static func validUntil(
        _ until: Int64,
        nowUnixMilliseconds: Int64
    ) -> Bool {
        let (minimum, minimumOverflow) = nowUnixMilliseconds
            .addingReportingOverflow(
                NativeBoundedKeepAwakeCapabilityV1
                    .minimumDurationMilliseconds
            )
        let (maximum, maximumOverflow) = nowUnixMilliseconds
            .addingReportingOverflow(
                NativeBoundedKeepAwakeCapabilityV1
                    .maximumDurationMilliseconds
            )
        return !minimumOverflow
            && !maximumOverflow
            && until >= minimum
            && until <= maximum
            && until <= WireLimits.maximumSafeInteger
    }
}

#if os(macOS)
public struct IOPMKeepAwakeAssertionBackendV1:
    KeepAwakeAssertionBackendV1
{
    public init() {}

    public func createAssertion(
        timeoutSeconds: TimeInterval
    ) throws -> UInt32 {
        guard timeoutSeconds > 0,
              timeoutSeconds <= TimeInterval(
                NativeBoundedKeepAwakeCapabilityV1
                    .maximumDurationMilliseconds
              ) / 1_000 else {
            throw BoundedKeepAwakeErrorV1.rejected
        }
        var assertionID = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithDescription(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            "Mac Companion Keep Awake" as CFString,
            "Bounded remote keep-awake request" as CFString,
            nil,
            nil,
            timeoutSeconds,
            kIOPMAssertionTimeoutActionRelease as CFString,
            &assertionID
        )
        guard status == kIOReturnSuccess else {
            throw BoundedKeepAwakeErrorV1.executionFailed
        }
        return assertionID
    }

    public func releaseAssertion(_ assertionID: UInt32) throws {
        guard assertionID != 0,
              IOPMAssertionRelease(assertionID) == kIOReturnSuccess else {
            throw BoundedKeepAwakeErrorV1.outcomeUnknown
        }
    }
}

public extension BoundedKeepAwakeControllerV1 {
    static func systemDefault() -> BoundedKeepAwakeControllerV1 {
        BoundedKeepAwakeControllerV1(
            backend: IOPMKeepAwakeAssertionBackendV1()
        )
    }
}
#endif
