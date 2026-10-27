import Foundation
import CoreGraphics

public struct CardPoint3D {
    public let x: Double
    public let y: Double
    public let z: Double
}

/// A projective transform for an individual face of the solid card.
public struct CardFaceProjection {
    public let xx: Double, xy: Double, xOffset: Double
    public let yx: Double, yy: Double, yOffset: Double
    public let wx: Double, wy: Double, wOffset: Double

    public func project(x: Double, y: Double) -> CGPoint {
        let divisor = wx * x + wy * y + wOffset
        return CGPoint(x: (xx * x + xy * y + xOffset) / divisor,
                       y: (yx * x + yy * y + yOffset) / divisor)
    }
}

/// A real extruded slab: front/back faces share the same camera and solid edge.
/// Scale is derived from all eight corners, so arbitrary rotations stay in bounds.
public struct CardGeometry {
    public let width: Double, height: Double, depth: Double
    public let cameraDistance: Double, scale: Double
    private let sp: Double, cp: Double, sy: Double, cy: Double

    public init(width: Double, height: Double, depth: Double = 18, pitch: Double, yaw: Double) {
        self.width = width.isFinite ? max(1, width) : 340
        self.height = height.isFinite ? max(1, height) : 480
        self.depth = depth.isFinite ? min(36, max(1, depth)) : 18
        let p = (pitch.isFinite ? pitch.truncatingRemainder(dividingBy: 360) : 0) * .pi / 180
        let y = (yaw.isFinite ? yaw.truncatingRemainder(dividingBy: 360) : 0) * .pi / 180
        sp = sin(p); cp = cos(p); sy = sin(y); cy = cos(y)
        cameraDistance = max(self.width, self.height, self.depth) * 3.2

        var extentX = 0.0, extentY = 0.0
        for x in [-self.width / 2, self.width / 2] {
            for y in [-self.height / 2, self.height / 2] {
                for z in [-self.depth / 2, self.depth / 2] {
                    let rx = x * cy + (y * sp + z * cp) * sy
                    let ry = y * cp - z * sp
                    let rz = -x * sy + (y * sp + z * cp) * cy
                    let divisor = 1 - rz / cameraDistance
                    extentX = max(extentX, abs(rx / divisor))
                    extentY = max(extentY, abs(ry / divisor))
                }
            }
        }
        scale = min(1, self.width / max(1, extentX * 2), self.height / max(1, extentY * 2))
    }

    public var frontVisible: Bool { cameraDistance * cp * cy > depth / 2 }
    public var backVisible: Bool { -cameraDistance * cp * cy > depth / 2 }

    public func rotate(x: Double, y: Double, z: Double) -> CardPoint3D {
        CardPoint3D(x: x * cy + (y * sp + z * cp) * sy,
                    y: y * cp - z * sp,
                    z: -x * sy + (y * sp + z * cp) * cy)
    }

    public func project(x: Double, y: Double, z: Double) -> CGPoint {
        let point = rotate(x: x, y: y, z: z)
        let factor = scale / (1 - point.z / cameraDistance)
        return CGPoint(x: width / 2 + point.x * factor, y: height / 2 + point.y * factor)
    }

    public func faceProjection(back: Bool) -> CardFaceProjection {
        let sign = back ? -1.0 : 1.0
        let z = (back ? -1.0 : 1.0) * depth / 2
        let centerX = width / 2, centerY = height / 2
        let a = sign * cy, b = sp * sy, c = z * cp * sy
        let e = cp, f = -z * sp
        let g = -sign * sy, h = sp * cy, i = z * cp * cy
        let dx = -g / cameraDistance, dy = -h / cameraDistance
        let dc = 1 + (g * centerX + h * centerY - i) / cameraDistance
        return CardFaceProjection(
            xx: centerX * dx + scale * a, xy: centerX * dy + scale * b,
            xOffset: centerX * dc + scale * (c - a * centerX - b * centerY),
            yx: centerY * dx, yy: centerY * dy + scale * e,
            yOffset: centerY * dc + scale * (f - e * centerY),
            wx: dx, wy: dy, wOffset: dc)
    }

    public func sideVisible(from a: CGPoint, to b: CGPoint) -> Bool {
        let normal = rotate(x: b.y - a.y, y: a.x - b.x, z: 0)
        let middle = rotate(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, z: 0)
        return -normal.x * middle.x - normal.y * middle.y + normal.z * (cameraDistance - middle.z) > 0
    }

    public func sideLight(from a: CGPoint, to b: CGPoint) -> Double {
        let normal = rotate(x: b.y - a.y, y: a.x - b.x, z: 0)
        let length = max(0.001, hypot(b.x - a.x, b.y - a.y))
        return max(0, (-0.45 * normal.x - 0.55 * normal.y + 0.70 * normal.z) / length)
    }
}
