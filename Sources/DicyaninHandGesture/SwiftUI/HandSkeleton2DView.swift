import SwiftUI
import simd

/// A 2D rendering of a `HandGesturePose`: every joint as a dot and the bones
/// between them as lines, projected from wrist local space onto a flat plane. A
/// small axis marker shows the wrist orientation. Pure SwiftUI Canvas, works on
/// every platform.
public struct HandSkeleton2DView: View {

    public var pose: HandGesturePose?
    public var showLabels: Bool
    public var tint: Color

    public init(pose: HandGesturePose?, showLabels: Bool = false, tint: Color = .accentColor) {
        self.pose = pose
        self.showLabels = showLabels
        self.tint = tint
    }

    /// Bone connectivity used to draw the hand outline.
    static let bones: [(HandGesturePose.Joint, HandGesturePose.Joint)] = [
        (.wrist, .thumbKnuckle), (.thumbKnuckle, .thumbIntermediateBase), (.thumbIntermediateBase, .thumbIntermediateTip), (.thumbIntermediateTip, .thumbTip),
        (.wrist, .indexFingerMetacarpal), (.indexFingerMetacarpal, .indexFingerKnuckle), (.indexFingerKnuckle, .indexFingerIntermediateBase), (.indexFingerIntermediateBase, .indexFingerIntermediateTip), (.indexFingerIntermediateTip, .indexFingerTip),
        (.wrist, .middleFingerMetacarpal), (.middleFingerMetacarpal, .middleFingerKnuckle), (.middleFingerKnuckle, .middleFingerIntermediateBase), (.middleFingerIntermediateBase, .middleFingerIntermediateTip), (.middleFingerIntermediateTip, .middleFingerTip),
        (.wrist, .ringFingerMetacarpal), (.ringFingerMetacarpal, .ringFingerKnuckle), (.ringFingerKnuckle, .ringFingerIntermediateBase), (.ringFingerIntermediateBase, .ringFingerIntermediateTip), (.ringFingerIntermediateTip, .ringFingerTip),
        (.wrist, .littleFingerMetacarpal), (.littleFingerMetacarpal, .littleFingerKnuckle), (.littleFingerKnuckle, .littleFingerIntermediateBase), (.littleFingerIntermediateBase, .littleFingerIntermediateTip), (.littleFingerIntermediateTip, .littleFingerTip)
    ]

    public var body: some View {
        GeometryReader { geo in
            if let pose, !pose.joints.isEmpty {
                let layout = Layout(pose: pose, size: geo.size)
                Canvas { ctx, _ in
                    for bone in Self.bones {
                        guard let a = layout.point(bone.0), let b = layout.point(bone.1) else { continue }
                        var path = Path()
                        path.move(to: a)
                        path.addLine(to: b)
                        ctx.stroke(path, with: .color(tint.opacity(0.55)), lineWidth: 3)
                    }
                    for joint in HandGesturePose.Joint.allCases {
                        guard let p = layout.point(joint) else { continue }
                        let r: CGFloat = joint == .wrist ? 7 : 4
                        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                        ctx.fill(Circle().path(in: rect), with: .color(joint == .wrist ? .orange : tint))
                        if showLabels {
                            ctx.draw(Text(joint.rawValue).font(.system(size: 7)).foregroundColor(.secondary), at: CGPoint(x: p.x + 6, y: p.y))
                        }
                    }
                }
            } else {
                ContentUnavailablePlaceholder()
            }
        }
    }

    /// Projects wrist local 3D points to view space. Uses the X/Y plane (palm
    /// facing the camera) and fits the bounding box into the view with padding.
    struct Layout {
        var projected: [HandGesturePose.Joint: CGPoint] = [:]

        init(pose: HandGesturePose, size: CGSize) {
            var raw: [HandGesturePose.Joint: CGPoint] = [:]
            var minX: Float = .greatestFiniteMagnitude, minY: Float = .greatestFiniteMagnitude
            var maxX: Float = -.greatestFiniteMagnitude, maxY: Float = -.greatestFiniteMagnitude
            for (joint, p) in pose.joints {
                let x = pose.chirality == .left ? -p.x : p.x
                let y = p.y
                raw[joint] = CGPoint(x: CGFloat(x), y: CGFloat(y))
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
            let pad: CGFloat = 24
            let spanX = CGFloat(max(maxX - minX, 0.0001))
            let spanY = CGFloat(max(maxY - minY, 0.0001))
            let scale = min((size.width - pad * 2) / spanX, (size.height - pad * 2) / spanY)
            let offX = (size.width - spanX * scale) / 2
            let offY = (size.height - spanY * scale) / 2
            for (joint, p) in raw {
                let vx = offX + (p.x - CGFloat(minX)) * scale
                // Flip Y so up in the world is up on screen.
                let vy = size.height - (offY + (p.y - CGFloat(minY)) * scale)
                projected[joint] = CGPoint(x: vx, y: vy)
            }
        }

        func point(_ joint: HandGesturePose.Joint) -> CGPoint? { projected[joint] }
    }
}

private struct ContentUnavailablePlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(.quaternary.opacity(0.4))
            VStack(spacing: 8) {
                Image(systemName: "hand.raised.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No hand detected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
