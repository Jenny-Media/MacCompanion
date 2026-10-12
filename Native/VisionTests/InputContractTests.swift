import Foundation
import CoreGraphics

@main enum VisionInputContractTests {
    struct Corpus: Decodable {
        let geometry: [Geometry]; let terminalAdmission: [Admission]; let selection: [Selection]
        let interaction: [Interaction]; let scrollDistance: [Scroll]
        let scrollDirection: [String: Int]
        let toolbarTargets: [Target]; let nativeScrollPackets: [NativeScroll]
        let physicalWheelBoundaries: [WheelBoundary]
        let handPanBoundaries: [PanBoundary]
    }
    struct PanBoundary: Decodable {
        let name: String; let crop: [Double]; let viewport: [Double]; let zoom: Double; let pan: [Double]
        let translations: [[Double]]; let expectedPan: [[Double]]; let cancelled: Bool
        let restartTranslation: [Double]; let restartPan: [Double]
    }
    struct WheelBoundary: Decodable {
        let state: String; let crop: [Double]; let viewport: [Double]
        let begin: [Double]; let finish: [Double]; let next: [Double]; let nativeBeginTargets: [[Double]]
    }
    struct Target: Decodable {
        let cursor: [Double]; let crop: [Double]; let viewport: [Double]; let zoom: Double; let pan: [Double]
        let target: [Double]?; let local: [Double]?
    }
    struct NativeScroll: Decodable { let delta: [Double]; let packets: [[Double]]? }
    struct Interaction: Decodable {
        let name: String; let events: [[Value]]; let effects: [String]; let state: String
    }
    enum Value: Decodable {
        case text(String), number(Double)
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let text = try? value.decode(String.self) { self = .text(text) }
            else { self = .number(try value.decode(Double.self)) }
        }
        var text: String { if case .text(let value) = self { value } else { "" } }
        var number: Double { if case .number(let value) = self { value } else { 0 } }
    }
    struct Scroll: Decodable { let deltas: [[Double]]; let horizontal: Int; let vertical: Int; let remainder: [Double] }
    struct Selection: Decodable { let translations: [[Double]]; let cancelled: Bool; let click: Bool; let dragBeganAt: Int? }
    struct Admission: Decodable { let focused: Bool; let emulatorReply: Bool; let suspended: Bool; let unlocked: Bool; let allowed: Bool }
    struct Geometry: Decodable {
        let crop: [Double]; let viewport: [Double]; let point: [Double]
        let mapped: [Double]?; let dragging: Bool?
    }
    static func main() throws {
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        precondition(corpus.scrollDirection == ["positiveVertical": VisionScrollDistance.positiveVertical,
            "negativeVertical": VisionScrollDistance.negativeVertical, "positiveHorizontal": VisionScrollDistance.positiveHorizontal,
            "negativeHorizontal": VisionScrollDistance.negativeHorizontal])
        for row in corpus.geometry {
            let crop = CGRect(x: row.crop[0], y: row.crop[1], width: row.crop[2], height: row.crop[3])
            let destination = VisionDesktopGeometry.destination(crop: crop, viewport: CGSize(width: row.viewport[0], height: row.viewport[1]))
            let mapped = VisionDesktopGeometry.map(CGPoint(x: row.point[0], y: row.point[1]), crop: crop, destination: destination, dragging: row.dragging ?? false)
            precondition(mapped == row.mapped.map { CGPoint(x: $0[0], y: $0[1]) }, "Incorrect native wide/ultrawide pointer mapping")
        }
        for row in corpus.terminalAdmission {
            precondition(VisionTerminalAdmission.allows(focused: row.focused, emulatorReply: row.emulatorReply, suspended: row.suspended, unlocked: row.unlocked) == row.allowed)
        }
        for row in corpus.selection {
            var gesture = VisionSelectionGesture(), beginnings: [Int] = []
            for (index, point) in row.translations.enumerated() {
                if gesture.update(translation: CGPoint(x: point[0], y: point[1])) { beginnings.append(index) }
            }
            precondition(beginnings == row.dragBeganAt.map { [$0] } ?? [])
            precondition(gesture.finish(cancelled: row.cancelled) == row.click)
            precondition(!gesture.finish(cancelled: false), "Completion or cancellation cannot click twice")
        }
        for row in corpus.interaction {
            var gesture = VisionDesktopGesture(), effects: [String] = []
            for event in row.events {
                let time = event[1].number / 1000
                let values: [VisionDesktopGesture.Effect]
                switch event[0].text {
                case "begin", "pointer":
                    let point = CGPoint(x: event[2].number, y: event[3].number)
                    values = gesture.begin(target: point, local: point, time: time, source: event[0].text == "pointer" ? .pointer : .hand)
                case "move": values = gesture.move(CGPoint(x: event[2].number, y: event[3].number))
                case "hold": values = gesture.hold(time: time)
                case "end": values = gesture.finish(time: time)
                case "cancel": values = gesture.cancel()
                case "right": values = gesture.action(.right)
                case "double": values = gesture.action(.doubleClick)
                case "arm": values = gesture.action(.armDrag)
                case "adjust": values = gesture.setAdjusting(true)
                case "done": values = gesture.setAdjusting(false)
                default: fatalError("Unknown authoritative interaction event")
                }
                effects += values.map {
                    let point = "@\(Int($0.point.x)),\(Int($0.point.y))"
                    let delta = [.scroll, .dragMove, .localPan].contains($0.kind) ? ":\(Int($0.delta.x)),\(Int($0.delta.y))" : ""
                    return $0.kind.rawValue + point + delta
                }
            }
            precondition(effects == row.effects, "Incorrect effects for \(row.name): \(effects)")
            precondition(gesture.state.rawValue == row.state, "Incorrect final state for \(row.name)")
        }
        for row in corpus.scrollDistance {
            var accumulator = VisionScrollDistance(), horizontal = 0, vertical = 0
            for delta in row.deltas {
                let result = accumulator.accumulate(dx: delta[0], dy: delta[1])!
                horizontal += result.horizontal; vertical += result.vertical
            }
            precondition(horizontal == row.horizontal && vertical == row.vertical)
            precondition(accumulator.remainder == CGPoint(x: row.remainder[0], y: row.remainder[1]))
        }
        for row in corpus.toolbarTargets {
            let crop = CGRect(x: row.crop[0], y: row.crop[1], width: row.crop[2], height: row.crop[3])
            let viewport = CGSize(width: row.viewport[0], height: row.viewport[1])
            let destination = VisionDesktopGeometry.destination(crop: crop, viewport: viewport, zoom: row.zoom,
                pan: CGPoint(x: row.pan[0], y: row.pan[1]))
            let target = VisionDesktopGeometry.visibleTarget(cursor: CGPoint(x: row.cursor[0], y: row.cursor[1]),
                crop: crop, destination: destination, viewport: viewport)
            precondition(target?.remote == row.target.map { CGPoint(x: $0[0], y: $0[1]) })
            precondition(target?.local == row.local.map { CGPoint(x: $0[0], y: $0[1]) })
        }
        for row in corpus.nativeScrollPackets {
            let packets = VisionNativeScroll.packets(dx: row.delta[0], dy: row.delta[1])
            precondition(packets == row.packets.map { $0.map { CGPoint(x: $0[0], y: $0[1]) } })
        }
        for row in corpus.physicalWheelBoundaries {
            precondition(["ended", "cancelled", "failed"].contains(row.state))
            let crop = CGRect(x: row.crop[0], y: row.crop[1], width: row.crop[2], height: row.crop[3])
            let destination = VisionDesktopGeometry.destination(crop: crop, viewport: CGSize(width: row.viewport[0], height: row.viewport[1]))
            precondition(VisionDesktopGeometry.map(CGPoint(x: row.finish[0], y: row.finish[1]), crop: crop, destination: destination) == nil)
            for (local, target) in zip([row.begin, row.next], row.nativeBeginTargets) {
                precondition(VisionDesktopGeometry.map(CGPoint(x: local[0], y: local[1]), crop: crop, destination: destination) == CGPoint(x: target[0], y: target[1]))
            }
        }
        for row in corpus.handPanBoundaries {
            let crop = CGRect(x: row.crop[0], y: row.crop[1], width: row.crop[2], height: row.crop[3])
            let viewport = CGSize(width: row.viewport[0], height: row.viewport[1])
            var gesture = VisionDesktopGesture(), pan = CGPoint(x: row.pan[0], y: row.pan[1])
            _ = gesture.setAdjusting(true)
            _ = gesture.begin(target: .zero, local: .zero, time: 0)
            precondition(row.translations.count == row.expectedPan.count)
            for (travel, expected) in zip(row.translations, row.expectedPan) {
                let effects = gesture.move(CGPoint(x: travel[0], y: travel[1]))
                precondition(effects.count == 1 && effects[0].kind == .localPan)
                pan = VisionDesktopGeometry.clampedPan(CGPoint(x: pan.x + effects[0].delta.x, y: pan.y + effects[0].delta.y),
                    crop: crop, viewport: viewport, zoom: row.zoom)
                precondition(pan == CGPoint(x: expected[0], y: expected[1]), "Hand pan reversal: \(row.name)")
            }
            precondition(gesture.finish(time: 1, cancelled: row.cancelled).isEmpty)
            _ = gesture.begin(target: .zero, local: .zero, time: 2)
            let effects = gesture.move(CGPoint(x: row.restartTranslation[0], y: row.restartTranslation[1]))
            precondition(effects.count == 1 && effects[0].kind == .localPan)
            pan = VisionDesktopGeometry.clampedPan(CGPoint(x: pan.x + effects[0].delta.x, y: pan.y + effects[0].delta.y),
                crop: crop, viewport: viewport, zoom: row.zoom)
            precondition(pan == CGPoint(x: row.restartPan[0], y: row.restartPan[1]), "Fresh hand pan baseline: \(row.name)")
            precondition(gesture.finish(time: 3).isEmpty)
        }
        let crop = CGRect(x: 0, y: 0, width: 1920, height: 1080), viewport = CGSize(width: 960, height: 600)
        let anchor = CGPoint(x: 300, y: 200)
        let before = VisionDesktopGeometry.destination(crop: crop, viewport: viewport)
        let anchored = VisionDesktopGeometry.anchoredPan(crop: crop, viewport: viewport, zoom: 1, pan: .zero, nextZoom: 2, anchor: anchor)
        let after = VisionDesktopGeometry.destination(crop: crop, viewport: viewport, zoom: 2, pan: anchored)
        precondition(VisionDesktopGeometry.map(anchor, crop: crop, destination: before) == VisionDesktopGeometry.map(anchor, crop: crop, destination: after))
        precondition(VisionDesktopGeometry.clampedPan(CGPoint(x: 100_000, y: 100_000), crop: crop, viewport: viewport, zoom: 1) == .zero)
        precondition(VisionDesktopGeometry.destination(crop: CGRect(x: 0, y: 0, width: 5120, height: 1440), viewport: CGSize(width: CGFloat.infinity, height: 100)) == .zero)
        var a = VisionHeldInput(), b = VisionHeldInput()
        precondition(a.down(0xffe1) && b.down(0xffe3))
        a.pointer(1); b.pointer(4)
        let release = a.release()
        precondition(release.keys == [0xffe1] && release.pointer)
        precondition(a.release().keys.isEmpty && !a.release().pointer)
        precondition(b.keys == [0xffe3] && b.buttons == 4)
        for key in 0..<256 { precondition(a.down(UInt32(key))) }
        precondition(!a.down(256))
        precondition(a.release().keys.count == 256)
        print("Native visionOS input contract: \(corpus.geometry.count) geometry, \(corpus.selection.count) jitter, \(corpus.interaction.count) interaction traces, \(corpus.scrollDistance.count) sampled-distance, \(corpus.toolbarTargets.count) visible-target, \(corpus.nativeScrollPackets.count) native-packet, \(corpus.physicalWheelBoundaries.count) wheel-boundary and \(corpus.handPanBoundaries.count) hand-pan boundary cases, anchored/clamped adjustment and independent held-input owners passed")
    }
}
