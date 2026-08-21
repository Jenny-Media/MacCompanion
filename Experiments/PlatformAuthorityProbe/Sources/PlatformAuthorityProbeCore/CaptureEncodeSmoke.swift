import CompanionHostPlatform
import CoreGraphics
import Foundation
import ScreenCaptureKit

public enum PlatformAuthorityProbeCommand: Equatable, Sendable {
    case preflight
    case enumerateShareableContent
    case captureEncodeSmoke

    public static func parse(_ arguments: [String]) throws -> Self {
        switch arguments {
        case [], ["--preflight"]:
            return .preflight
        case ["--enumerate-shareable-content"]:
            return .enumerateShareableContent
        case ["--capture-encode-smoke"]:
            return .captureEncodeSmoke
        default:
            throw PlatformAuthorityProbeCommandError.invalidArguments
        }
    }
}

public enum PlatformAuthorityProbeCommandError: Error, Equatable, Sendable {
    case invalidArguments
}

public enum CaptureEncodeSmokeResult: String, Codable, Equatable, Sendable {
    case succeeded
    case permissionNotGranted
    case mainDisplayUnavailable
    case graphConstructionFailed
    case captureStartFailed
    case captureStopFailed
    case invalidEncodedSample
    case captureStoppedBySystem
    case invalidCaptureSample
    case encoderRejectedFrame
    case encoderTerminated
    case encodeSubmissionFailed
    case encodeCallbackFailed
    case requiredCleanKeyframeMissing
    case outputRejected
    case sourceSequenceExhausted
    case timedOut
    case cancelled
    case cleanupFailed
}

public struct CaptureEncodeSmokeReport: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case profile, experimentOnly, operatingSystemVersion, result
        case permissionPreflightGranted, requestedWidth, requestedHeight
        case encodedWidth, encodedHeight, requestedFramesPerSecond
        case completeFrameReceived, h264SampleValidated, cleanKeyframe
        case decoderConfigurationValidated, accessUnitValidated
        case startToFirstEncodedSampleMilliseconds, terminalReason
    }
    public let profile: String
    public let experimentOnly: Bool
    public let operatingSystemVersion: String
    public let result: CaptureEncodeSmokeResult
    public let permissionPreflightGranted: Bool
    public let requestedWidth: Int
    public let requestedHeight: Int
    public let encodedWidth: Int?
    public let encodedHeight: Int?
    public let requestedFramesPerSecond: Int
    public let completeFrameReceived: Bool
    public let h264SampleValidated: Bool
    public let cleanKeyframe: Bool
    public let decoderConfigurationValidated: Bool
    public let accessUnitValidated: Bool
    public let startToFirstEncodedSampleMilliseconds: Int64?
    public let terminalReason: String

    public static func closed(
        result: CaptureEncodeSmokeResult,
        permissionGranted: Bool,
        sample: CaptureEncodeSmokeSampleFacts? = nil,
        elapsedMilliseconds: Int64? = nil,
        terminalReason: String
    ) -> Self {
        let capture = ScreenCaptureKitCaptureProfileV0.initial
        return Self(
            profile: "maccompanion.capture-encode-smoke.v0",
            experimentOnly: true,
            operatingSystemVersion:
                ProcessInfo.processInfo.operatingSystemVersionString,
            result: result,
            permissionPreflightGranted: permissionGranted,
            requestedWidth: capture.width,
            requestedHeight: capture.height,
            encodedWidth: sample?.width,
            encodedHeight: sample?.height,
            requestedFramesPerSecond: capture.framesPerSecond,
            completeFrameReceived: sample?.completeFrameReceived ?? false,
            h264SampleValidated: sample?.h264SampleValidated ?? false,
            cleanKeyframe: sample?.cleanKeyframe ?? false,
            decoderConfigurationValidated:
                sample?.decoderConfigurationValidated ?? false,
            accessUnitValidated: sample?.accessUnitValidated ?? false,
            startToFirstEncodedSampleMilliseconds: elapsedMilliseconds,
            terminalReason: terminalReason
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profile, forKey: .profile)
        try container.encode(experimentOnly, forKey: .experimentOnly)
        try container.encode(
            operatingSystemVersion,
            forKey: .operatingSystemVersion
        )
        try container.encode(result, forKey: .result)
        try container.encode(
            permissionPreflightGranted,
            forKey: .permissionPreflightGranted
        )
        try container.encode(requestedWidth, forKey: .requestedWidth)
        try container.encode(requestedHeight, forKey: .requestedHeight)
        if let encodedWidth {
            try container.encode(encodedWidth, forKey: .encodedWidth)
        } else {
            try container.encodeNil(forKey: .encodedWidth)
        }
        if let encodedHeight {
            try container.encode(encodedHeight, forKey: .encodedHeight)
        } else {
            try container.encodeNil(forKey: .encodedHeight)
        }
        try container.encode(
            requestedFramesPerSecond,
            forKey: .requestedFramesPerSecond
        )
        try container.encode(
            completeFrameReceived,
            forKey: .completeFrameReceived
        )
        try container.encode(
            h264SampleValidated,
            forKey: .h264SampleValidated
        )
        try container.encode(cleanKeyframe, forKey: .cleanKeyframe)
        try container.encode(
            decoderConfigurationValidated,
            forKey: .decoderConfigurationValidated
        )
        try container.encode(
            accessUnitValidated,
            forKey: .accessUnitValidated
        )
        if let startToFirstEncodedSampleMilliseconds {
            try container.encode(
                startToFirstEncodedSampleMilliseconds,
                forKey: .startToFirstEncodedSampleMilliseconds
            )
        } else {
            try container.encodeNil(
                forKey: .startToFirstEncodedSampleMilliseconds
            )
        }
        try container.encode(terminalReason, forKey: .terminalReason)
    }
}

public struct CaptureEncodeSmokeSampleFacts: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let completeFrameReceived: Bool
    public let h264SampleValidated: Bool
    public let cleanKeyframe: Bool
    public let decoderConfigurationValidated: Bool
    public let accessUnitValidated: Bool

    public init(
        width: Int,
        height: Int,
        completeFrameReceived: Bool,
        h264SampleValidated: Bool,
        cleanKeyframe: Bool,
        decoderConfigurationValidated: Bool,
        accessUnitValidated: Bool
    ) {
        self.width = width
        self.height = height
        self.completeFrameReceived = completeFrameReceived
        self.h264SampleValidated = h264SampleValidated
        self.cleanKeyframe = cleanKeyframe
        self.decoderConfigurationValidated = decoderConfigurationValidated
        self.accessUnitValidated = accessUnitValidated
    }

    fileprivate var isAccepted: Bool {
        let profile = ScreenCaptureKitCaptureProfileV0.initial
        return width == profile.width
            && height == profile.height
            && completeFrameReceived
            && h264SampleValidated
            && cleanKeyframe
            && decoderConfigurationValidated
            && accessUnitValidated
    }
}

public enum CaptureEncodeSmokeTerminal: String, Equatable, Sendable {
    case captureStoppedBySystem
    case invalidCaptureSample
    case encoderRejectedFrame
    case encoderTerminated
    case encodeSubmissionFailed
    case encodeCallbackFailed
    case requiredCleanKeyframeMissing
    case outputRejected
    case sourceSequenceExhausted
}

public protocol CaptureEncodeSmokePermissionChecking: Sendable {
    func screenCaptureAccessAlreadyGranted() -> Bool
}

public protocol CaptureEncodeSmokeGraph: Sendable {
    func start() async throws
    func stop() async throws
}

public protocol CaptureEncodeSmokeGraphBuilding: Sendable {
    func makeMainDisplayGraph(
        sample: @escaping @Sendable (CaptureEncodeSmokeSampleFacts) async -> Bool,
        terminal: @escaping @Sendable (CaptureEncodeSmokeTerminal) async -> Void
    ) async throws -> (any CaptureEncodeSmokeGraph)?
}

public protocol CaptureEncodeSmokeMonotonicClock: Sendable {
    func nowMilliseconds() -> Int64
}

public protocol CaptureEncodeSmokeSleeping: Sendable {
    func waitForTimeout() async -> Bool
}

private enum CaptureEncodeSmokeEvent: Sendable {
    case sample(CaptureEncodeSmokeSampleFacts)
    case invalidSample(CaptureEncodeSmokeSampleFacts)
    case terminal(CaptureEncodeSmokeTerminal)
    case timeout
    case cancelled
}

private actor CaptureEncodeSmokeOneShot {
    private var result: CaptureEncodeSmokeEvent?
    private var waiter: CheckedContinuation<CaptureEncodeSmokeEvent, Never>?
    private var pendingInvalidSample: CaptureEncodeSmokeSampleFacts?

    func observe(_ sample: CaptureEncodeSmokeSampleFacts) -> Bool {
        if sample.isAccepted {
            resolve(.sample(sample))
            return true
        }
        if result == nil { pendingInvalidSample = sample }
        return false
    }

    func terminal(_ reason: CaptureEncodeSmokeTerminal) {
        if let pendingInvalidSample {
            resolve(.invalidSample(pendingInvalidSample))
        } else {
            resolve(.terminal(reason))
        }
    }

    func resolve(_ event: CaptureEncodeSmokeEvent) {
        guard result == nil else { return }
        result = event
        waiter?.resume(returning: event)
        waiter = nil
    }

    func wait() async -> CaptureEncodeSmokeEvent {
        if let result { return result }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let result {
                    continuation.resume(returning: result)
                } else if Task.isCancelled {
                    continuation.resume(returning: .cancelled)
                } else {
                    waiter = continuation
                }
            }
        } onCancel: {
            Task { await self.resolve(.cancelled) }
        }
    }

    func resolvedEvent() -> CaptureEncodeSmokeEvent? { result }
}

public struct SystemCaptureEncodeSmokePermissionChecker:
    CaptureEncodeSmokePermissionChecking
{
    public init() {}
    public func screenCaptureAccessAlreadyGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}

public struct SystemCaptureEncodeSmokeClock:
    CaptureEncodeSmokeMonotonicClock
{
    public init() {}
    public func nowMilliseconds() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }
}

public struct FiveSecondCaptureEncodeSmokeSleeper:
    CaptureEncodeSmokeSleeping
{
    public init() {}
    public func waitForTimeout() async -> Bool {
        do {
            try await Task.sleep(for: .seconds(5))
            return true
        } catch {
            return false
        }
    }
}

public struct CaptureEncodeSmokeCoordinator: Sendable {
    private let permission: any CaptureEncodeSmokePermissionChecking
    private let graphs: any CaptureEncodeSmokeGraphBuilding
    private let clock: any CaptureEncodeSmokeMonotonicClock
    private let sleeper: any CaptureEncodeSmokeSleeping

    public init(
        permission: any CaptureEncodeSmokePermissionChecking,
        graphs: any CaptureEncodeSmokeGraphBuilding,
        clock: any CaptureEncodeSmokeMonotonicClock =
            SystemCaptureEncodeSmokeClock(),
        sleeper: any CaptureEncodeSmokeSleeping =
            FiveSecondCaptureEncodeSmokeSleeper()
    ) {
        self.permission = permission
        self.graphs = graphs
        self.clock = clock
        self.sleeper = sleeper
    }

    public func run() async -> CaptureEncodeSmokeReport {
        let granted = permission.screenCaptureAccessAlreadyGranted()
        guard granted else {
            return .closed(
                result: .permissionNotGranted,
                permissionGranted: false,
                terminalReason: "permissionNotGranted"
            )
        }
        let channel = CaptureEncodeSmokeOneShot()
        let graph: any CaptureEncodeSmokeGraph
        do {
            guard let built = try await graphs.makeMainDisplayGraph(
                sample: { facts in
                    await channel.observe(facts)
                },
                terminal: { reason in await channel.terminal(reason) }
            ) else {
                return .closed(
                    result: .mainDisplayUnavailable,
                    permissionGranted: true,
                    terminalReason: "mainDisplayUnavailable"
                )
            }
            graph = built
        } catch {
            return .closed(
                result: .graphConstructionFailed,
                permissionGranted: true,
                terminalReason: "graphConstructionFailed"
            )
        }
        let startedAt = clock.nowMilliseconds()
        do {
            try await graph.start()
        } catch {
            return .closed(
                result: .captureStartFailed,
                permissionGranted: true,
                terminalReason: "captureStartFailed"
            )
        }

        await Task.yield()
        let event: CaptureEncodeSmokeEvent
        if let alreadyResolved = await channel.resolvedEvent() {
            event = alreadyResolved
        } else {
            event = await withTaskGroup(
                of: CaptureEncodeSmokeEvent.self,
                returning: CaptureEncodeSmokeEvent.self
            ) { group in
                group.addTask { await channel.wait() }
                group.addTask {
                    await sleeper.waitForTimeout() ? .timeout : .cancelled
                }
                let first = await group.next() ?? .cancelled
                group.cancelAll()
                return first
            }
        }
        switch event {
        case let .sample(sample):
            do {
                try await graph.stop()
            } catch {
                return .closed(
                    result: .captureStopFailed,
                    permissionGranted: true,
                    sample: sample,
                    elapsedMilliseconds: elapsed(since: startedAt),
                    terminalReason: "captureStopFailed"
                )
            }
            return .closed(
                result: .succeeded,
                permissionGranted: true,
                sample: sample,
                elapsedMilliseconds: elapsed(since: startedAt),
                terminalReason: "validatedSample"
            )
        case let .invalidSample(sample):
            return .closed(
                result: .invalidEncodedSample,
                permissionGranted: true,
                sample: sample,
                terminalReason: "invalidEncodedSample"
            )
        case let .terminal(reason):
            return .closed(
                result: result(for: reason),
                permissionGranted: true,
                terminalReason: reason.rawValue
            )
        case .timeout, .cancelled:
            do {
                try await graph.stop()
            } catch {
                return .closed(
                    result: .cleanupFailed,
                    permissionGranted: true,
                    terminalReason: "cleanupFailed"
                )
            }
            let cancelled: Bool
            if case .cancelled = event { cancelled = true } else { cancelled = false }
            return .closed(
                result: cancelled ? .cancelled : .timedOut,
                permissionGranted: true,
                terminalReason: cancelled ? "cancelled" : "timedOut"
            )
        }
    }

    private func elapsed(since started: Int64) -> Int64? {
        let ended = clock.nowMilliseconds()
        guard started >= 0, ended >= started else { return nil }
        return ended - started
    }

    private func result(
        for reason: CaptureEncodeSmokeTerminal
    ) -> CaptureEncodeSmokeResult {
        switch reason {
        case .captureStoppedBySystem: .captureStoppedBySystem
        case .invalidCaptureSample: .invalidCaptureSample
        case .encoderRejectedFrame: .encoderRejectedFrame
        case .encoderTerminated: .encoderTerminated
        case .encodeSubmissionFailed: .encodeSubmissionFailed
        case .encodeCallbackFailed: .encodeCallbackFailed
        case .requiredCleanKeyframeMissing: .requiredCleanKeyframeMissing
        case .outputRejected: .outputRejected
        case .sourceSequenceExhausted: .sourceSequenceExhausted
        }
    }
}

private final class CaptureEncodeSmokeEncoderRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var owner: ScreenCaptureKitStreamOwnerV0?
    private var reason: VideoToolboxH264EncoderTerminationReasonV0?

    func bind(_ owner: ScreenCaptureKitStreamOwnerV0) {
        lock.withLock { self.owner = owner }
    }

    func encoderTerminated(
        _ reason: VideoToolboxH264EncoderTerminationReasonV0
    ) {
        let current = lock.withLock {
            self.reason = reason
            return owner
        }
        guard let current else { return }
        Task { await current.encoderTerminated() }
    }

    func terminalReason() -> VideoToolboxH264EncoderTerminationReasonV0? {
        lock.withLock { reason }
    }
}

private struct ProductionCaptureEncodeSmokeGraph: CaptureEncodeSmokeGraph {
    let owner: ScreenCaptureKitStreamOwnerV0
    func start() async throws { try await owner.start() }
    func stop() async throws { try await owner.stop() }
}

public struct ProductionCaptureEncodeSmokeGraphBuilder:
    CaptureEncodeSmokeGraphBuilding
{
    public init() {}

    public func makeMainDisplayGraph(
        sample: @escaping @Sendable (CaptureEncodeSmokeSampleFacts) async -> Bool,
        terminal: @escaping @Sendable (CaptureEncodeSmokeTerminal) async -> Void
    ) async throws -> (any CaptureEncodeSmokeGraph)? {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: {
            $0.displayID == CGMainDisplayID()
        }) else { return nil }
        let captureProfile = ScreenCaptureKitCaptureProfileV0.initial
        let encoderProfile = VideoToolboxH264EncoderProfileV0.initial
        let compression = try VideoToolboxH264CompressionSessionV0(
            profile: encoderProfile
        )
        let relay = CaptureEncodeSmokeEncoderRelay()
        let encoder = VideoToolboxH264EncoderOwnerV0(
            profile: encoderProfile,
            session: compression,
            output: { encoded in
                await sample(
                    CaptureEncodeSmokeSampleFacts(
                        width: Int(encoded.width),
                        height: Int(encoded.height),
                        completeFrameReceived: true,
                        h264SampleValidated: true,
                        cleanKeyframe: encoded.cleanKeyframe,
                        decoderConfigurationValidated:
                            !encoded.decoderConfiguration.isEmpty,
                        accessUnitValidated: !encoded.accessUnit.isEmpty
                    )
                )
            },
            terminal: { reason in
                if reason != .localStop {
                    relay.encoderTerminated(reason)
                }
            }
        )
        let capture = ScreenCaptureKitStreamingSessionAdapterV0(
            filter: ScreenCaptureKitCaptureConfigurationV0
                .makeDesktopFilter(display: display),
            profile: captureProfile
        )
        let owner = ScreenCaptureKitStreamOwnerV0(
            session: capture,
            encoder: encoder,
            terminal: { reason in
                guard let mapped = CaptureEncodeSmokeTerminal(
                    reason,
                    encoderReason: relay.terminalReason()
                ) else {
                    return
                }
                Task { await terminal(mapped) }
            }
        )
        relay.bind(owner)
        return ProductionCaptureEncodeSmokeGraph(owner: owner)
    }
}

private extension CaptureEncodeSmokeTerminal {
    init?(
        _ reason: ScreenCaptureKitStreamTerminationReasonV0,
        encoderReason: VideoToolboxH264EncoderTerminationReasonV0?
    ) {
        switch reason {
        case .localStop, .captureStartFailed, .captureStopFailed:
            return nil
        case .captureStoppedBySystem: self = .captureStoppedBySystem
        case .invalidCaptureSample: self = .invalidCaptureSample
        case .encoderRejectedFrame: self = .encoderRejectedFrame
        case .encoderTerminated:
            switch encoderReason {
            case .encodeSubmissionFailed: self = .encodeSubmissionFailed
            case .encodeCallbackFailed: self = .encodeCallbackFailed
            case .requiredCleanKeyframeMissing:
                self = .requiredCleanKeyframeMissing
            case .outputRejected: self = .outputRejected
            case .localStop, nil: self = .encoderTerminated
            }
        case .sourceSequenceExhausted: self = .sourceSequenceExhausted
        }
    }
}
