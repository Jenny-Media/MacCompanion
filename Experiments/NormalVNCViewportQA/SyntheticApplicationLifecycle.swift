import XCTest
import UIKit
@testable import Mac_Companion

@MainActor extension XCTestCase {
    /// UIKit stays active when a test posts a synthetic background notification.
    /// Pair it with foreground notifications even if an assertion unwrap or wait throws.
    func withSyntheticApplicationBackground<Result>(file: StaticString = #filePath, line: UInt = #line,
                                                    beforeBackground: () -> Void = {},
                                                    _ operation: () async throws -> Result) async throws -> Result {
        let application = UIApplication.shared, lock = DirectAppLockV1.shared
        guard !lock.enabled else { throw XCTSkip("Leave an already enabled QA app lock unchanged") }
        let scene = try XCTUnwrap(application.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, file: file, line: line)
        XCTAssertEqual(application.applicationState, .active, file: file, line: line)
        XCTAssertTrue(lock.canResumeRemoteSession, "Background coverage must begin with foreground admission", file: file, line: line)
        let center = NotificationCenter.default
        defer {
            // Do not manufacture activation if the Simulator really backgrounded the app.
            if application.applicationState == .active && scene.activationState == .foregroundActive {
                center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
                center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
                XCTAssertTrue(lock.foregroundActive, file: file, line: line)
                XCTAssertTrue(lock.canResumeRemoteSession, "Synthetic background must not leak into the next case", file: file, line: line)
            } else {
                XCTFail("The QA app left the foreground during synthetic lifecycle coverage", file: file, line: line)
            }
        }
        beforeBackground()
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(lock.foregroundActive, "Exercise the installed application lifecycle observer", file: file, line: line)
        return try await operation()
    }

    func waitForComposerUI(_ description: String, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for \(description)", file: file, line: line)
                throw POSIXError(.ETIMEDOUT)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
