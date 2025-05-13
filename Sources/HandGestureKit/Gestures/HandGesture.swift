/*
 * HandGestureKit
 * Created by Hunter Harris on 04/03/2025
 * Copyright © 2025 Dicyanin Labs. All rights reserved.
 */

import RealityKit
import ARKit

/// Represents which hand(s) a gesture should be detected on
public enum HandSide {
    /// Only detect the gesture on the left hand
    case left
    /// Only detect the gesture on the right hand
    case right
    /// Detect the gesture on either hand
    case both
}

/// Protocol that defines the interface for hand gestures
///
/// Implement this protocol to create custom hand gestures. For most cases,
/// it's recommended to subclass `BaseHandGesture` instead of implementing
/// this protocol directly.
public protocol HandGesture {
    /// The name of the gesture
    var name: String { get }
    
    /// Whether the gesture is currently active
    var isActive: Bool { get }
    
    /// How long the gesture has been active
    var duration: TimeInterval { get }
    
    /// Which hand(s) the gesture should be detected on
    var handSide: HandSide { get }
    
    /// Updates the gesture state based on the current hand position
    /// - Parameter hand: The hand to check for the gesture
    /// - Returns: Whether the gesture is active
    func update(hand: HandAnchor) -> Bool
    
    /// Resets the gesture state
    func reset()
}

/// Base class for implementing hand gestures
///
/// This class provides common functionality for gesture detection, including:
/// - Duration tracking
/// - Hand selection
/// - State management
///
/// Example usage:
/// ```swift
/// class CustomGesture: BaseHandGesture {
///     override func checkGesture(hand: HandAnchor) -> Bool {
///         // Implement custom gesture detection logic
///         return true
///     }
/// }
/// ```
public class BaseHandGesture: HandGesture {
    /// The name of the gesture
    public let name: String
    
    /// Which hand(s) the gesture should be detected on
    public let handSide: HandSide
    
    /// Whether the gesture is currently active
    public private(set) var isActive: Bool = false
    
    /// How long the gesture has been active
    public private(set) var duration: TimeInterval = 0
    
    private var startTime: Date?
    private var requiredDuration: TimeInterval
    
    /// Creates a new base gesture
    /// - Parameters:
    ///   - name: The name of the gesture
    ///   - handSide: Which hand(s) to detect the gesture on
    ///   - requiredDuration: How long the gesture must be held to be considered active
    public init(name: String, handSide: HandSide = .both, requiredDuration: TimeInterval = 0.5) {
        self.name = name
        self.handSide = handSide
        self.requiredDuration = requiredDuration
    }
    
    public func update(hand: HandAnchor) -> Bool {
        // Check if this gesture should process the given hand
        switch handSide {
        case .left:
            guard hand.chirality == .left else { return false }
        case .right:
            guard hand.chirality == .right else { return false }
        case .both:
            break
        }
        
        let isDetected = checkGesture(hand: hand)
        
        if isDetected {
            if startTime == nil {
                startTime = Date()
            }
            duration = Date().timeIntervalSince(startTime!)
            isActive = duration >= requiredDuration
        } else {
            reset()
        }
        
        return isActive
    }
    
    public func reset() {
        isActive = false
        duration = 0
        startTime = nil
    }
    
    /// Override this method in subclasses to implement specific gesture detection
    /// - Parameter hand: The hand to check for the gesture
    /// - Returns: Whether the gesture is being performed
    public func checkGesture(hand: HandAnchor) -> Bool {
        return false
    }
} 