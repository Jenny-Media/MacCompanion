import Foundation
import PlatformAuthorityProbeCore
import Testing

private enum SmokeTestError: Error { case injected }

private struct SmokePermission: CaptureEncodeSmokePermissionChecking {
    let granted: Bool
    func screenCaptureAccessAlreadyGranted() -> Bool { granted }
}

private struct SmokeSleeper: CaptureEncodeSmokeSleeping {
    let timeout: Bool
    func waitForTimeout() async -> Bool { timeout }
}

private final class SmokeClock: CaptureEncodeSmokeMonotonicClock,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [Int64]

    init(_ values: [Int64]) { self.values = values }
    func nowMilliseconds() -> Int64 {
        lock.withLock {
            if values.count > 1 { return values.removeFirst() }
            return values.first ?? 0
        }
    }
}

private enum SmokeGraphBehavior: Sendable {
    case idle
    case sample(CaptureEncodeSmokeSampleFacts)
    case terminal(CaptureEncodeSmokeTerminal)
    case startFailure
}

private actor SmokeGraph: CaptureEncodeSmokeGraph {
    let behavior: SmokeGraphBehavior
    let stopFails: Bool
    private var sample:
        (@Sendable (CaptureEncodeSmokeSampleFacts) async -> Bool)?
    private var terminal:
        (@Sendable (CaptureEncodeSmokeTerminal) -> Void)?
    private var starts = 0
    private var stops = 0

    init(behavior: SmokeGraphBehavior, stopFails: Bool = false) {
        self.behavior = behavior
        self.stopFails = stopFails
    }

    func configure(
        sample: @escaping @Sendable (CaptureEncodeSmokeSampleFacts) async -> Bool,
        terminal: @escaping @Sendable (CaptureEncodeSmokeTerminal) -> Void
    ) {
        self.sample = sample
        self.terminal = terminal
    }

    func start() async throws {
        starts += 1
        switch behavior {
        case .idle:
            return
        case let .sample(facts):
            let accepted = await sample?(facts) ?? false
            if !accepted { terminal?(.encoderTerminated) }
        case let .terminal(reason):
            terminal?(reason)
        case .startFailure:
            throw SmokeTestError.injected
        }
    }

    func stop() async throws {
        stops += 1
        if stopFails { throw SmokeTestError.injected }
    }

    func counts() -> (Int, Int) { (starts, stops) }
}

private actor SmokeBuilder: CaptureEncodeSmokeGraphBuilding {
    enum Mode: Sendable { case graph, missing, failure }
    let mode: Mode
    let graph: SmokeGraph
    private var makes = 0

    init(mode: Mode = .graph, graph: SmokeGraph) {
        self.mode = mode
        self.graph = graph
    }

    func makeMainDisplayGraph(
        sample: @escaping @Sendable (CaptureEncodeSmokeSampleFacts) async -> Bool,
        terminal: @escaping @Sendable (CaptureEncodeSmokeTerminal) -> Void
    ) async throws -> (any CaptureEncodeSmokeGraph)? {
        makes += 1
        switch mode {
        case .missing:
            return nil
        case .failure:
            throw SmokeTestError.injected
        case .graph:
            await graph.configure(sample: sample, terminal: terminal)
            return graph
        }
    }

    func makeCount() -> Int { makes }
}

private let validSmokeSample = CaptureEncodeSmokeSampleFacts(
    width: 1_920,
    height: 1_200,
    completeFrameReceived: true,
    h264SampleValidated: true,
    cleanKeyframe: true,
    decoderConfigurationValidated: true,
    accessUnitValidated: true
)

private func smokeCoordinator(
    permission: Bool = true,
    builder: SmokeBuilder,
    timeout: Bool = true,
    clock: [Int64] = [100, 125]
) -> CaptureEncodeSmokeCoordinator {
    CaptureEncodeSmokeCoordinator(
        permission: SmokePermission(granted: permission),
        graphs: builder,
        clock: SmokeClock(clock),
        sleeper: SmokeSleeper(timeout: timeout)
    )
}

@Test func commandParserIsExactAndMutuallyExclusive() throws {
    #expect(try PlatformAuthorityProbeCommand.parse([]) == .preflight)
    #expect(try PlatformAuthorityProbeCommand.parse(["--preflight"])
        == .preflight)
    #expect(try PlatformAuthorityProbeCommand.parse([
        "--enumerate-shareable-content",
    ]) == .enumerateShareableContent)
    #expect(try PlatformAuthorityProbeCommand.parse([
        "--capture-encode-smoke",
    ]) == .captureEncodeSmoke)
    for invalid in [
        ["--preflight", "--capture-encode-smoke"],
        ["--preflight", "--preflight"],
        ["--capture-encode-smoke=true"],
        ["--unknown"],
    ] {
        #expect(throws: PlatformAuthorityProbeCommandError.invalidArguments) {
            _ = try PlatformAuthorityProbeCommand.parse(invalid)
        }
    }
}

@Test func missingPermissionPerformsNoEnumerationOrGraphConstruction()
    async throws
{
    let graph = SmokeGraph(behavior: .idle)
    let builder = SmokeBuilder(graph: graph)
    let report = await smokeCoordinator(
        permission: false,
        builder: builder
    ).run()
    #expect(report.result == .permissionNotGranted)
    #expect(await builder.makeCount() == 0)
    #expect(await graph.counts() == (0, 0))
    let object = try #require(
        JSONSerialization.jsonObject(
            with: JSONEncoder().encode(report)
        ) as? [String: Any]
    )
    #expect(object.keys.count == 17)
    #expect(object["encodedWidth"] is NSNull)
    #expect(object["startToFirstEncodedSampleMilliseconds"] is NSNull)
}

@Test func missingMainDisplayAndConstructionFailureStayClosed() async {
    let missingGraph = SmokeGraph(behavior: .idle)
    let missing = await smokeCoordinator(
        builder: SmokeBuilder(mode: .missing, graph: missingGraph)
    ).run()
    #expect(missing.result == .mainDisplayUnavailable)
    #expect(await missingGraph.counts() == (0, 0))

    let failedGraph = SmokeGraph(behavior: .idle)
    let failed = await smokeCoordinator(
        builder: SmokeBuilder(mode: .failure, graph: failedGraph)
    ).run()
    #expect(failed.result == .graphConstructionFailed)
    #expect(await failedGraph.counts() == (0, 0))
}

@Test func firstExactCleanSampleSucceedsAndStopsExactlyOnce() async throws {
    let graph = SmokeGraph(behavior: .sample(validSmokeSample))
    let report = await smokeCoordinator(
        builder: SmokeBuilder(graph: graph)
    ).run()
    #expect(report.result == .succeeded)
    #expect(report.encodedWidth == 1_920)
    #expect(report.encodedHeight == 1_200)
    #expect(report.startToFirstEncodedSampleMilliseconds == 25)
    #expect(await graph.counts() == (1, 1))

    let data = try JSONEncoder().encode(report)
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(Set(object.keys) == [
        "accessUnitValidated", "cleanKeyframe", "completeFrameReceived",
        "decoderConfigurationValidated", "encodedHeight", "encodedWidth",
        "experimentOnly", "h264SampleValidated", "operatingSystemVersion",
        "permissionPreflightGranted", "profile", "requestedFramesPerSecond",
        "requestedHeight", "requestedWidth", "result",
        "startToFirstEncodedSampleMilliseconds", "terminalReason",
    ])
    #expect(!String(decoding: data, as: UTF8.self).contains("accessUnit" + ":"))
}

@Test func invalidSampleFailsThroughTerminalCleanupWithoutSecondStop()
    async
{
    let invalid = CaptureEncodeSmokeSampleFacts(
        width: 1_280,
        height: 720,
        completeFrameReceived: true,
        h264SampleValidated: true,
        cleanKeyframe: false,
        decoderConfigurationValidated: true,
        accessUnitValidated: true
    )
    let graph = SmokeGraph(behavior: .sample(invalid))
    let report = await smokeCoordinator(
        builder: SmokeBuilder(graph: graph)
    ).run()
    #expect(report.result == .invalidEncodedSample)
    #expect(await graph.counts() == (1, 0))
}

@Test func terminalAndStartFailuresDoNotAttemptSecondCleanup() async {
    let terminalGraph = SmokeGraph(
        behavior: .terminal(.captureStoppedBySystem)
    )
    let terminal = await smokeCoordinator(
        builder: SmokeBuilder(graph: terminalGraph)
    ).run()
    #expect(terminal.result == .captureStoppedBySystem)
    #expect(await terminalGraph.counts() == (1, 0))

    let startGraph = SmokeGraph(behavior: .startFailure)
    let start = await smokeCoordinator(
        builder: SmokeBuilder(graph: startGraph)
    ).run()
    #expect(start.result == .captureStartFailed)
    #expect(await startGraph.counts() == (1, 0))
}

@Test func timeoutAndCancellationStopExactlyOnce() async {
    let timeoutGraph = SmokeGraph(behavior: .idle)
    let timeout = await smokeCoordinator(
        builder: SmokeBuilder(graph: timeoutGraph),
        timeout: true
    ).run()
    #expect(timeout.result == .timedOut)
    #expect(await timeoutGraph.counts() == (1, 1))

    let cancelledGraph = SmokeGraph(behavior: .idle)
    let cancelled = await smokeCoordinator(
        builder: SmokeBuilder(graph: cancelledGraph),
        timeout: false
    ).run()
    #expect(cancelled.result == .cancelled)
    #expect(await cancelledGraph.counts() == (1, 1))
}

@Test func captureStopFailureOverridesOtherwiseSuccessfulSample() async {
    let graph = SmokeGraph(
        behavior: .sample(validSmokeSample),
        stopFails: true
    )
    let report = await smokeCoordinator(
        builder: SmokeBuilder(graph: graph)
    ).run()
    #expect(report.result == .captureStopFailed)
    #expect(await graph.counts() == (1, 1))
}
