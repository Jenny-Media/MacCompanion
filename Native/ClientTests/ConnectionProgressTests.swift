#if os(iOS)
import Darwin
import NIO
import XCTest
@testable import Mac_Companion

@MainActor final class ConnectionProgressTests: XCTestCase {
    func testSocketProgressReportsEachAttemptBeforeReturningTheFallback() async throws {
        let probe = FilesDirectoryTestProbe()
        let listener = try await filesDirectoryTestServer(probe: probe)
        defer { Task { await probe.shutdown(); try? await listener.close() } }
        let port = try XCTUnwrap(listener.localAddress?.port)
        let addresses = ["127.0.0.2", "127.0.0.1"]
        let reported = DispatchSemaphore(value: 0)
        var attempts: [String] = []
        let (fd, _, index) = await connectDirectSocket(addresses: addresses, port: port, cancelled: { false },
            registerSocket: { fd in fd < 0 || reported.wait(timeout: .now() + 2) == .success }, attemptingAddress: { address in
                attempts.append(address)
                reported.signal()
            })
        if fd >= 0 { Darwin.close(fd) }
        XCTAssertGreaterThanOrEqual(fd, 0)
        XCTAssertEqual(attempts, addresses)
        XCTAssertEqual(index, 1)
    }

    func testSecurityIsNotClaimedWhileReachingOrVerifyingTheMac() {
        let progress = DirectConnectionProgressState()
        XCTAssertFalse(progress.encrypted)
        progress.recordTransportMessage("Verifying SSH server…")
        XCTAssertEqual(progress.stage, .securing)
        XCTAssertFalse(progress.encrypted)
        XCTAssertEqual(progress.steps(service: "Screen Sharing")[1].status, .active)
        progress.recordNativeState("Opening desktop")
        XCTAssertEqual(progress.stage, .securing, "A native UI state cannot establish SSH security")
        progress.recordTransportMessage("Signing in to Remote Login…")
        XCTAssertTrue(progress.encrypted)
        XCTAssertEqual(progress.steps(service: "Screen Sharing")[1].status, .complete)
        XCTAssertEqual(progress.stage, .signingIn)
    }
    func testDesktopWaitsForNativeSignInBeforeShowingTheFinalStep() {
        let progress = DirectConnectionProgressState()
        progress.recordTransportMessage("Opening encrypted connection…")
        XCTAssertEqual(progress.stage, .signingIn, "SSH completion still leaves Screen Sharing authentication")
        progress.recordNativeState("Authenticating with macOS")
        XCTAssertEqual(progress.stage, .signingIn)
        progress.recordNativeState("Opening desktop")
        XCTAssertEqual(progress.stage, .startingSession)
        XCTAssertEqual(progress.steps(service: "Screen Sharing")[2].status, .complete)
        XCTAssertEqual(progress.steps(service: "Screen Sharing")[3].status, .active)
    }
    func testLateEventsCannotMoveTheSameAttemptBackwards() {
        let progress = DirectConnectionProgressState()
        progress.recordTransportMessage("Opening encrypted connection…")
        progress.recordNativeState("Opening desktop")
        for message in ["Connecting to Remote Login…", "Verifying SSH server…", "Signing in to Remote Login…", "Unknown"] {
            progress.recordTransportMessage(message)
            XCTAssertEqual(progress.stage, .startingSession)
        }
        XCTAssertEqual(progress.steps(service: "Screen Sharing").filter { $0.status == .active }.count, 1)
    }
    func testNewAttemptResetsCompletionSecurityCleanupAndClockTogether() {
        let progress = DirectConnectionProgressState()
        progress.begin(waitingForDisplays: true)
        let previousAttempt = progress.attempt
        progress.recordRouteAddress("preferred.local")
        progress.recordRouteAddress("fallback.local")
        XCTAssertEqual(progress.routeAddress, "fallback.local")
        XCTAssertEqual(progress.tryingAddressText, "Trying fallback.local")
        progress.recordTransportMessage("Opening encrypted connection…")
        progress.recordNativeState("Opening desktop")
        progress.begin(waitingForDisplays: false)
        XCTAssertNotEqual(progress.attempt, previousAttempt)
        XCTAssertNil(progress.routeAddress)
        XCTAssertNil(progress.tryingAddressText)
        XCTAssertEqual(progress.stage, .contacting)
        XCTAssertFalse(progress.encrypted)
        XCTAssertFalse(progress.restoresDisplays)
        XCTAssertEqual(progress.elapsedSeconds(at: progress.startedAt), 0)
        XCTAssertEqual(progress.steps(service: "Screen Sharing").count, 4)
    }
    func testCleanupWaitStaysInTheChecklistAfterReconnectionBegins() {
        let progress = DirectConnectionProgressState()
        progress.begin(waitingForDisplays: true)
        let initialIDs = progress.steps(service: "Screen Sharing").map(\.id)
        XCTAssertEqual(progress.stage, .restoringDisplays)
        progress.finishedRestoringDisplays()
        let rows = progress.steps(service: "Screen Sharing")
        XCTAssertEqual(rows.map(\.id), initialIDs, "The list must not jump when the cleanup wait ends")
        XCTAssertEqual(rows.first?.status, .complete)
        XCTAssertEqual(rows.first?.title, "Ready to reconnect", "A timer is not proof the host restored its physical displays")
        XCTAssertEqual(progress.stage, .contacting)
        XCTAssertFalse(progress.encrypted)
    }
    func testFinalStepMatchesTheActualConnectionService() {
        let progress = DirectConnectionProgressState()
        XCTAssertEqual(progress.steps(service: "Screen Sharing").last?.title, "Starting desktop")
        XCTAssertEqual(progress.steps(service: "Trackpad & Keyboard").last?.title, "Enabling controls")
        XCTAssertEqual(progress.steps(service: "Terminal").last?.title, "Opening Terminal")
    }
    func testElapsedTimeUsesTheAttemptClockAndNeverBecomesNegative() {
        let progress = DirectConnectionProgressState()
        XCTAssertEqual(progress.elapsedSeconds(at: progress.startedAt + 8.9), 8)
        XCTAssertEqual(progress.elapsedSeconds(at: progress.startedAt - 1), 0)
    }
}
#endif
