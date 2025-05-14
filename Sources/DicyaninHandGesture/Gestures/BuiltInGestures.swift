/*
 * HandGestureKit
 * Created by Hunter Harris on 04/03/2025
 * Copyright © 2025 Dicyanin Labs. All rights reserved.
 */

import RealityKit
import ARKit

/// A gesture that detects when two fingers are pinched together
///
/// This gesture can be configured to detect pinches between any two fingers
/// on either hand. By default, it detects pinches between the index finger
/// and thumb on both hands.
///
/// Example usage:
/// ```swift
/// // Right hand index-thumb pinch
/// let rightPinch = PinchGesture(
///     finger1: .indexFingerTip,
///     finger2: .thumbTip,
///     handSide: .right
/// )
///
/// // Left hand index-pinky pinch
/// let leftPinch = PinchGesture(
///     finger1: .indexFingerTip,
///     finger2: .littleFingerTip,
///     handSide: .left
/// )
/// ```
public class PinchGesture: BaseHandGesture {
    private let finger1: HandSkeleton.JointName
    private let finger2: HandSkeleton.JointName
    private let minimumDistance: Float
    
    /// Creates a new pinch gesture
    /// - Parameters:
    ///   - finger1: The first finger to check
    ///   - finger2: The second finger to check
    ///   - handSide: Which hand(s) to detect the gesture on
    ///   - minimumDistance: The maximum distance between fingers to be considered a pinch
    ///   - requiredDuration: How long the gesture must be held to be considered active
    public init(finger1: HandSkeleton.JointName = .indexFingerTip,
                finger2: HandSkeleton.JointName = .thumbTip,
                handSide: HandSide = .both,
                minimumDistance: Float = 0.02,
                requiredDuration: TimeInterval = 0.5) {
        self.finger1 = finger1
        self.finger2 = finger2
        self.minimumDistance = minimumDistance
        super.init(name: "Pinch", handSide: handSide, requiredDuration: requiredDuration)
    }
    
    public override func checkGesture(hand: HandAnchor) -> Bool {
        guard let handSkeleton = hand.handSkeleton else { return false }
        
        let finger1Joint = handSkeleton.joint(finger1)
        let finger2Joint = handSkeleton.joint(finger2)
        let originTransform = hand.originFromAnchorTransform
        
        let finger1Transform = matrix_multiply(originTransform, finger1Joint.anchorFromJointTransform)
        let finger2Transform = matrix_multiply(originTransform, finger2Joint.anchorFromJointTransform)
        
        let finger1Pos = SIMD3<Float>(finger1Transform.columns.3.x,
                                     finger1Transform.columns.3.y,
                                     finger1Transform.columns.3.z)
        let finger2Pos = SIMD3<Float>(finger2Transform.columns.3.x,
                                     finger2Transform.columns.3.y,
                                     finger2Transform.columns.3.z)
        
        return simd_distance(finger1Pos, finger2Pos) < minimumDistance
    }
}

/// A gesture that detects when two fingers are held at a specific distance apart
///
/// This gesture can be used to detect when two fingers are held at a specific
/// distance range from each other. Useful for detecting "peace sign" or
/// "okay sign" type gestures.
///
/// Example usage:
/// ```swift
/// // Detect when index and middle fingers are held 5-10cm apart
/// let fingerDistance = FingerDistanceGesture(
///     finger1: .indexFingerTip,
///     finger2: .middleFingerTip,
///     minimumDistance: 0.05,
///     maximumDistance: 0.1
/// )
/// ```
public class FingerDistanceGesture: BaseHandGesture {
    private let finger1: HandSkeleton.JointName
    private let finger2: HandSkeleton.JointName
    private let minimumDistance: Float
    private let maximumDistance: Float
    
    /// Creates a new finger distance gesture
    /// - Parameters:
    ///   - finger1: The first finger to check
    ///   - finger2: The second finger to check
    ///   - handSide: Which hand(s) to detect the gesture on
    ///   - minimumDistance: The minimum distance between fingers to be considered active
    ///   - maximumDistance: The maximum distance between fingers to be considered active
    ///   - requiredDuration: How long the gesture must be held to be considered active
    public init(finger1: HandSkeleton.JointName,
                finger2: HandSkeleton.JointName,
                handSide: HandSide = .both,
                minimumDistance: Float = 0.0,
                maximumDistance: Float = 0.1,
                requiredDuration: TimeInterval = 0.5) {
        self.finger1 = finger1
        self.finger2 = finger2
        self.minimumDistance = minimumDistance
        self.maximumDistance = maximumDistance
        super.init(name: "FingerDistance", handSide: handSide, requiredDuration: requiredDuration)
    }
    
    public override func checkGesture(hand: HandAnchor) -> Bool {
        guard let handSkeleton = hand.handSkeleton,
              let positions = HandGestureDetector.shared.getFingerPositions(for: hand),
              let pos1 = positions[finger1],
              let pos2 = positions[finger2] else {
            return false
        }
        
        let distance = simd_distance(pos1, pos2)
        return distance >= minimumDistance && distance <= maximumDistance
    }
} 