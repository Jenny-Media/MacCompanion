import AppKit
import Foundation

@main struct InputContractTests {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let fixture = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var count = 0
        for value in fixture["terminalSGRReleaseIdentity"] as! [[String: Any]] {
            let input = (value["input"] as! [Int]).map(UInt8.init)
            let output = (value["output"] as! [Int]).map(UInt8.init)
            precondition(MacTerminalMouseReport.correctingSGRRelease(input[...], button: value["button"] as? Int) == output)
            count += 1
        }
        for value in fixture["terminalFocusRelease"] as! [[String: Any]] {
            var held = MacTerminalHeldInput()
            let press = (value["press"] as! [Int]).map(UInt8.init)
            let release = (value["release"] as! [Int]).map(UInt8.init)
            precondition(held.observe(press[...], keyboardEvents: value["keyboardEvents"] as! Bool))
            precondition(held.releaseAll().packets == (release.isEmpty ? [] : [release]))
            precondition(held.releaseAll().packets.isEmpty)
            count += 1
        }
        var held = MacTerminalHeldInput()
        for text in ["\u{1b}[97u", "\u{1b}[97;1:2u", "\u{1b}[97;1:3u"] {
            precondition(held.observe(Array(text.utf8)[...], keyboardEvents: true))
        }
        precondition(held.releaseAll().packets.isEmpty)
        precondition(held.observe(Array("\u{1b}[<0;12;21M".utf8)[...], keyboardEvents: false))
        precondition(held.observe(Array("\u{1b}[<32;14;22M".utf8)[...], keyboardEvents: false))
        precondition(held.releaseAll().packets == [Array("\u{1b}[<0;14;22m".utf8)])
        for key in 1...256 { precondition(held.observe(Array("\u{1b}[\(key)u".utf8)[...], keyboardEvents: true)) }
        precondition(!held.observe(Array("\u{1b}[257u".utf8)[...], keyboardEvents: true))
        precondition(held.releaseAll().packets.count == 256)
        count += 3
        var startup = MacVNCInitialLogin()
        var reads = 0
        func read() -> String? { reads += 1; return "synthetic" }
        let lockedStartup = try startup.loadIfNeeded(canAccess: false, hasExplicitLogin: false, usable: { !$0.isEmpty }, read: read)
        precondition(lockedStartup == nil)
        precondition(reads == 0)
        let firstStartup = try startup.loadIfNeeded(canAccess: true, hasExplicitLogin: false, usable: { !$0.isEmpty }, read: read)
        precondition(firstStartup?.shouldConnect == true)
        let repeatedStartup = try startup.loadIfNeeded(canAccess: true, hasExplicitLogin: false, usable: { !$0.isEmpty }, read: read)
        precondition(repeatedStartup == nil)
        precondition(reads == 1)
        count += 1
        for value in fixture["terminalMouseReports"] as! [[String: Any]] {
            let bytes = (value["bytes"] as! [Int]).map(UInt8.init)
            precondition(MacTerminalMouseReport.contains(bytes[...]) == value["mouse"] as! Bool)
            count += 1
        }
        for value in fixture["keyMapping"] as! [[String: Int]] {
            precondition(MacVNCKeyboardState.keysym(code: UInt16(value["keyCode"]!), characters: "") == UInt32(value["keysym"]!))
            count += 1
        }
        for value in fixture["geometry"] as! [[String: Any]] {
            let rect = value["crop"] as! [Double], viewport = value["viewport"] as! [Double], point = value["point"] as! [Double]
            let crop = CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])
            let destination = MacVNCGeometry.destination(crop: crop, viewport: CGSize(width: viewport[0], height: viewport[1]))
            let actual = MacVNCGeometry.map(point: CGPoint(x: point[0], y: point[1]), crop: crop, destination: destination)
            if let expected = value["mapped"] as? [Double] { precondition(actual == CGPoint(x: expected[0], y: expected[1])) }
            else { precondition(actual == nil) }
            count += 1
        }
        var first = MacVNCKeyboardState(), second = MacVNCKeyboardState()
        precondition(first.updateModifiers([.command]) == [.init(key: 0xffeb, down: true)])
        precondition(first.keyDown(code: 8, characters: "c", repeatKey: false) == [.init(key: 99, down: true)])
        precondition(second.keyDown(code: 0, characters: "a", repeatKey: false) == [.init(key: 97, down: true)])
        precondition(first.releaseAll() == [.init(key: 99, down: false), .init(key: 0xffeb, down: false)])
        precondition(second.held[0] == 97 && second.keyUp(code: 0) == [.init(key: 97, down: false)])
        count += 1
        precondition(first.keyDown(code: 8, characters: "C", repeatKey: false) == [.init(key: 67, down: true)])
        precondition(first.keyDown(code: 8, characters: "c", repeatKey: true) == [.init(key: 67, down: true)])
        precondition(first.keyUp(code: 8) == [.init(key: 67, down: false)])
        precondition(first.keyUp(code: 8).isEmpty)
        count += 1
        precondition(MacVNCKeyboardState.keysym(code: 0, characters: "你") == 0x01004f60)
        precondition(MacVNCKeyboardState.keysym(code: 0, characters: "\u{1}") == nil)
        count += 1
        let crop = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        precondition(MacVNCGeometry.map(point: CGPoint(x: -100, y: 1000), crop: crop,
            destination: MacVNCGeometry.destination(crop: crop, viewport: CGSize(width: 960, height: 600)), clamp: true) == CGPoint(x: 1920, y: 1079))
        count += 1
        let viewport = CGSize(width: 960, height: 600)
        let cursor = CGPoint(x: crop.maxX - 1, y: crop.maxY - 1)
        let followed = MacVNCGeometry.following(cursor: cursor, crop: crop, viewport: viewport, zoom: 3, pan: .zero)
        let visible = MacVNCGeometry.destination(crop: crop, viewport: viewport, zoom: 3, pan: followed)
        let displayed = CGPoint(x: visible.minX + (cursor.x - crop.minX) / crop.width * visible.width,
                                y: visible.minY + (cursor.y - crop.minY) / crop.height * visible.height)
        precondition(CGRect(origin: .zero, size: viewport).contains(displayed))
        precondition(MacVNCGeometry.following(cursor: cursor, crop: crop, viewport: viewport, zoom: 1, pan: .zero) == .zero)
        count += 1
        var composition = MacVNCComposition()
        composition.set("你🙂", selectedRange: NSRange(location: 1, length: 2))
        precondition(composition.hasMarkedText && composition.markedRange == NSRange(location: 0, length: 3))
        precondition(composition.selection == NSRange(location: 1, length: 2))
        precondition(composition.substring(NSRange(location: 1, length: 99))?.0.string == "🙂")
        precondition(composition.substring(NSRange(location: 2, length: 1))?.1 == NSRange(location: 1, length: 2))
        precondition(composition.substring(NSRange(location: NSNotFound, length: 1)) == nil)
        composition.discard(); precondition(!composition.hasMarkedText && composition.text.isEmpty)
        count += 1
        composition.set(String(repeating: "x", count: 4097), selectedRange: NSRange(location: 0, length: 1))
        precondition(!composition.hasMarkedText)
        composition.set("你", selectedRange: NSRange(location: NSNotFound, length: Int.max))
        precondition(composition.selection == NSRange(location: 1, length: 0))
        count += 1
        print("Native Mac input contracts: \(count) golden geometry, key mapping, focus release and session isolation cases passed")
    }
}
