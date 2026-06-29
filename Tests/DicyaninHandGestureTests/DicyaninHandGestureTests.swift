import XCTest
import simd
@testable import DicyaninHandGesture

final class DicyaninHandGestureTests: XCTestCase {

    private func pose(spread: Float, chirality: HandGesturePose.Chirality = .right) -> HandGesturePose {
        var joints: [HandGesturePose.Joint: SIMD3<Float>] = [.wrist: .zero]
        joints[.middleFingerTip] = SIMD3<Float>(0, 0.18, 0)
        joints[.indexFingerTip] = SIMD3<Float>(-0.03 * spread, 0.16, 0)
        joints[.thumbTip] = SIMD3<Float>(-0.06 * spread, 0.08, 0)
        return HandGesturePose(joints: joints, chirality: chirality)
    }

    func testIdenticalPoseHasZeroDeviation() {
        let p = pose(spread: 1)
        XCTAssertEqual(p.deviation(to: p) ?? 1, 0, accuracy: 0.0001)
    }

    func testDifferentPoseHasPositiveDeviation() {
        let a = pose(spread: 1)
        let b = pose(spread: 3)
        XCTAssertGreaterThan(a.deviation(to: b) ?? 0, 0)
    }

    func testMatchWithinThreshold() {
        let def = HandGestureDefinition(name: "spread", pose: pose(spread: 1), threshold: 0.2)
        XCTAssertTrue(def.matches(pose(spread: 1.05)))
        XCTAssertFalse(def.matches(pose(spread: 5)))
    }

    func testChiralityMismatchFails() {
        let def = HandGestureDefinition(name: "r", pose: pose(spread: 1, chirality: .right))
        XCTAssertFalse(def.matches(pose(spread: 1, chirality: .left)))
    }

    func testEitherChiralityMatches() {
        let def = HandGestureDefinition(name: "any", pose: pose(spread: 1, chirality: .either))
        XCTAssertTrue(def.matches(pose(spread: 1, chirality: .left)))
    }

    func testJSONRoundTrip() throws {
        let def = HandGestureDefinition(name: "Peace Sign", author: "hunter", pose: pose(spread: 1), threshold: 0.15)
        let data = try def.encodedJSON()
        let decoded = try HandGestureDefinition.decoded(from: data)
        XCTAssertEqual(def, decoded)
    }

    func testSuggestedFileName() {
        let def = HandGestureDefinition(name: "Peace Sign!", pose: pose(spread: 1))
        XCTAssertEqual(def.suggestedFileName, "peace-sign.handgesture.json")
    }

    func testMatcherBestMatch() {
        let matcher = HandGestureMatcher()
        matcher.register(HandGestureDefinition(name: "tight", pose: pose(spread: 1), threshold: 0.2))
        matcher.register(HandGestureDefinition(name: "wide", pose: pose(spread: 3), threshold: 0.2))
        let best = matcher.bestMatch(for: pose(spread: 1.02))
        XCTAssertEqual(best?.name, "tight")
    }
}
