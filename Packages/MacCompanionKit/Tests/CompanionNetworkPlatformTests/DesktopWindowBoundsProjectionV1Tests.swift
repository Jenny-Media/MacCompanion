@testable import CompanionNetworkPlatform
import CompanionTestSupport
import CompanionWire
import CoreGraphics
import Foundation
import Testing

@Test func desktopWindowProjectionUsesTopmostWindowNegativeOriginsAndCurrentAspect() throws {
    let data = try Data(contentsOf: FixturePaths.authoritativeFixtures().appendingPathComponent("vnc-desktop-tunnel-v0.1.json"))
    let profile = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    func rect(_ a: [Double]) -> CGRect { CGRect(x: a[0], y: a[1], width: a[2], height: a[3]) }
    for row in profile["windowProjectionCases"] as! [[String: Any]] {
        let point = row["point"] as! [Int64], size = row["framebuffer"] as! [Int64]
        let query = try DesktopWindowQueryV1(sequence: 1, x: point[0], y: point[1], width: size[0], height: size[1])
        let result = try DesktopWindowBoundsProjectionV1.project(query,
            desktop: rect(row["desktop"] as! [Double]), windows: (row["windows"] as! [[Double]]).map(rect))
        #expect(result.rect == row["rect"] as! [Int64])
    }
}
