import Foundation
import simd

/// One captured hand pose: the 3D position of every tracked joint, expressed in
/// wrist local space so the pose is invariant to where the hand was in the room
/// and which way it was facing. This is the unit that gets compared and exported.
public struct HandGesturePose: Codable, Equatable, Sendable {

    /// The 26 ARKit hand joints, named so JSON stays human readable and portable.
    public enum Joint: String, Codable, CaseIterable, Sendable {
        case wrist
        case thumbKnuckle, thumbIntermediateBase, thumbIntermediateTip, thumbTip
        case indexFingerMetacarpal, indexFingerKnuckle, indexFingerIntermediateBase, indexFingerIntermediateTip, indexFingerTip
        case middleFingerMetacarpal, middleFingerKnuckle, middleFingerIntermediateBase, middleFingerIntermediateTip, middleFingerTip
        case ringFingerMetacarpal, ringFingerKnuckle, ringFingerIntermediateBase, ringFingerIntermediateTip, ringFingerTip
        case littleFingerMetacarpal, littleFingerKnuckle, littleFingerIntermediateBase, littleFingerIntermediateTip, littleFingerTip
        case forearmWrist, forearmArm
    }

    public enum Chirality: String, Codable, Sendable {
        case left, right, either
    }

    /// Joint positions in wrist local space (meters). Wrist is at the origin.
    public var joints: [Joint: SIMD3<Float>]

    /// Which hand produced this pose.
    public var chirality: Chirality

    public init(joints: [Joint: SIMD3<Float>], chirality: Chirality) {
        self.joints = joints
        self.chirality = chirality
    }

    // Codable: encode the joint map as a plain [String: [Float]] for clean JSON.
    private enum CodingKeys: String, CodingKey { case joints, chirality }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chirality = try c.decode(Chirality.self, forKey: .chirality)
        let raw = try c.decode([String: [Float]].self, forKey: .joints)
        var map: [Joint: SIMD3<Float>] = [:]
        for (key, value) in raw where value.count == 3 {
            if let joint = Joint(rawValue: key) {
                map[joint] = SIMD3<Float>(value[0], value[1], value[2])
            }
        }
        joints = map
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(chirality, forKey: .chirality)
        var raw: [String: [Float]] = [:]
        for (joint, p) in joints { raw[joint.rawValue] = [p.x, p.y, p.z] }
        try c.encode(raw, forKey: .joints)
    }
}

public extension HandGesturePose {

    /// Hand span used to normalize deviation so big and small hands match the
    /// same gesture. Wrist to middle finger tip distance, fallback 0.18m.
    var scale: Float {
        guard let tip = joints[.middleFingerTip] else { return 0.18 }
        let d = simd_length(tip)
        return d > 0.0001 ? d : 0.18
    }

    /// Scale invariant per joint distance to another pose, averaged over the
    /// joints both poses share. Lower is a closer match. Returns nil if there is
    /// nothing to compare.
    func deviation(to other: HandGesturePose) -> Float? {
        let s = (scale + other.scale) * 0.5
        guard s > 0.0001 else { return nil }
        var total: Float = 0
        var count = 0
        for joint in Joint.allCases {
            guard let a = joints[joint], let b = other.joints[joint] else { continue }
            total += simd_length(a - b)
            count += 1
        }
        guard count > 0 else { return nil }
        return (total / Float(count)) / s
    }
}
