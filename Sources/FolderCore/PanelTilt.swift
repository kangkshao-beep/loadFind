import Foundation

/// Window-local card orientation. Drag translations accumulate from a saved pose.
public struct PanelTilt: Equatable, Sendable {
    public let horizontal: Double
    public let vertical: Double

    public static let neutral = PanelTilt(horizontal: 0, vertical: 0)

    public var pitchDegrees: Double { -vertical * 360 }
    public var yawDegrees: Double { horizontal * 360 }

    public static func dragged(from start: PanelTilt, deltaX: Double, deltaY: Double,
                               width: Double, height: Double) -> PanelTilt {
        guard deltaX.isFinite, deltaY.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0 else { return start }
        let horizontal = start.horizontal + deltaX / width
        let vertical = start.vertical + deltaY / height
        guard (horizontal * 360).isFinite, (vertical * 360).isFinite else { return start }
        return PanelTilt(horizontal: horizontal, vertical: vertical)
    }

    public var lightHorizontal: Double { sin(horizontal.truncatingRemainder(dividingBy: 1) * 2 * .pi) }
    public var lightVertical: Double { sin(vertical.truncatingRemainder(dividingBy: 1) * 2 * .pi) }
}
