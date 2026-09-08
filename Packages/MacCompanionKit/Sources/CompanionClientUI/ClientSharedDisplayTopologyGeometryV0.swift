import CompanionInteractiveWire
import CoreGraphics
import Foundation

struct ClientSharedDisplayTopologyGeometryV0 {
    let framesByDisplayID: [UUID: CGRect]

    init?(
        displays: [InteractiveDisplayCandidateV1],
        canvasSize: CGSize,
        padding: CGFloat = 20
    ) {
        guard !displays.isEmpty,
              canvasSize.width > padding * 2,
              canvasSize.height > padding * 2 else { return nil }

        let minX = displays.map { Int64($0.layoutX) }.min() ?? 0
        let minY = displays.map { Int64($0.layoutY) }.min() ?? 0
        let maxX = displays.map {
            Int64($0.layoutX) + Int64($0.layoutWidth)
        }.max() ?? 0
        let maxY = displays.map {
            Int64($0.layoutY) + Int64($0.layoutHeight)
        }.max() ?? 0
        let desktopWidth = maxX - minX
        let desktopHeight = maxY - minY
        guard desktopWidth > 0, desktopHeight > 0 else { return nil }

        let availableWidth = canvasSize.width - padding * 2
        let availableHeight = canvasSize.height - padding * 2
        let scale = min(
            availableWidth / CGFloat(desktopWidth),
            availableHeight / CGFloat(desktopHeight)
        )
        guard scale.isFinite, scale > 0 else { return nil }

        let renderedWidth = CGFloat(desktopWidth) * scale
        let renderedHeight = CGFloat(desktopHeight) * scale
        let originX = (canvasSize.width - renderedWidth) / 2
        let originY = (canvasSize.height - renderedHeight) / 2
        framesByDisplayID = Dictionary(uniqueKeysWithValues: displays.map {
            let relativeX = Int64($0.layoutX) - minX
            let relativeY = Int64($0.layoutY) - minY
            let frameX = originX + CGFloat(relativeX) * scale
            let frameY = originY + CGFloat(relativeY) * scale
            let frameWidth = CGFloat($0.layoutWidth) * scale
            let frameHeight = CGFloat($0.layoutHeight) * scale
            let frame = CGRect(
                x: frameX,
                y: frameY,
                width: frameWidth,
                height: frameHeight
            )
            return ($0.id, frame)
        })
    }
}
