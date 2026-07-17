import SwiftUI
import simd

/// The interactive 2D hand editor: renders the pose as a skeleton (palm facing
/// the camera) and lets the user grab any knuckle or finger joint and drag it.
/// Drags are solved through the pose template, so fingers bend and spread
/// naturally instead of joints flying apart. Works on visionOS, iOS, and macOS.
public struct HandPoseEditor2DView: View {

    @ObservedObject var model: HandPoseEditorModel
    @State private var draggedJoint: HandGesturePose.Joint?

    public init(model: HandPoseEditorModel) {
        self.model = model
    }

    /// Fixed world window (meters, wrist local) so the mapping is stable while
    /// dragging. Covers both chiralities with headroom for splayed thumbs.
    private nonisolated static let worldRect = CGRect(x: -0.135, y: -0.035, width: 0.27, height: 0.27)

    public var body: some View {
        GeometryReader { geo in
            let mapping = Mapping(size: geo.size)
            ZStack {
                Canvas { ctx, _ in
                    draw(in: &ctx, mapping: mapping)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(mapping: mapping))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Drawing

    private func draw(in ctx: inout GraphicsContext, mapping: Mapping) {
        let pose = model.pose
        for bone in HandSkeleton2DView.bones {
            guard let a = pose.joints[bone.0], let b = pose.joints[bone.1] else { continue }
            var path = Path()
            path.move(to: mapping.toView(a))
            path.addLine(to: mapping.toView(b))
            ctx.stroke(path, with: .color(.accentColor.opacity(0.55)), lineWidth: 4)
        }
        for joint in HandGesturePose.Joint.allCases {
            guard let p = pose.joints[joint] else { continue }
            let point = mapping.toView(p)
            let draggable = HandPoseEditorModel.isDraggable(joint)
            let active = joint == draggedJoint
            let r: CGFloat = joint == .wrist ? 8 : (draggable ? (active ? 9 : 6.5) : 3.5)
            let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
            let color: Color = joint == .wrist ? .orange : (draggable ? (active ? .yellow : .accentColor) : .secondary)
            ctx.fill(Circle().path(in: rect), with: .color(color))
            if draggable {
                ctx.stroke(Circle().path(in: rect.insetBy(dx: -2.5, dy: -2.5)), with: .color(.white.opacity(active ? 0.9 : 0.35)), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Dragging

    private func dragGesture(mapping: Mapping) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if draggedJoint == nil {
                    draggedJoint = nearestDraggableJoint(to: value.startLocation, mapping: mapping)
                }
                guard let joint = draggedJoint else { return }
                let world = mapping.toWorld(value.location)
                model.drag(joint: joint, toward: world)
            }
            .onEnded { _ in draggedJoint = nil }
    }

    private func nearestDraggableJoint(to point: CGPoint, mapping: Mapping) -> HandGesturePose.Joint? {
        var best: (HandGesturePose.Joint, CGFloat)?
        for (joint, p) in model.pose.joints where HandPoseEditorModel.isDraggable(joint) {
            let v = mapping.toView(p)
            let d = hypot(v.x - point.x, v.y - point.y)
            if d < 28, d < (best?.1 ?? .greatestFiniteMagnitude) {
                best = (joint, d)
            }
        }
        return best?.0
    }

    // MARK: - Coordinate mapping

    /// Stable view <-> world transform: orthographic, X/Y plane, Y flipped so up
    /// in wrist space is up on screen.
    nonisolated struct Mapping {
        let scale: CGFloat
        let offset: CGPoint
        let size: CGSize

        init(size: CGSize) {
            self.size = size
            let rect = HandPoseEditor2DView.worldRect
            scale = min(size.width / rect.width, size.height / rect.height)
            offset = CGPoint(
                x: (size.width - rect.width * scale) / 2 - rect.minX * scale,
                y: (size.height - rect.height * scale) / 2 - rect.minY * scale
            )
        }

        func toView(_ p: SIMD3<Float>) -> CGPoint {
            CGPoint(
                x: CGFloat(p.x) * scale + offset.x,
                y: size.height - (CGFloat(p.y) * scale + offset.y)
            )
        }

        func toWorld(_ p: CGPoint) -> SIMD3<Float> {
            SIMD3<Float>(
                Float((p.x - offset.x) / scale),
                Float((size.height - p.y - offset.y) / scale),
                0
            )
        }
    }
}
