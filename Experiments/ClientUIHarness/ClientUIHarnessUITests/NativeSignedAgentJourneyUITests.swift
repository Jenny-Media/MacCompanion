import XCTest

/// Opt-in generated Simulator target: normal workspace and native owner with
/// the actual managed host. The regular harness does not select this suite.
final class NativeSignedAgentJourneyUITests: XCTestCase {
    @MainActor
    func testNativeDesktopFrameStopAndRestart() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--authenticated-journey", "--journey-case", UUID().uuidString]
        app.launch()
        func label(_ id: String, _ value: String, timeout: TimeInterval = 30) {
            let item = app.staticTexts[id]
            XCTAssertTrue(item.waitForExistence(timeout: 10))
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: item)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                "\(id): \(item.label); phase: \(app.staticTexts["Journey phase"].label); saved: \(app.staticTexts["Journey saved"].label); native: \(app.staticTexts["Native phase"].label); diagnostic: \(app.staticTexts["Native diagnostic"].label); failure: \(app.staticTexts["Journey failure"].label); connection: \(app.staticTexts["Journey connection"].label); primaryPresent: \(app.staticTexts["Journey primary"].label != "None")")
        }
        func observe() {
            XCTAssertTrue(app.staticTexts["Journey verified observation receipt"].waitForExistence(timeout: 10))
            let previous = app.staticTexts["Journey verified observation receipt"].label
            app.buttons["Journey observe"].tap()
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@ AND label != %@", previous, "None"),
                object: app.staticTexts["Journey verified observation receipt"])
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
        }
        label("Journey phase", "Unpaired")
        app.buttons["Journey pair"].tap()
        label("Journey connection", "Connected")
        label("Journey saved", "1")
        app.buttons["Grant Act"].tap()
        label("Signed administration", "Completed")
        let previousPrimary = app.staticTexts["Journey primary"].label
        app.buttons["Grant Control"].tap()
        let replaced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@ AND label != %@", previousPrimary, "None"),
            object: app.staticTexts["Journey primary"])
        XCTAssertEqual(XCTWaiter.wait(for: [replaced], timeout: 20), .completed)
        label("Journey connection", "Connected")
        observe()
        var primary = app.staticTexts["Journey primary"].label
        for cycle in 1...4 {
            let request = app.buttons["Request Remote Control"]
            for _ in 0..<4 where !request.isHittable { app.swipeUp() }
            XCTAssertTrue(request.waitForExistence(timeout: 10))
            request.tap()
            label("Journey control", "active")
            label("Native phase", "displaying", timeout: 45)
            label("Native displaying frames", String(cycle))
            label("Native diagnostic", "presentation-input-admitted", timeout: 15)
            let surface = app.otherElements["Journey live surface"]
            XCTAssertTrue(surface.waitForExistence(timeout: 10))
            assertVisibleNativeVideo(surface)
            func deliversInput(_ action: () -> Void) {
                let counter = app.staticTexts["Signed input events"]
                let baseline = Int(counter.label) ?? 0
                action()
                let delivered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    (Int(counter.label) ?? 0) > baseline
                }, object: counter)
                XCTAssertEqual(XCTWaiter.wait(for: [delivered], timeout: 10), .completed,
                    "Native input must pass the primary channel and final host posting permit")
            }
            deliversInput {
                surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            app.buttons["Keyboard"].tap()
            XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 10))
            deliversInput { app.keys["a"].tap() }
            app.buttons["Hide Keyboard"].tap()
            let shortcuts = app.buttons["All remote shortcuts"]
            XCTAssertTrue(shortcuts.waitForExistence(timeout: 5))
            for _ in 0..<3 where !shortcuts.isHittable {
                app.scrollViews.containing(.button, identifier: "All remote shortcuts").firstMatch.swipeLeft()
            }
            shortcuts.tap()
            XCTAssertFalse(app.keyboards.element.exists)
            app.buttons["shift"].tap()
            deliversInput { app.buttons["tab"].tap() }
            app.buttons["shift"].tap()
            deliversInput {
                app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@",
                    "Copy", "Remote shortcut copy")).element.tap()
            }
            app.buttons["Done"].tap()
            XCTAssertEqual(app.staticTexts["Journey primary"].label, primary)
            if cycle == 1 {
                app.buttons["Keyboard"].tap()
                XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))
                XCUIDevice.shared.press(.home)
                XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5)
                    || app.state == .runningBackgroundSuspended)
                Thread.sleep(forTimeInterval: 2)
                app.activate()
                label("Journey connection", "Connected")
                label("Native phase", "retired")
                XCTAssertFalse(app.keyboards.element.exists)
                XCTAssertEqual(app.staticTexts["Journey primary"].label, primary)
                let counter = app.staticTexts["Signed input events"]
                let baseline = counter.label
                surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                let denied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", baseline), object: counter)
                denied.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [denied], timeout: 1), .completed)
            }
            if cycle == 2 {
                app.buttons["Keyboard"].tap()
                XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))
                app.buttons["Signed offline"].tap()
                label("Journey connection", "Disconnected")
                label("Journey saved", "1")
                label("Journey control", "ready")
                label("Journey capture", "Stopped")
                label("Journey queue", "0")
                XCTAssertFalse(app.keyboards.element.exists)
                XCTAssertFalse(app.otherElements["Journey live surface"].exists)
                app.buttons["Signed online"].tap()
                label("Journey connection", "Connected")
                let fresh = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@ AND label != %@", primary, "None"),
                    object: app.staticTexts["Journey primary"])
                XCTAssertEqual(XCTWaiter.wait(for: [fresh], timeout: 20), .completed)
                primary = app.staticTexts["Journey primary"].label
                observe()
                label("Journey control", "ready")
                label("Journey failure", "None")
                continue
            }
            let stop = app.buttons["Stop Remote Control"]
            XCTAssertTrue(stop.waitForExistence(timeout: 5))
            stop.tap()
            label("Journey capture", "Stopped")
            label("Journey queue", "0")
            label("Journey control", "ready")
            XCTAssertFalse(app.otherElements["Journey live surface"].exists)
            XCTAssertEqual(app.staticTexts["Journey primary"].label, primary)
            observe()
            label("Journey failure", "None")
        }
    }

    @MainActor
    private func assertVisibleNativeVideo(_ surface: XCUIElement) {
        let screenshot = surface.screenshot()
        guard let image = screenshot.image.cgImage else { XCTFail("Native screenshot missing"); return }
        var bytes = [UInt8](repeating: 0, count: 32 * 32 * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 32, height: 32,
                bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let levels = Set(stride(from: 0, to: bytes.count, by: 4).map {
            (Int(bytes[$0]) + Int(bytes[$0 + 1]) + Int(bytes[$0 + 2])) / 48
        })
        XCTAssertGreaterThan(levels.count, 2, "Admitted native video must show pixels rather than a uniform cover")
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Normal Control native video pixel assertion"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
