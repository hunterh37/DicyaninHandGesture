import Foundation
import simd

/// A procedural hand model: five fingers, each described by just two parameters
/// (curl and splay), that generates a full anatomically plausible
/// `HandGesturePose`. This is what makes a 2D drag editor possible: instead of
/// letting users move 26 joints freely into impossible shapes, dragging a joint
/// solves for the finger's curl/splay and the whole chain follows naturally.
///
/// Coordinate convention (right hand): wrist at origin, fingers along +Y, palm
/// normal along +Z (palm facing the viewer), thumb on the -X side. Left hands
/// are mirrored across X. Matching against live ARKit poses is orientation
/// independent thanks to `HandGesturePose.normalized()`.
public struct HandPoseTemplate: Equatable, Sendable {

    public enum Finger: String, CaseIterable, Identifiable, Sendable {
        case thumb, index, middle, ring, little
        public var id: String { rawValue }
    }

    /// The two degrees of freedom per finger.
    /// - curl: 0 fully straight, 1 fully bent into the palm.
    /// - splay: -1...1 side to side spread around the finger's rest direction.
    public struct FingerShape: Equatable, Sendable {
        public var curl: Float
        public var splay: Float
        public init(curl: Float = 0, splay: Float = 0) {
            self.curl = curl
            self.splay = splay
        }
    }

    public var chirality: HandGesturePose.Chirality
    public var fingers: [Finger: FingerShape]

    public init(
        chirality: HandGesturePose.Chirality = .right,
        fingers: [Finger: FingerShape] = [:]
    ) {
        self.chirality = chirality
        var full: [Finger: FingerShape] = [:]
        for f in Finger.allCases { full[f] = fingers[f] ?? FingerShape() }
        self.fingers = full
    }

    public subscript(finger: Finger) -> FingerShape {
        get { fingers[finger] ?? FingerShape() }
        set { fingers[finger] = newValue }
    }

    // MARK: - Anatomy (right hand, meters)

    struct FingerSpec {
        var knuckle: SIMD3<Float>          // knuckle offset from wrist
        var segments: [Float]              // proximal, intermediate, distal lengths
        var baseSplayDeg: Float            // rest direction, rotation about +Z from +Y
        var maxSplayDeg: Float             // splay range at splay = +/-1
        var bendDeg: [Float]               // per segment bend at curl = 1
        var curlDirection: SIMD3<Float>    // direction segments bend toward
        var chainJoints: [HandGesturePose.Joint]
        var metacarpal: HandGesturePose.Joint?
    }

    static let specs: [Finger: FingerSpec] = [
        .thumb: FingerSpec(
            knuckle: [-0.030, 0.020, 0.010],
            segments: [0.046, 0.032, 0.028],
            baseSplayDeg: 55, maxSplayDeg: 25,
            bendDeg: [35, 40, 70],
            curlDirection: simd_normalize(SIMD3<Float>(0.8, -0.3, 0.5)),
            chainJoints: [.thumbIntermediateBase, .thumbIntermediateTip, .thumbTip],
            metacarpal: nil
        ),
        .index: FingerSpec(
            knuckle: [-0.030, 0.088, 0],
            segments: [0.042, 0.026, 0.022],
            baseSplayDeg: 4, maxSplayDeg: 15,
            bendDeg: [80, 95, 60],
            curlDirection: [0, 0, 1],
            chainJoints: [.indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip],
            metacarpal: .indexFingerMetacarpal
        ),
        .middle: FingerSpec(
            knuckle: [-0.010, 0.092, 0],
            segments: [0.046, 0.030, 0.023],
            baseSplayDeg: 0, maxSplayDeg: 12,
            bendDeg: [80, 95, 60],
            curlDirection: [0, 0, 1],
            chainJoints: [.middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip],
            metacarpal: .middleFingerMetacarpal
        ),
        .ring: FingerSpec(
            knuckle: [0.010, 0.088, 0],
            segments: [0.042, 0.028, 0.022],
            baseSplayDeg: -4, maxSplayDeg: 12,
            bendDeg: [80, 95, 60],
            curlDirection: [0, 0, 1],
            chainJoints: [.ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip],
            metacarpal: .ringFingerMetacarpal
        ),
        .little: FingerSpec(
            knuckle: [0.030, 0.080, 0],
            segments: [0.033, 0.021, 0.019],
            baseSplayDeg: -9, maxSplayDeg: 20,
            bendDeg: [80, 95, 60],
            curlDirection: [0, 0, 1],
            chainJoints: [.littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip],
            metacarpal: .littleFingerMetacarpal
        )
    ]

    static func knuckleJoint(for finger: Finger) -> HandGesturePose.Joint {
        switch finger {
        case .thumb: return .thumbKnuckle
        case .index: return .indexFingerKnuckle
        case .middle: return .middleFingerKnuckle
        case .ring: return .ringFingerKnuckle
        case .little: return .littleFingerKnuckle
        }
    }

    /// Which finger and chain depth a joint belongs to. Depth 0 is the knuckle,
    /// -1 the metacarpal, 1...3 the segments out to the fingertip.
    public static func fingerAndDepth(of joint: HandGesturePose.Joint) -> (finger: Finger, depth: Int)? {
        for finger in Finger.allCases {
            guard let spec = specs[finger] else { continue }
            if joint == spec.metacarpal { return (finger, -1) }
            if joint == knuckleJoint(for: finger) { return (finger, 0) }
            if let i = spec.chainJoints.firstIndex(of: joint) { return (finger, i + 1) }
        }
        return nil
    }

    // MARK: - Forward kinematics

    /// Joint positions for one finger in right hand space, indexed by chain
    /// depth: [knuckle, intermediate base, intermediate tip, fingertip].
    static func chainPositions(finger: Finger, shape: FingerShape) -> [SIMD3<Float>] {
        guard let spec = specs[finger] else { return [] }
        let splayRad = (spec.baseSplayDeg + shape.splay.clamped(-1, 1) * spec.maxSplayDeg) * .pi / 180
        // Positive Z rotation moves +Y toward -X (thumb side of a right hand).
        var dir = simd_act(simd_quatf(angle: splayRad, axis: [0, 0, 1]), SIMD3<Float>(0, 1, 0))
        var axis = simd_cross(dir, spec.curlDirection)
        axis = simd_length(axis) > 0.0001 ? simd_normalize(axis) : SIMD3<Float>(1, 0, 0)

        var positions: [SIMD3<Float>] = [spec.knuckle]
        var p = spec.knuckle
        let curl = shape.curl.clamped(0, 1)
        for (i, length) in spec.segments.enumerated() {
            let bend = spec.bendDeg[i] * curl * .pi / 180
            dir = simd_act(simd_quatf(angle: bend, axis: axis), dir)
            p += dir * length
            positions.append(p)
        }
        return positions
    }

    /// The full generated pose, mirrored for left hands.
    public func pose() -> HandGesturePose {
        var joints: [HandGesturePose.Joint: SIMD3<Float>] = [.wrist: .zero]
        for finger in Finger.allCases {
            guard let spec = Self.specs[finger] else { continue }
            let chain = Self.chainPositions(finger: finger, shape: self[finger])
            guard chain.count == 4 else { continue }
            if let meta = spec.metacarpal { joints[meta] = spec.knuckle * 0.35 }
            joints[Self.knuckleJoint(for: finger)] = chain[0]
            for (i, joint) in spec.chainJoints.enumerated() { joints[joint] = chain[i + 1] }
        }
        if chirality == .left {
            for (j, p) in joints { joints[j] = SIMD3<Float>(-p.x, p.y, p.z) }
        }
        return HandGesturePose(joints: joints, chirality: chirality)
    }

    // MARK: - Inverse fitting (drag support)

    /// Solves curl and splay so the given chain joint lands as close as possible
    /// to a target point, expressed in right hand space (callers mirror X for
    /// left hands before calling).
    /// Depth 0 or -1 adjusts splay only; 1...3 adjusts curl and splay.
    public mutating func drag(finger: Finger, depth: Int, toward target: SIMD3<Float>) {
        guard let spec = Self.specs[finger] else { return }
        var shape = self[finger]
        let local = target - spec.knuckle

        if simd_length(SIMD2<Float>(local.x, local.y)) > 0.005 {
            // Splay from the in-plane angle of knuckle -> target vs rest direction.
            let angleDeg = atan2(-local.x, local.y) * 180 / .pi
            shape.splay = ((angleDeg - spec.baseSplayDeg) / spec.maxSplayDeg).clamped(-1, 1)
        }

        if depth >= 1 {
            // 1D search over curl for the value that puts the dragged joint
            // nearest the target in the editing plane.
            let idx = min(depth, 3)
            var bestCurl = shape.curl
            var bestErr = Float.greatestFiniteMagnitude
            for step in 0...40 {
                var candidate = shape
                candidate.curl = Float(step) / 40
                let chain = Self.chainPositions(finger: finger, shape: candidate)
                let p = chain[idx]
                // 2D editor targets live in the Z = 0 plane; fitted captures
                // carry real depth, so use it when present.
                let err = abs(target.z) > 0.001
                    ? simd_length(p - target)
                    : simd_length(SIMD2<Float>(p.x, p.y) - SIMD2<Float>(target.x, target.y))
                if err < bestErr {
                    bestErr = err
                    bestCurl = candidate.curl
                }
            }
            shape.curl = bestCurl
        }
        self[finger] = shape
    }

    /// Best effort fit of template parameters to an arbitrary pose, used to seed
    /// the editor from a captured or imported gesture.
    public static func fitted(to pose: HandGesturePose) -> HandPoseTemplate {
        var template = HandPoseTemplate(chirality: pose.chirality == .left ? .left : .right)
        let mirror: Float = template.chirality == .left ? -1 : 1
        for finger in Finger.allCases {
            guard let spec = specs[finger],
                  let tip = pose.joints[spec.chainJoints[2]] else { continue }
            let target = SIMD3<Float>(tip.x * mirror, tip.y, tip.z)
            template.drag(finger: finger, depth: 3, toward: target)
        }
        return template
    }

    // MARK: - Presets

    public enum PresetName: String, CaseIterable, Identifiable, Sendable {
        case open, fist, point, peace, thumbsUp, pinch
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .thumbsUp: return "Thumbs Up"
            default: return rawValue.capitalized
            }
        }
    }

    public static func preset(_ name: PresetName, chirality: HandGesturePose.Chirality = .right) -> HandPoseTemplate {
        var t = HandPoseTemplate(chirality: chirality)
        switch name {
        case .open:
            break
        case .fist:
            for f in Finger.allCases { t[f] = FingerShape(curl: f == .thumb ? 0.8 : 1) }
        case .point:
            for f in Finger.allCases { t[f] = FingerShape(curl: 1) }
            t[.index] = FingerShape(curl: 0)
            t[.thumb] = FingerShape(curl: 0.6)
        case .peace:
            for f in Finger.allCases { t[f] = FingerShape(curl: 1) }
            t[.index] = FingerShape(curl: 0, splay: 0.7)
            t[.middle] = FingerShape(curl: 0, splay: -0.7)
            t[.thumb] = FingerShape(curl: 0.7)
        case .thumbsUp:
            for f in Finger.allCases { t[f] = FingerShape(curl: 1) }
            t[.thumb] = FingerShape(curl: 0, splay: 0.6)
        case .pinch:
            t[.thumb] = FingerShape(curl: 0.55)
            t[.index] = FingerShape(curl: 0.55)
            t[.middle] = FingerShape(curl: 0.25)
            t[.ring] = FingerShape(curl: 0.25)
            t[.little] = FingerShape(curl: 0.25)
        }
        return t
    }
}

extension Float {
    func clamped(_ lo: Float, _ hi: Float) -> Float { Swift.min(Swift.max(self, lo), hi) }
}
