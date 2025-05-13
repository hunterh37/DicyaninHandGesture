// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HandGestureKit",
    platforms: [
        .iOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "HandGestureKit",
            targets: ["HandGestureKit"]),
    ],
    dependencies: [
        .package(path: "DicyaninARKitSession")
    ],
    targets: [
        .target(
            name: "HandGestureKit",
            dependencies: ["DicyaninARKitSession"]),
        .testTarget(
            name: "HandGestureKitTests",
            dependencies: ["HandGestureKit"]),
    ]
) 