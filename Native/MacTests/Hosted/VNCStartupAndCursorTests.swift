import AppKit
import SwiftUI
import XCTest
@testable import MacCompanion

private final class CursorOnlyTransport: CompanionVNCSession {
    private var active = false
    override var running: Bool { active }
    override var connected: Bool { active }
    override func connectAddresses(_ addresses: [String]!, port: Int, username: String!, password: String!) { active = true }
    override func stop() { active = false }
    func reportConnected() { stateHandler?("Connected", ["framebufferWidth": 100, "framebufferHeight": 100]) }
}

private final class CursorInvalidationWindow: NSWindow {
    private(set) var invalidations = 0
    override func invalidateCursorRects(for view: NSView) {
        if view is MacVNCInputView { invalidations += 1 }
        super.invalidateCursorRects(for: view)
    }
}

@MainActor final class VNCStartupAndCursorTests: XCTestCase {
    private func bitmap(width: Int, height: Int) throws -> NSBitmapImageRep {
        try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    }
    private func solidImage(width: Int, height: Int, rgba: [UInt8]) throws -> NSImage {
        let bitmap = try bitmap(width: width, height: height), pixels = try XCTUnwrap(bitmap.bitmapData)
        for y in 0..<height { for x in 0..<width { for channel in 0..<4 {
            pixels[y * bitmap.bytesPerRow + x * 4 + channel] = rgba[channel]
        } } }
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap); return image
    }
    private func render(_ input: MacVNCInputView) throws -> NSBitmapImageRep {
        // Supply a fixed RGBA target rather than a screen-profile bitmap. This
        // invokes the real view drawing without depending on a pending dirty flag.
        let bitmap = try bitmap(width: Int(input.bounds.width), height: Int(input.bounds.height))
        bitmap.size = input.bounds.size
        input.cacheDisplay(in: input.bounds, to: bitmap)
        return bitmap
    }
    private func coloredPixels(_ bitmap: NSBitmapImageRep, channel: Int) throws -> Set<Int> {
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        var result = Set<Int>()
        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
            let offset = y * bitmap.bytesPerRow + x * 4
            if pixels[offset + channel] > 230,
               (0..<3).filter({ $0 != channel }).allSatisfy({ pixels[offset + $0] < 25 }) {
                result.insert(y * bitmap.pixelsWide + x)
            }
        } }
        return result
    }
    private func rectanglePixels(x: Range<Int>, y: Range<Int>, width: Int) -> Set<Int> {
        Set(y.flatMap { row in x.map { row * width + $0 } })
    }
    private func changedPixels(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep) throws -> Set<Int> {
        XCTAssertEqual(first.pixelsWide, second.pixelsWide); XCTAssertEqual(first.pixelsHigh, second.pixelsHigh)
        let a = try XCTUnwrap(first.bitmapData), b = try XCTUnwrap(second.bitmapData)
        var result = Set<Int>()
        for y in 0..<first.pixelsHigh { for x in 0..<first.pixelsWide {
            let firstOffset = y * first.bytesPerRow + x * 4, secondOffset = y * second.bytesPerRow + x * 4
            if (0..<4).contains(where: { a[firstOffset + $0] != b[secondOffset + $0] }) {
                result.insert(y * first.pixelsWide + x)
            }
        } }
        return result
    }
    func testSavedVNCLoginWaitsForUnlockAndStartsOnlyOncePerWindow() throws {
        let id = UUID(), login = DesktopCredentialStoreV1.Login(username: "synthetic", password: "synthetic-only")
        func usable(_ login: DesktopCredentialStoreV1.Login) -> Bool {
            (try? MacLoginPolicy.prepareVNC(username: login.username, password: login.password, remember: true, macID: id)) != nil
        }
        var startup = MacVNCInitialLogin(), reads = 0, attempts = 0
        func read() -> DesktopCredentialStoreV1.Login { reads += 1; return login }
        XCTAssertNil(try startup.loadIfNeeded(canAccess: false, hasExplicitLogin: false, usable: usable, read: read))
        XCTAssertFalse(startup.loaded); XCTAssertEqual(reads, 0)
        let initial = try XCTUnwrap(startup.loadIfNeeded(canAccess: true, hasExplicitLogin: false, usable: usable, read: read))
        XCTAssertTrue(initial.shouldConnect); XCTAssertEqual(initial.login.username, login.username)
        if initial.shouldConnect { attempts += 1 }
        // Reappearance, cancellation, disconnect and recovery keep the same
        // window owner. Neither another appearance nor a later unlock retries.
        for allowed in [true, false, true, true] {
            if let next = try startup.loadIfNeeded(canAccess: allowed, hasExplicitLogin: false, usable: usable, read: read), next.shouldConnect { attempts += 1 }
        }
        XCTAssertEqual(reads, 1); XCTAssertEqual(attempts, 1)
        var otherWindow = MacVNCInitialLogin()
        XCTAssertTrue(try XCTUnwrap(otherWindow.loadIfNeeded(canAccess: true, hasExplicitLogin: false, usable: usable, read: read)).shouldConnect)
        XCTAssertEqual(reads, 2, "A new independent window receives its own initial attempt")
    }

    func testInitialSavedVNCLoginKeepsMissingUnavailableInvalidAndExplicitFieldsPassive() throws {
        let id = UUID()
        func usable(_ login: DesktopCredentialStoreV1.Login) -> Bool {
            (try? MacLoginPolicy.prepareVNC(username: login.username, password: login.password, remember: true, macID: id)) != nil
        }
        var missing = MacVNCInitialLogin(), missingReads = 0
        XCTAssertNil(try missing.loadIfNeeded(canAccess: true, hasExplicitLogin: false, usable: usable, read: { missingReads += 1; return nil }))
        XCTAssertNil(try missing.loadIfNeeded(canAccess: true, hasExplicitLogin: false, usable: usable, read: { XCTFail("Missing data cannot retry automatically"); return nil }))
        XCTAssertEqual(missingReads, 1)

        var unavailable = MacVNCInitialLogin()
        XCTAssertThrowsError(try unavailable.loadIfNeeded(canAccess: true, hasExplicitLogin: false, usable: usable, read: { throw DesktopCredentialStoreV1.StoreFailure.unavailable }))
        XCTAssertTrue(unavailable.loaded)
        XCTAssertNil(try unavailable.loadIfNeeded(canAccess: true, hasExplicitLogin: false, usable: usable, read: { XCTFail("Unavailable data requires explicit retry"); return nil }))

        for login in [DesktopCredentialStoreV1.Login(username: "", password: "synthetic-only"),
                      .init(username: "synthetic", password: ""),
                      .init(username: "synthetic\0", password: "synthetic-only"),
                      .init(username: "synthetic", password: String(repeating: "x", count: 64)),
                      .init(username: String(repeating: "你", count: 22), password: "synthetic-only")] {
            var startup = MacVNCInitialLogin()
            let loaded = try XCTUnwrap(startup.loadIfNeeded(canAccess: true, hasExplicitLogin: false, usable: usable, read: { login }))
            XCTAssertFalse(loaded.shouldConnect)
            XCTAssertEqual(loaded.login.username, login.username); XCTAssertEqual(loaded.login.password, login.password)
        }
        var explicit = MacVNCInitialLogin()
        XCTAssertNil(try explicit.loadIfNeeded(canAccess: true, hasExplicitLogin: true, usable: usable, read: { XCTFail("Explicit fields must not be replaced by saved credentials"); return nil }))
        XCTAssertTrue(explicit.loaded)
        XCTAssertNil(try explicit.loadIfNeeded(canAccess: true, hasExplicitLogin: false, usable: usable, read: { XCTFail("Clearing explicit fields cannot arm a later automatic attempt"); return nil }))
    }

    func testCursorOnlyReportsRedrawAndInvalidateCursorRectsWithoutFramebufferChanges() async throws {
        for legacyTrackpadPreference in [false, true] {
            let transport = CursorOnlyTransport()
            let session = MacVNCSession(mac: .init(id: UUID(), name: "Synthetic", addresses: ["fixture.local"]),
                                        removeSavedLogin: { _ in }, makeTransport: { transport }, canAccess: { true })
            VNCSessionPreferences.setTrackpad(legacyTrackpadPreference, mac: session.mac.id)
            defer { VNCSessionPreferences.clear(session.mac.id) }
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            transport.reportConnected()
            let frame = try solidImage(width: 100, height: 100, rgba: [0, 0, 255, 255])
            transport.frameHandler?(frame)
            let initialCursor = try solidImage(width: 10, height: 10, rgba: [255, 0, 0, 255])
            transport.cursorHandler?(initialCursor, CGPoint(x: 2, y: 3), CGPoint(x: 20, y: 30), true)
            let host = NSHostingView(rootView: MacVNCSurface(session: session))
            host.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
            let window = CursorInvalidationWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close(); session.close() }
            func surface(in view: NSView) -> MacVNCInputView? {
                if let surface = view as? MacVNCInputView { return surface }
                return view.subviews.lazy.compactMap { surface(in: $0) }.first
            }
            for _ in 0..<100 {
                host.layoutSubtreeIfNeeded()
                if surface(in: host) != nil, window.invalidations > 0 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let input = try XCTUnwrap(surface(in: host))
            XCTAssertEqual(input.bounds.size, CGSize(width: 200, height: 100))
            let before = try render(input)
            let previous = window.invalidations
            let cursor = try solidImage(width: 8, height: 12, rgba: [0, 255, 0, 255])
            transport.cursorHandler?(cursor, CGPoint(x: 4, y: 5), CGPoint(x: 80, y: 70), true)
            for _ in 0..<100 {
                host.layoutSubtreeIfNeeded()
                if window.invalidations > previous { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(session.image === frame)
            XCTAssertEqual(session.zoom, 1); XCTAssertEqual(session.pan, .zero)
            XCTAssertGreaterThan(window.invalidations, previous, "Cursor-only reports must update the native surface")
            let after = try render(input)
            XCTAssertTrue(try coloredPixels(before, channel: 0).isEmpty)
            XCTAssertTrue(try coloredPixels(after, channel: 1).isEmpty)
            XCTAssertTrue(try changedPixels(before, after).isEmpty,
                "macOS uses native cursor rectangles even with a saved iPhone Trackpad preference")
            XCTAssertEqual(VNCSessionPreferences.trackpad(session.mac.id), legacyTrackpadPreference,
                "Opening a macOS desktop must not change the shared iPhone preference")
        }
    }
}
