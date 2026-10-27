import SwiftUI
import FolderCore

struct CardMoveHandleRegionKey: PreferenceKey {
    static let defaultValue: [CGPoint] = []
    static func reduce(value: inout [CGPoint], nextValue: () -> [CGPoint]) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

struct SolidCardView<Front: View, Back: View>: View, Animatable {
    var pitch: Double
    var yaw: Double
    let size: CGSize
    let front: Front
    let back: Back

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(pitch, yaw) }
        set { pitch = newValue.first; yaw = newValue.second }
    }

    var body: some View {
        let geometry = CardGeometry(width: size.width, height: size.height, pitch: pitch, yaw: yaw)
        ZStack {
            Canvas { context, _ in drawEdge(context: &context, geometry: geometry) }
                .allowsHitTesting(false).accessibilityHidden(true)
            if geometry.frontVisible {
                front.frame(width: size.width, height: size.height)
                    .projectionEffect(projection(geometry.faceProjection(back: false)))
                    .transition(.identity)
            }
            if geometry.backVisible {
                back.frame(width: size.width, height: size.height)
                    .projectionEffect(projection(geometry.faceProjection(back: true)))
                    .transition(.identity)
            }
        }
        .frame(width: size.width, height: size.height)
        .preference(key: CardMoveHandleRegionKey.self, value: moveHandleRegion(geometry))
    }

    private func moveHandleRegion(_ geometry: CardGeometry) -> [CGPoint] {
        guard geometry.frontVisible else { return [] }
        let face = geometry.faceProjection(back: false)
        return [CGPoint(x: 22, y: 24), CGPoint(x: 68, y: 24),
                CGPoint(x: 68, y: 70), CGPoint(x: 22, y: 70)].map {
            let projected = face.project(x: $0.x, y: $0.y)
            return CGPoint(x: projected.x + 24, y: projected.y + 24)
        }
    }

    private func projection(_ face: CardFaceProjection) -> ProjectionTransform {
        var transform = ProjectionTransform()
        transform.m11 = face.xx; transform.m21 = face.xy; transform.m31 = face.xOffset
        transform.m12 = face.yx; transform.m22 = face.yy; transform.m32 = face.yOffset
        transform.m13 = face.wx; transform.m23 = face.wy; transform.m33 = face.wOffset
        return transform
    }

    private func drawEdge(context: inout GraphicsContext, geometry: CardGeometry) {
        let points = outline(width: size.width, height: size.height)
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            guard geometry.sideVisible(from: a, to: b) else { continue }
            let frontA = geometry.project(x: a.x, y: a.y, z: geometry.depth / 2)
            let frontB = geometry.project(x: b.x, y: b.y, z: geometry.depth / 2)
            let backB = geometry.project(x: b.x, y: b.y, z: -geometry.depth / 2)
            let backA = geometry.project(x: a.x, y: a.y, z: -geometry.depth / 2)
            var path = Path()
            path.move(to: frontA); path.addLine(to: frontB)
            path.addLine(to: backB); path.addLine(to: backA); path.closeSubpath()
            let light = geometry.sideLight(from: a, to: b)
            let metal = 0.24 + light * 0.34
            let gradient = Gradient(stops: [
                .init(color: .white.opacity(0.92), location: 0),
                .init(color: Color(white: metal + 0.13), location: 0.12),
                .init(color: Color(white: metal), location: 0.38),
                .init(color: Color(white: metal + 0.08), location: 0.80),
                .init(color: Color(white: min(0.95, metal + 0.27)), location: 1)
            ])
            context.fill(path, with: .linearGradient(gradient, startPoint: frontA, endPoint: backA))
            context.stroke(path, with: .color(.black.opacity(0.08)), lineWidth: 0.25)
        }
    }

    /// Clockwise rounded outline; each segment is one face of the extrusion.
    private func outline(width: CGFloat, height: CGFloat) -> [CGPoint] {
        let radius = min(24, width / 4, height / 4)
        let centers = [
            CGPoint(x: width / 2 - radius, y: -height / 2 + radius),
            CGPoint(x: width / 2 - radius, y: height / 2 - radius),
            CGPoint(x: -width / 2 + radius, y: height / 2 - radius),
            CGPoint(x: -width / 2 + radius, y: -height / 2 + radius)
        ]
        return centers.enumerated().flatMap { index, center in
            (0...12).map { step in
                let angle = (-90 + Double(index) * 90 + Double(step) * 7.5) * .pi / 180
                return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            }
        }
    }
}
