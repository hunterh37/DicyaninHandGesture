# HandGestureKit

A Swift package for detecting hand gestures in visionOS and iOS applications using ARKit's hand tracking capabilities.

## Requirements

- iOS 17.0+ / visionOS 1.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "YOUR_REPOSITORY_URL", from: "1.0.0")
]
```

## Usage

### Basic Setup

```swift
import HandGestureKit

class YourViewController: UIViewController {
    private let handGestureDetector = HandGestureDetector()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupHandTracking()
    }
    
    private func setupHandTracking() {
        Task {
            do {
                try await handGestureDetector.start()
            } catch {
                print("Failed to start hand tracking: \(error)")
            }
        }
    }
}
```

### Detecting Pinch Gestures

```swift
// Check for pinch gesture on the dominant hand
if let dominantHand = handGestureDetector.getDominantHand() {
    let isPinching = handGestureDetector.checkForPinchGesture(hand: dominantHand)
    if isPinching {
        // Handle pinch gesture
    }
}
```

### Getting Finger Positions

```swift
if let dominantHand = handGestureDetector.getDominantHand(),
   let positions = handGestureDetector.getFingerPositions(for: dominantHand) {
    // Access positions for specific fingers
    if let indexFingerPosition = positions[.indexFingerTip] {
        // Use index finger position
    }
}
```

## Features

- Hand tracking initialization and management
- Pinch gesture detection
- Finger position tracking
- Support for both dominant and non-dominant hands
- Thread-safe hand tracking updates

## License

[Your License Here] 