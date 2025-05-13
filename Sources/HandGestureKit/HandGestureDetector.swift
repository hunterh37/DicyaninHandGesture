/*
 * HandGestureKit
 * Created by Hunter Harris on 04/03/2025
 * Copyright © 2025 Dicyanin Labs. All rights reserved.
 */

import RealityKit
import ARKit
import Combine
import DicyaninARKitSession

/// A class that manages hand tracking and gesture detection in visionOS and iOS applications.
///
/// `HandGestureDetector` provides a clean, reusable interface for working with ARKit's hand tracking capabilities.
/// It supports multiple concurrent gestures, hand-specific detection, and customizable gesture parameters.
///
/// Example usage:
/// ```swift
/// let detector = HandGestureDetector.shared
/// let pinchGesture = PinchGesture(handSide: .right)
/// detector.addGesture(pinchGesture) { isActive in
///     // Handle pinch gesture state
/// }
/// ```
public class HandGestureDetector: ObservableObject {
    /// Shared instance of the detector for easy access throughout the app
    public static let shared = HandGestureDetector()
    
    @Published public private(set) var latestHandTracking: HandAnchorUpdate = .init()
    @Published public var isRightHanded = true
    
    private let handUpdateQueue_dominant = DispatchQueue(label: "handgesturekit.domHandUpdateQueue", qos: .userInteractive)
    private let handUpdateQueue_nonDominant = DispatchQueue(label: "handgesturekit.nonDomHandUpdateQueue", qos: .userInteractive)
    
    private var gestures: [HandGesture] = []
    private var gestureCallbacks: [String: (Bool) -> Void] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    /// Creates a new instance of the hand gesture detector
    public init() {
        setupHandTrackingSubscription()
    }
    
    private func setupHandTrackingSubscription() {
        ARKitSessionManager.shared.handTrackingUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.latestHandTracking = update
                
                // Update gestures for both hands
                if let leftHand = update.left {
                    self?.updateGestures(hand: leftHand)
                }
                if let rightHand = update.right {
                    self?.updateGestures(hand: rightHand)
                }
            }
            .store(in: &cancellables)
    }
    
    /// Starts hand tracking and gesture detection
    /// - Throws: `ARKitSessionError.handTrackingNotSupported` if the device doesn't support hand tracking
    public func start() async throws {
        try await ARKitSessionManager.shared.start()
    }
    
    /// Stops hand tracking and gesture detection
    public func stop() {
        ARKitSessionManager.shared.stop()
    }
    
    // MARK: - Gesture Management
    
    /// Adds a gesture to be tracked
    /// - Parameters:
    ///   - gesture: The gesture to track
    ///   - onStateChange: Optional callback for when the gesture state changes
    public func addGesture(_ gesture: HandGesture, onStateChange: ((Bool) -> Void)? = nil) {
        gestures.append(gesture)
        if let callback = onStateChange {
            gestureCallbacks[gesture.name] = callback
        }
    }
    
    /// Removes a gesture from tracking
    /// - Parameter name: The name of the gesture to remove
    public func removeGesture(named name: String) {
        gestures.removeAll { $0.name == name }
        gestureCallbacks.removeValue(forKey: name)
    }
    
    private func updateGestures(hand: HandAnchor) {
        for gesture in gestures {
            let wasActive = gesture.isActive
            let isActive = gesture.update(hand: hand)
            
            if wasActive != isActive {
                DispatchQueue.main.async { [weak self] in
                    self?.gestureCallbacks[gesture.name]?(isActive)
                }
            }
        }
    }
    
    // MARK: - Gesture Detection
    
    /// Checks if a pinch gesture is being performed
    /// - Parameters:
    ///   - hand: The hand to check
    ///   - minimumDistance: The maximum distance between fingers to be considered a pinch
    /// - Returns: Whether a pinch gesture is being performed
    public func checkForPinchGesture(hand: HandAnchor, minimumDistance: Float = 0.02) -> Bool {
        guard let handSkeleton = hand.handSkeleton else { return false }
        
        let indexFinger = handSkeleton.joint(.indexFingerTip)
        let thumbTip = handSkeleton.joint(.thumbTip)
        let originTransform = hand.originFromAnchorTransform
        
        let indexFingerTransform = matrix_multiply(originTransform, indexFinger.anchorFromJointTransform)
        let thumbTipTransform = matrix_multiply(originTransform, thumbTip.anchorFromJointTransform)
        
        let indexFingerPos = SIMD3<Float>(indexFingerTransform.columns.3.x,
                                         indexFingerTransform.columns.3.y,
                                         indexFingerTransform.columns.3.z)
        let thumbTipPos = SIMD3<Float>(thumbTipTransform.columns.3.x,
                                      thumbTipTransform.columns.3.y,
                                      thumbTipTransform.columns.3.z)
        
        let currentFingertipDistance = simd_distance(indexFingerPos, thumbTipPos)
        return currentFingertipDistance < minimumDistance
    }
    
    /// Gets the positions of all finger joints for a hand
    /// - Parameter hand: The hand to get finger positions for
    /// - Returns: A dictionary mapping joint names to their positions, or nil if the hand skeleton is not available
    public func getFingerPositions(for hand: HandAnchor) -> [HandSkeleton.JointName: SIMD3<Float>]? {
        guard let handSkeleton = hand.handSkeleton else { return nil }
        
        var positions: [HandSkeleton.JointName: SIMD3<Float>] = [:]
        let originTransform = hand.originFromAnchorTransform
        
        for joint in HandSkeleton.JointName.allCases {
            let jointAnchor = handSkeleton.joint(joint)
            let transform = matrix_multiply(originTransform, jointAnchor.anchorFromJointTransform)
            let position = SIMD3<Float>(transform.columns.3.x,
                                      transform.columns.3.y,
                                      transform.columns.3.z)
            positions[joint] = position
        }
        
        return positions
    }
    
    /// Gets the dominant hand based on the user's handedness preference
    /// - Returns: The dominant hand anchor if available
    public func getDominantHand() -> HandAnchor? {
        return isRightHanded ? latestHandTracking.right : latestHandTracking.left
    }
    
    /// Gets the non-dominant hand based on the user's handedness preference
    /// - Returns: The non-dominant hand anchor if available
    public func getNonDominantHand() -> HandAnchor? {
        return isRightHanded ? latestHandTracking.left : latestHandTracking.right
    }
} 
