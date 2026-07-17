import SwiftUI
import simd
#if canImport(RealityKit)
import RealityKit

/// A live 3D rendering of a `HandGesturePose` in a `RealityView`: spheres for
/// joints, capsule bones between them, slowly turning so depth reads at a
/// glance. Drop it next to (or overlaid on) the 2D editor; it tracks every drag
/// in real time. Available on visionOS, iOS 18, and macOS 15.
public struct HandSkeleton3DView: View {

    public var pose: HandGesturePose?
    public var autoRotate: Bool

    @State private var userYaw: Float = 0

    public init(pose: HandGesturePose?, autoRotate: Bool = true) {
        self.pose = pose
        self.autoRotate = autoRotate
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !autoRotate)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            RealityView { content in
                let root = Entity()
                root.name = "handRoot"
                content.add(root)
                camera(in: content)
            } update: { content in
                guard let root = content.entities.first(where: { $0.name == "handRoot" }) else { return }
                let spin = autoRotate ? Float(time.truncatingRemainder(dividingBy: 360)) * 0.6 : 0
                root.orientation = simd_quatf(angle: userYaw + spin, axis: [0, 1, 0])
                // Center the hand vertically so it spins about its middle.
                root.position = [0, -0.09, 0]
                Self.sync(pose: pose, into: root)
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        userYaw += Float(value.translation.width - lastDragX) * 0.012
                        lastDragX = value.translation.width
                    }
                    .onEnded { _ in lastDragX = 0 }
            )
        }
    }

    @State private var lastDragX: CGFloat = 0

    private func camera(in content: some RealityViewContentProtocol) {
        #if !os(visionOS)
        // Flat platforms need an explicit camera; visionOS composites in space.
        let camera = PerspectiveCamera()
        camera.position = [0, 0, 0.35]
        content.add(camera)
        #endif
    }

    // MARK: - Scene sync

    static let jointRadius: Float = 0.005
    static let boneRadius: Float = 0.0028

    /// Creates or moves joint spheres and bone capsules to mirror the pose.
    /// Entities are cached by name so per frame updates are transform only.
    static func sync(pose: HandGesturePose?, into root: Entity) {
        guard let pose else {
            root.children.forEach { $0.isEnabled = false }
            return
        }
        root.children.forEach { $0.isEnabled = true }

        for joint in HandGesturePose.Joint.allCases {
            let name = "j:\(joint.rawValue)"
            let existing = root.findEntity(named: name)
            guard let p = pose.joints[joint] else {
                existing?.isEnabled = false
                continue
            }
            let entity = existing ?? {
                let radius = joint == .wrist ? jointRadius * 1.7 : jointRadius
                let color: SimpleMaterial.Color = joint == .wrist ? .orange : .cyan
                let e = ModelEntity(
                    mesh: .generateSphere(radius: radius),
                    materials: [SimpleMaterial(color: color, roughness: 0.35, isMetallic: false)]
                )
                e.name = name
                root.addChild(e)
                return e
            }()
            entity.isEnabled = true
            entity.position = p
        }

        for (i, bone) in HandSkeleton2DView.bones.enumerated() {
            let name = "b:\(i)"
            let existing = root.findEntity(named: name)
            guard let a = pose.joints[bone.0], let b = pose.joints[bone.1] else {
                existing?.isEnabled = false
                continue
            }
            let entity = existing ?? {
                // Unit height cylinder, scaled per frame to the bone length.
                let e = ModelEntity(
                    mesh: .generateCylinder(height: 1, radius: boneRadius),
                    materials: [SimpleMaterial(color: .white.withAlphaComponent(0.85), roughness: 0.5, isMetallic: false)]
                )
                e.name = name
                root.addChild(e)
                return e
            }()
            entity.isEnabled = true
            let delta = b - a
            let length = simd_length(delta)
            guard length > 0.0001 else {
                entity.isEnabled = false
                continue
            }
            entity.position = (a + b) * 0.5
            entity.orientation = simd_quatf(from: [0, 1, 0], to: delta / length)
            entity.scale = [1, length, 1]
        }
    }
}
#endif
