import Foundation
import simd

#if os(visionOS)
import ARKit

/// Bridges ARKit hand tracking to `HandGesturePose`. Feed it `HandAnchor`s from a
/// `HandTrackingProvider` loop; it produces wrist local poses ready to capture or
/// match.
public enum HandGestureRecorder {

    /// Maps our portable joint names to ARKit joint names.
    static let jointMap: [HandGesturePose.Joint: HandSkeleton.JointName] = [
        .wrist: .wrist,
        .thumbKnuckle: .thumbKnuckle,
        .thumbIntermediateBase: .thumbIntermediateBase,
        .thumbIntermediateTip: .thumbIntermediateTip,
        .thumbTip: .thumbTip,
        .indexFingerMetacarpal: .indexFingerMetacarpal,
        .indexFingerKnuckle: .indexFingerKnuckle,
        .indexFingerIntermediateBase: .indexFingerIntermediateBase,
        .indexFingerIntermediateTip: .indexFingerIntermediateTip,
        .indexFingerTip: .indexFingerTip,
        .middleFingerMetacarpal: .middleFingerMetacarpal,
        .middleFingerKnuckle: .middleFingerKnuckle,
        .middleFingerIntermediateBase: .middleFingerIntermediateBase,
        .middleFingerIntermediateTip: .middleFingerIntermediateTip,
        .middleFingerTip: .middleFingerTip,
        .ringFingerMetacarpal: .ringFingerMetacarpal,
        .ringFingerKnuckle: .ringFingerKnuckle,
        .ringFingerIntermediateBase: .ringFingerIntermediateBase,
        .ringFingerIntermediateTip: .ringFingerIntermediateTip,
        .ringFingerTip: .ringFingerTip,
        .littleFingerMetacarpal: .littleFingerMetacarpal,
        .littleFingerKnuckle: .littleFingerKnuckle,
        .littleFingerIntermediateBase: .littleFingerIntermediateBase,
        .littleFingerIntermediateTip: .littleFingerIntermediateTip,
        .littleFingerTip: .littleFingerTip,
        .forearmWrist: .forearmWrist,
        .forearmArm: .forearmArm
    ]

    /// Builds a wrist local pose from a hand anchor, or nil if not tracked.
    /// Every joint is transformed into the wrist coordinate frame, so the result
    /// is invariant to hand position and orientation in the room.
    public static func pose(from anchor: HandAnchor) -> HandGesturePose? {
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else { return nil }

        let wristFromOrigin = skeleton.joint(.wrist).anchorFromJointTransform
        let originFromWrist = wristFromOrigin.inverse

        var joints: [HandGesturePose.Joint: SIMD3<Float>] = [:]
        for (joint, arName) in jointMap {
            let j = skeleton.joint(arName)
            guard j.isTracked else { continue }
            let local = originFromWrist * j.anchorFromJointTransform
            joints[joint] = SIMD3<Float>(local.columns.3.x, local.columns.3.y, local.columns.3.z)
        }
        guard !joints.isEmpty else { return nil }

        let chirality: HandGesturePose.Chirality = anchor.chirality == .left ? .left : .right
        return HandGesturePose(joints: joints, chirality: chirality)
    }

    /// Builds a wrist local pose from raw anchor-from-joint transforms, the shape
    /// exposed by DicyaninMockHandTracking (`leftHandJoints` / `rightHandJoints`).
    /// This lets gesture capture and matching piggyback off mocked or webcam
    /// driven hands with no ARKit session.
    public static func pose(
        jointTransforms: [HandSkeleton.JointName: simd_float4x4],
        chirality: HandGesturePose.Chirality
    ) -> HandGesturePose? {
        guard let wristFromOrigin = jointTransforms[.wrist] else { return nil }
        let originFromWrist = wristFromOrigin.inverse

        var joints: [HandGesturePose.Joint: SIMD3<Float>] = [:]
        for (joint, arName) in jointMap {
            guard let t = jointTransforms[arName] else { continue }
            let local = originFromWrist * t
            joints[joint] = SIMD3<Float>(local.columns.3.x, local.columns.3.y, local.columns.3.z)
        }
        guard !joints.isEmpty else { return nil }
        return HandGesturePose(joints: joints, chirality: chirality)
    }
}
#endif
