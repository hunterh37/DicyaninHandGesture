# DicyaninHandGesture

A Swift package that provides a clean, reusable interface for hand gesture detection in visionOS applications.

## Overview

DicyaninHandGesture simplifies working with ARKit's hand tracking capabilities by providing:
- A clean, reusable interface for hand gesture detection
- Support for multiple concurrent gestures
- Hand-specific detection (left/right hand)
- Customizable gesture parameters
- Dominant/non-dominant hand support

## Dependencies

DicyaninHandGesture depends on  [DicyaninHandSessionManager](https://github.com/hunterh37/DicyaninARKitSession), a package that manages ARKit sessions and hand tracking updates. This separation of concerns is important because:

1. **Resource Management**: ARKit sessions are resource-intensive and should be shared across multiple packages
2. **Consistency**: Ensures all packages receive the same hand tracking data
3. **Performance**: Prevents multiple ARKit sessions from running simultaneously
4. **Modularity**: Allows other packages to use hand tracking without implementing their own session management

## Requirements

- visionOS 1.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/hunterh37/DicyaninHandGesture.git", from: "0.0.1")
]
```

## Usage

### Basic Setup

```swift
import DicyaninHandGesture
import SwiftUI
import RealityKit

struct ContentView: View {
    @StateObject private var gestureDetector = HandGestureDetector.shared
    @State private var isPinching = false
    
    var body: some View {
        RealityView { content in
            // Add your 3D content here
            let box = ModelEntity(mesh: .generateBox(size: 0.3))
            content.add(box)
        } update: { content in
            // Your update logic here
        }
        .task {
            // Start hand tracking when the view appears
            try? await gestureDetector.start()
        }
        .onDisappear {
            // Stop hand tracking when the view disappears
            gestureDetector.stop()
        }
        .onAppear {
            // Set up gesture detection
            let pinchGesture = PinchGesture(handSide: .right)
            gestureDetector.addGesture(pinchGesture) { isActive in
                isPinching = isActive
            }
        }
    }
}
```

### Required Setup

1. Add the following key to your Info.plist file to request hand tracking permissions:
```xml
<key>NSHandsTrackingUsageDescription</key>
<string>This app needs access to hand tracking to enable hand interaction features.</string>
```

### Available Gestures

- `PinchGesture`: Detects pinching between thumb and index finger
- `GrabGesture`: Detects when all fingers are curled
- `PointGesture`: Detects when index finger is extended while others are curled

## License

Copyright © 2025 Dicyanin Labs. All rights reserved. 
