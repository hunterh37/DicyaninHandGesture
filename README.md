# DicyaninHandGesture

Author, share, and detect Apple Vision Pro hand gestures. Capture a hand pose into a portable `.handgesture.json` file, ship those files to other users, and at runtime check whether a live hand is performing any registered gesture by measuring its deviation from the captured pose.

Platforms: visionOS 2+ (live capture and matching). iOS 18+ / macOS 15+ build the model, matcher, and the 2D SwiftUI views for tooling and previews.

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/dicyanin/DicyaninHandGesture.git", from: "1.0.0")
```

## How it works

A `HandGesturePose` stores all 26 ARKit joints in wrist local space, so a pose is invariant to where the hand was in the room or which way it faced. Matching is a scale invariant average joint distance (`deviation`), normalized by hand span so big and small hands match the same gesture. A `HandGestureDefinition` wraps one reference pose plus a `threshold`: a live pose matches when its deviation is at or below the threshold.

## Capture and share (SwiftUI)

`HandGestureCaptureView` is a full authoring panel: live + captured 2D skeletons, name/author fields, a threshold slider with a live match readout, a Capture button, and a `ShareLink` that exports the gesture as JSON.

```swift
import DicyaninHandGesture

struct AuthoringPanel: View {
    @State private var live: HandGesturePose?
    var body: some View {
        HandGestureCaptureView(livePose: live) { saved in
            // persist or register the captured gesture
        }
    }
}
```

Feed `live` every frame from your hand tracking loop:

```swift
for await update in handTracking.anchorUpdates {
    if let pose = HandGestureRecorder.pose(from: update.anchor) {
        live = pose
    }
}
```

## Detect at runtime

```swift
let matcher = HandGestureMatcher()
matcher.register(try HandGestureExport.read(from: peaceSignURL))

// per frame
if let pose = HandGestureRecorder.pose(from: anchor),
   let hit = matcher.bestMatch(for: pose) {
    print("performing \(hit.name)")
}
```

## Visualize any pose

```swift
HandSkeleton2DView(pose: somePose, showLabels: true)
```

Draws every joint as a dot and the bones between them, with the wrist marked, projected onto the palm plane.

## JSON format

```json
{
  "id": "…",
  "name": "Peace Sign",
  "author": "hunter",
  "threshold": 0.15,
  "version": 1,
  "pose": {
    "chirality": "right",
    "joints": { "wrist": [0, 0, 0], "indexFingerTip": [-0.03, 0.16, 0], ... }
  }
}
```

Files are pretty printed and key sorted, so they diff cleanly and are easy to hand edit and share.
