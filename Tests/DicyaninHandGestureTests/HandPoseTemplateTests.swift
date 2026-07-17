import XCTest
import simd
@testable import DicyaninHandGesture

final class HandPoseTemplateTests: XCTestCase {

    func testOpenHandHasAllJointsExceptForearm() {
        let pose = HandPoseTemplate.preset(.open).pose()
        // wrist + thumb (4) + four fingers (5 each: metacarpal through tip)
        XCTAssertEqual(pose.joints.count, 25)
        XCTAssertNil(pose.joints[.forearmWrist])
        XCTAssertEqual(pose.joints[.wrist], .zero)
    }

    func testFistTipsCloserToWristThanOpen() {
        let open = HandPoseTemplate.preset(.open).pose()
        let fist = HandPoseTemplate.preset(.fist).pose()
        for tip: HandGesturePose.Joint in [.indexFingerTip, .middleFingerTip, .ringFingerTip, .littleFingerTip] {
            XCTAssertLessThan(simd_length(fist.joints[tip]!), simd_length(open.joints[tip]!) * 0.7, "\(tip)")
        }
    }

    func testLeftHandIsMirrored() {
        let right = HandPoseTemplate.preset(.open, chirality: .right).pose()
        let left = HandPoseTemplate.preset(.open, chirality: .left).pose()
        let r = right.joints[.thumbTip]!
        let l = left.joints[.thumbTip]!
        XCTAssertEqual(l.x, -r.x, accuracy: 0.0001)
        XCTAssertEqual(l.y, r.y, accuracy: 0.0001)
    }

    func testBoneLengthsPreservedUnderCurl() {
        let spec = HandPoseTemplate.specs[.index]!
        for curl in stride(from: Float(0), through: 1, by: 0.25) {
            let chain = HandPoseTemplate.chainPositions(finger: .index, shape: .init(curl: curl))
            for i in 0..<3 {
                XCTAssertEqual(simd_length(chain[i + 1] - chain[i]), spec.segments[i], accuracy: 0.0001)
            }
        }
    }

    func testDragTipIncreasesCurlWhenTargetNearKnuckle() {
        var t = HandPoseTemplate.preset(.open)
        let knuckle = HandPoseTemplate.specs[.index]!.knuckle
        t.drag(finger: .index, depth: 3, toward: knuckle + SIMD3<Float>(0, 0.02, 0))
        XCTAssertGreaterThan(t[.index].curl, 0.5)
    }

    func testDragSidewaysSetsSplay() {
        var t = HandPoseTemplate.preset(.open)
        let straightTip = HandPoseTemplate.chainPositions(finger: .index, shape: .init())[3]
        t.drag(finger: .index, depth: 3, toward: straightTip + SIMD3<Float>(-0.04, 0, 0))
        XCTAssertGreaterThan(t[.index].splay, 0.3)
    }

    func testFittedRoundTripMatchesOriginal() {
        let original = HandPoseTemplate.preset(.point)
        let fitted = HandPoseTemplate.fitted(to: original.pose())
        let dev = original.pose().deviation(to: fitted.pose())!
        XCTAssertLessThan(dev, 0.1)
    }

    func testDistinctPresetsDontCrossMatch() {
        let matcher = HandGestureMatcher()
        for preset in HandPoseTemplate.PresetName.allCases {
            matcher.register(HandGestureDefinition(
                name: preset.rawValue,
                pose: HandPoseTemplate.preset(preset).pose(),
                threshold: 0.12
            ))
        }
        for preset in HandPoseTemplate.PresetName.allCases {
            let best = matcher.bestMatch(for: HandPoseTemplate.preset(preset).pose())
            XCTAssertEqual(best?.name, preset.rawValue)
        }
    }

    func testRotatedPoseStillMatchesViaAlignment() {
        let reference = HandPoseTemplate.preset(.peace).pose()
        // Roll the live hand 40 degrees about Z, as a rolled wrist would.
        let q = simd_quatf(angle: 40 * .pi / 180, axis: [0, 0, 1])
        var rotated: [HandGesturePose.Joint: SIMD3<Float>] = [:]
        for (j, p) in reference.joints { rotated[j] = simd_act(q, p) }
        let live = HandGesturePose(joints: rotated, chirality: .right)

        XCTAssertGreaterThan(reference.deviation(to: live)!, 0.1, "raw deviation should be large")
        XCTAssertLessThan(reference.alignedDeviation(to: live)!, 0.02, "aligned deviation should vanish")
        let def = HandGestureDefinition(name: "peace", pose: reference, threshold: 0.12)
        XCTAssertTrue(def.matches(live))
    }

    func testEditorModelProducesDefinition() async {
        await MainActor.run {
            let model = HandPoseEditorModel(template: .preset(.thumbsUp))
            model.name = "Thumbs Up"
            model.exportChirality = .either
            let def = model.makeDefinition()
            XCTAssertEqual(def.name, "Thumbs Up")
            XCTAssertEqual(def.pose.chirality, .either)
            XCTAssertTrue(def.matches(HandPoseTemplate.preset(.thumbsUp, chirality: .left).pose()))
        }
    }
}
