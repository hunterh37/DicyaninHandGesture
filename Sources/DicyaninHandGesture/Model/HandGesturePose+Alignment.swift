import Foundation
import simd

/// Orientation normalization so editor built poses (fingers +Y, palm +Z) match
/// live ARKit poses regardless of the wrist joint's axis convention, and so a
/// rolled wrist still matches the recorded gesture.
public extension HandGesturePose {

    /// A canonical orientation for this pose: middle finger knuckle direction
    /// becomes +Y, and the index-to-little knuckle line defines the palm plane
    /// so the palm normal becomes +Z. Returns the pose unchanged when the frame
    /// joints are missing (sparse poses degrade gracefully).
    func normalized() -> HandGesturePose {
        guard
            let middle = joints[.middleFingerKnuckle] ?? joints[.middleFingerMetacarpal],
            let index = joints[.indexFingerKnuckle] ?? joints[.indexFingerMetacarpal],
            let little = joints[.littleFingerKnuckle] ?? joints[.littleFingerMetacarpal],
            simd_length(middle) > 0.0001
        else { return self }

        let yAxis = simd_normalize(middle)
        // Index sits on -X for a right hand in our convention; flip for left so
        // both chiralities normalize into their own consistent frames.
        var xRaw = little - index
        if chirality == .left { xRaw = -xRaw }
        guard simd_length(xRaw) > 0.0001 else { return self }
        var zAxis = simd_cross(xRaw, yAxis)
        guard simd_length(zAxis) > 0.0001 else { return self }
        zAxis = simd_normalize(zAxis)
        let xAxis = simd_normalize(simd_cross(yAxis, zAxis))

        // Columns are the canonical axes expressed in pose space; transpose maps
        // pose space back into the canonical frame.
        let rotation = simd_transpose(simd_float3x3(xAxis, yAxis, zAxis))
        var out: [Joint: SIMD3<Float>] = [:]
        for (joint, p) in joints { out[joint] = rotation * p }
        return HandGesturePose(joints: out, chirality: chirality)
    }

    /// Deviation after rotating both poses into the canonical frame, making the
    /// comparison invariant to wrist orientation and axis conventions.
    func alignedDeviation(to other: HandGesturePose) -> Float? {
        normalized().deviation(to: other.normalized())
    }

    /// This pose reflected across X, becoming the opposite hand. A right hand
    /// gesture mirrored this way is what the same gesture looks like performed
    /// with the left hand.
    func mirrored() -> HandGesturePose {
        var out: [Joint: SIMD3<Float>] = [:]
        for (j, p) in joints { out[j] = SIMD3<Float>(-p.x, p.y, p.z) }
        let flipped: Chirality = chirality == .left ? .right : (chirality == .right ? .left : .either)
        return HandGesturePose(joints: out, chirality: flipped)
    }

    /// Deviation used for gesture matching: aligned, and when the hands differ
    /// (or either side is match-any) the mirrored comparison is also tried and
    /// the closer one wins, so one recording serves both hands.
    func matchDeviation(to live: HandGesturePose) -> Float? {
        let direct = alignedDeviation(to: live)
        let crossHanded = chirality == .either || live.chirality == .either || chirality != live.chirality
        guard crossHanded else { return direct }
        let mirroredDev = alignedDeviation(to: live.mirrored())
        switch (direct, mirroredDev) {
        case let (d?, m?): return min(d, m)
        case let (d?, nil): return d
        case let (nil, m?): return m
        case (nil, nil): return nil
        }
    }
}
