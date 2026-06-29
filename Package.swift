// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DicyaninHandGesture",
    platforms: [
        .visionOS(.v2),
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "DicyaninHandGesture",
            targets: ["DicyaninHandGesture"]
        )
    ],
    targets: [
        .target(
            name: "DicyaninHandGesture"
        ),
        .testTarget(
            name: "DicyaninHandGestureTests",
            dependencies: ["DicyaninHandGesture"]
        )
    ]
)
