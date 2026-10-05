#if os(iOS)
import CompanionClientPlatform
import CompanionInteractiveWire
import Foundation
import Testing
import UIKit

@Test @MainActor func keyboardPresentationIsIndependentOfInputAdmission() throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent()
        try #require(parent != root)
        root = parent
    }
    let path = "client-keyboard-presentation-v0.1.json"
    let index = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/manifest.json"))) as! [String: Any]
    try #require((index["fixtures"] as! [[String: Any]]).filter { $0["path"] as? String == path }.count == 1)
    let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/" + path))) as! [String: Any]
    #expect(fixture["cases"] as? [String] == ["opens-before-input-admission", "stays-visible-while-input-paused",
        "paused-commit-is-discarded", "replacement-does-not-replay-paused-commit", "modifier-clears-on-pause",
        "retirement-dismisses-keyboard"])

    var sent: [InteractiveInputPayload] = []
    let surface = UIKitClientLiveSurfaceViewV0(mode: .trackpad, onPayloads: { sent += $0 }, onFailure: { _ in Issue.record("Unexpected input failure") })
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let controller = UIViewController()
    window.rootViewController = controller
    controller.view.addSubview(surface)
    surface.frame = controller.view.bounds
    window.makeKeyAndVisible()
    defer { surface.resetInputAndBlank(); window.isHidden = true }
    let proxy = try #require(surface.subviews.compactMap { $0 as? UITextField }.first)
    surface.toggleSoftwareKeyboard()
    #expect(surface.isSoftwareKeyboardVisible)
    _ = proxy.delegate?.textField?(proxy, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "a")
    #expect(sent.isEmpty)
    surface.setInputEnabled(true)
    surface.setSoftwareKeyboardModifiers(.leftCommand)
    var modifierCleared = false
    surface.onSoftwareKeyboardModifiersCleared = { modifierCleared = true }
    surface.setInputEnabled(false)
    #expect(surface.isSoftwareKeyboardVisible)
    #expect(modifierCleared)
    #expect(surface.gestureRecognizers?.allSatisfy { !$0.isEnabled } == true)
    _ = proxy.delegate?.textField?(proxy, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "b")
    #expect(sent.isEmpty)
    proxy.setMarkedText("b", selectedRange: NSRange(location: 1, length: 0))
    surface.setInputEnabled(true)
    #expect(proxy.markedTextRange == nil)
    #expect(surface.isSoftwareKeyboardVisible)
    #expect(sent.isEmpty)
    _ = proxy.delegate?.textField?(proxy, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "c")
    #expect(sent == [.text("c")])
    surface.resetInputAndBlank()
    #expect(!surface.isSoftwareKeyboardVisible)
    _ = proxy.delegate?.textField?(proxy, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "d")
    #expect(sent == [.text("c")])
}
#endif
