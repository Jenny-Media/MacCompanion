import XCTest
import UIKit
@testable import Mac_Companion

@MainActor final class UIReadabilityTests: XCTestCase {
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
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
