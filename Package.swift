// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DicyaninHandGesture",
    platforms: [
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "DicyaninHandGesture",
            targets: ["DicyaninHandGesture"]),
    ],
    dependencies: [
        .package(path: "DicyaninARKitSession")
    ],
    targets: [
        .target(
            name: "DicyaninHandGesture",
            dependencies: ["DicyaninARKitSession"]),
        .testTarget(
            name: "DicyaninHandGestureTests",
            dependencies: ["DicyaninHandGesture"]),
    ]
) 