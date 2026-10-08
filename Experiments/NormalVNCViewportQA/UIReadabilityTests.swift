import XCTest
import UIKit
import SwiftUI
@testable import Mac_Companion

@MainActor final class UIReadabilityTests: XCTestCase {
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    func testLoginMethodKeepsSeparateAccountsAndDoesNotResetOnKeyReload() {
        var selection = TerminalLoginSelection()
        selection.loadPasswordAccount("synthetic-password-account")
        selection.loadKeyAccount("synthetic-key-account", preferSelected: true)
        XCTAssertEqual(selection.method, .sshKey); XCTAssertEqual(selection.username, "synthetic-key-account")
        selection.select(.password)
        XCTAssertEqual(selection.username, "synthetic-password-account")
        selection.username = "edited-password-account"
        selection.loadKeyAccount("updated-key-account", preferSelected: false)
        XCTAssertEqual(selection.method, .password); XCTAssertEqual(selection.username, "edited-password-account")
        selection.select(.sshKey); XCTAssertEqual(selection.username, "updated-key-account")
        selection.select(.password); XCTAssertEqual(selection.username, "edited-password-account")
    }
    func testRecoveryCardWithRetainedLoginRendersWithoutTheFullSignInForm() async throws {
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", address: "synthetic.local")
        try TerminalSecretStore.save(.init(username: "synthetic", password: "synthetic-only"), id: mac.id)
        let session = DirectTerminalSession(mac: mac)
        session.recovery = .make(.terminalEnded, message: "The connection was lost. Open a new shell to continue.")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, autoConnect: false, exit: {}).directAppearance())
        window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id) }
        try await Task.sleep(for: .milliseconds(300)); window.layoutIfNeeded()
        XCTAssertNotNil(window.rootViewController?.view.window)
        XCTAssertEqual(session.recovery?.reason, .terminalEnded); XCTAssertFalse(session.connecting)
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "compact-synthetic-terminal-recovery"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testMacTypeRowDoesNotReserveAnExpandedIconHeight() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DirectMacLibraryV1(url: folder.appending(path: "macs.json"))
        XCTAssertTrue(library.save(id: nil, name: "Synthetic Laptop", address: "synthetic.local"))
        library.updateDetectedMetadata([.init(name: "Synthetic Laptop", host: "synthetic.local", addresses: ["synthetic.local"], port: 5900, connection: .desktop, modelIdentifier: "MacBookPro18,1")])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: DirectMacEditorV1(mac: library.macs[0], library: library).directAppearance())
        window.makeKeyAndVisible()
        defer { library.discovery.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(700)); window.layoutIfNeeded()
        XCTAssertFalse(library.discovery.scanning, "Opening saved Mac settings must reuse cached metadata")
        let list = try XCTUnwrap(descendants(window).compactMap { $0 as? UICollectionView }.first)
        let initialCells = list.visibleCells.filter { list.indexPath(for: $0)?.section == 0 }
        XCTAssertGreaterThanOrEqual(initialCells.count, 4)
        for cell in initialCells { XCTAssertLessThan(cell.bounds.height, 180, "The Mac Type icon must not stretch its form row") }
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "compact-synthetic-mac-editor"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testTerminalKeysGrowAndRemainScrollableWhenTextSizeChanges() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene), holder = UIViewController()
        window.rootViewController = holder
        let terminal = SessionTerminalView(frame: .zero)
        let bar = TerminalKeyboardBar(terminal: terminal, preferences: .init())
        holder.view.addSubview(bar)
        NSLayoutConstraint.activate([bar.widthAnchor.constraint(equalToConstant: 375),
            bar.topAnchor.constraint(equalTo: holder.view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: holder.view.leadingAnchor)])
        bar.setSoftwareKeyboardVisible(true)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        holder.view.layoutIfNeeded()
        let ctrl = try XCTUnwrap(descendants(bar).compactMap { $0 as? UIButton }.first { $0.configuration?.title == "Ctrl" })
        let fn = try XCTUnwrap(descendants(bar).compactMap { $0 as? UIButton }.first { $0.configuration?.title == "Fn" })
        let normal = try XCTUnwrap(ctrl.titleLabel?.font.pointSize)
        bar.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        holder.view.layoutIfNeeded(); bar.layoutIfNeeded()
        XCTAssertGreaterThan(try XCTUnwrap(ctrl.titleLabel?.font.pointSize), normal)
        XCTAssertGreaterThan(try XCTUnwrap(fn.titleLabel?.font.pointSize), normal)
        for button in descendants(bar).compactMap({ $0 as? UIButton }).filter({ $0.configuration?.title != nil }) {
            button.layoutIfNeeded()
            XCTAssertGreaterThanOrEqual(button.bounds.height + 1, button.titleLabel?.font.lineHeight ?? 0)
            XCTAssertGreaterThanOrEqual(button.bounds.width + 1, button.titleLabel?.intrinsicContentSize.width ?? 0)
        }
        XCTAssertGreaterThan(bar.keyScroll.contentSize.width, bar.keyScroll.bounds.width)
        bar.traitOverrides.preferredContentSizeCategory = .large
        holder.view.layoutIfNeeded(); bar.layoutIfNeeded()
        XCTAssertEqual(bar.height, 108, accuracy: 1, "Default-size toolbar keeps its compact layout")
    }
    func testSelectedDisplayNameWrapsOnSmallPhoneAtAccessibilitySize() throws {
        let picker = CompanionVNCDisplayPicker()
        picker.displays = [["id": 1, "title": "Display 1", "x": 0, "y": 0, "width": 0.5, "height": 1, "pixelWidth": 1920, "pixelHeight": 1080],
                           ["id": 2, "title": "Display 2", "x": 0.5, "y": 0, "width": 0.5, "height": 1, "pixelWidth": 1920, "pixelHeight": 1080]]
        picker.selectedID = 2
        picker.loadViewIfNeeded(); picker.view.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        picker.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        picker.tableView.reloadData(); picker.view.layoutIfNeeded()
        let cell = try XCTUnwrap(picker.tableView.cellForRow(at: IndexPath(row: 1, section: 0)))
        let label = try XCTUnwrap(descendants(cell).compactMap { $0 as? UILabel }.first { $0.text == "Display 2" })
        XCTAssertEqual(label.numberOfLines, 0)
        let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
        XCTAssertGreaterThan(label.bounds.width, 0)
        XCTAssertGreaterThanOrEqual(label.bounds.height + 1, needed.height)
        XCTAssertEqual(cell.accessoryType, .checkmark)
    }
}
