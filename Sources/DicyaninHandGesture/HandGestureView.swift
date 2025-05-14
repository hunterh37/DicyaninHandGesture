/*
 * HandGestureKit
 * Created by Hunter Harris on 04/03/2025
 * Copyright © 2025 Dicyanin Labs. All rights reserved.
 */

import SwiftUI
import RealityKit
import ARKit

/// A SwiftUI view that demonstrates hand gesture detection
///
/// This view provides a default implementation for testing and demonstrating
/// hand gesture detection. It includes:
/// - A 3D box that responds to different gestures
/// - Visual feedback for active gestures
/// - Support for multiple concurrent gestures
///
/// Example usage:
/// ```swift
/// struct ContentView: View {
///     var body: some View {
///         HandGestureView()
///     }
/// }
/// ```
public struct HandGestureView: View {
    @StateObject private var detector = HandGestureDetector.shared
    @State private var activeGestures: [String: Bool] = [:]
    
    /// Creates a new hand gesture view
    public init() {}
    
    public var body: some View {
        RealityView { content in
            // Add any 3D content you want to interact with here
            let box = ModelEntity(mesh: .generateBox(size: 0.1))
            box.position = SIMD3<Float>(0, 0, -0.5)
            content.add(box)
            
            // Start hand tracking
            Task {
                do {
                    try await detector.start()
                    
                    // Add right hand index-thumb pinch
                    let rightPinchGesture = PinchGesture(
                        finger1: .indexFingerTip,
                        finger2: .thumbTip,
                        handSide: .right,
                        minimumDistance: 0.02,
                        requiredDuration: 0.5
                    )
                    detector.addGesture(rightPinchGesture) { isActive in
                        activeGestures["Right Pinch"] = isActive
                    }
                    
                    // Add left hand index-pinky pinch
                    let leftPinchGesture = PinchGesture(
                        finger1: .indexFingerTip,
                        finger2: .littleFingerTip,
                        handSide: .left,
                        minimumDistance: 0.02,
                        requiredDuration: 0.5
                    )
                    detector.addGesture(leftPinchGesture) { isActive in
                        activeGestures["Left Pinch"] = isActive
                    }
                    
                    // Add finger distance gesture for both hands
                    let fingerDistanceGesture = FingerDistanceGesture(
                        finger1: .indexFingerTip,
                        finger2: .middleFingerTip,
                        handSide: .both,
                        minimumDistance: 0.05,
                        maximumDistance: 0.1,
                        requiredDuration: 0.5
                    )
                    detector.addGesture(fingerDistanceGesture) { isActive in
                        activeGestures["Finger Distance"] = isActive
                    }
                    
                } catch {
                    print("Failed to start hand tracking: \(error)")
                }
            }
        } update: { content in
            // Update content based on active gestures
            if let box = content.entities.first {
                if activeGestures["Right Pinch"] == true {
                    box.scale = SIMD3<Float>(0.5, 0.5, 0.5)
                } else if activeGestures["Left Pinch"] == true {
                    box.scale = SIMD3<Float>(1.5, 1.5, 1.5)
                } else {
                    box.scale = SIMD3<Float>(1, 1, 1)
                }
                
                if activeGestures["Finger Distance"] == true {
                  //  box.model?.materials = [SimpleMaterial(color: .red, isMetallic: true)]
                } else {
                   // box.model?.materials = [SimpleMaterial(color: .blue, isMetallic: true)]
                }
            }
        }
        .overlay(alignment: .bottom) {
            VStack {
                ForEach(Array(activeGestures.keys.sorted()), id: \.self) { gestureName in
                    if let isActive = activeGestures[gestureName] {
                        Text("\(gestureName): \(isActive ? "Active" : "Inactive")")
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                    }
                }
            }
            .padding()
        }
    }
}

#Preview {
    HandGestureView()
} 
