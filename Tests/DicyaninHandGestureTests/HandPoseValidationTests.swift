import XCTest
import simd
@testable import DicyaninHandGesture

// MARK: - Helpers

private func rotated(_ pose: HandGesturePose, angle: Float, axis: SIMD3<Float>) -> HandGesturePose {
    let q = simd_quatf(angle: angle, axis: simd_normalize(axis))
    var joints: [HandGesturePose.Joint: SIMD3<Float>] = [:]
    for (j, p) in pose.joints { joints[j] = simd_act(q, p) }
    return HandGesturePose(joints: joints, chirality: pose.chirality)
}

private func scaled(_ pose: HandGesturePose, by factor: Float) -> HandGesturePose {
    var joints: [HandGesturePose.Joint: SIMD3<Float>] = [:]
    for (j, p) in pose.joints { joints[j] = p * factor }
    return HandGesturePose(joints: joints, chirality: pose.chirality)
}

private func jittered(_ pose: HandGesturePose, amplitude: Float, seed: UInt64 = 7) -> HandGesturePose {
    var state = seed
    func rand() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(state >> 40) / Float(1 << 24) * 2 - 1
    }
    var joints: [HandGesturePose.Joint: SIMD3<Float>] = [:]
    for joint in HandGesturePose.Joint.allCases {
        guard let p = pose.joints[joint] else { continue }
        joints[joint] = p + SIMD3<Float>(rand(), rand(), rand()) * amplitude
    }
    return HandGesturePose(joints: joints, chirality: pose.chirality)
}

// MARK: - Phase 1: Forward kinematics

final class ForwardKinematicsTests: XCTestCase {

    func testBoneLengthsPreservedForEveryFingerAcrossCurlAndSplay() {
        for finger in HandPoseTemplate.Finger.allCases {
            let spec = HandPoseTemplate.specs[finger]!
            for curl in stride(from: Float(0), through: 1, by: 0.2) {
                for splay in stride(from: Float(-1), through: 1, by: 0.5) {
                    let chain = HandPoseTemplate.chainPositions(
                        finger: finger, shape: .init(curl: curl, splay: splay))
                    XCTAssertEqual(chain.count, 4, "\(finger)")
                    for i in 0..<3 {
                        XCTAssertEqual(
                            simd_length(chain[i + 1] - chain[i]), spec.segments[i],
                            accuracy: 0.0001, "\(finger) segment \(i) curl \(curl) splay \(splay)")
                    }
                }
            }
        }
    }

    func testCurlIsMonotonic() {
        // More curl always brings the fingertip closer to the knuckle.
        for finger in HandPoseTemplate.Finger.allCases {
            let knuckle = HandPoseTemplate.specs[finger]!.knuckle
            var prev = Float.greatestFiniteMagnitude
            for step in 0...10 {
                let curl = Float(step) / 10
                let tip = HandPoseTemplate.chainPositions(finger: finger, shape: .init(curl: curl))[3]
                let d = simd_length(tip - knuckle)
                XCTAssertLessThan(d, prev + 0.0001, "\(finger) curl \(curl)")
                prev = d
            }
        }
    }

    func testCurlAndSplayInputsAreClamped() {
        let wild = HandPoseTemplate.chainPositions(finger: .index, shape: .init(curl: 5, splay: -9))
        let edge = HandPoseTemplate.chainPositions(finger: .index, shape: .init(curl: 1, splay: -1))
        for i in 0..<4 {
            XCTAssertEqual(simd_length(wild[i] - edge[i]), 0, accuracy: 0.0001)
        }
    }

    func testSplaySignConvention() {
        // Positive splay rotates toward -X (thumb side of a right hand).
        let pos = HandPoseTemplate.chainPositions(finger: .middle, shape: .init(splay: 1))[3]
        let neg = HandPoseTemplate.chainPositions(finger: .middle, shape: .init(splay: -1))[3]
        XCTAssertLessThan(pos.x, neg.x)
    }

    func testKnucklesUnaffectedByShape() {
        for finger in HandPoseTemplate.Finger.allCases {
            let spec = HandPoseTemplate.specs[finger]!
            let chain = HandPoseTemplate.chainPositions(finger: finger, shape: .init(curl: 1, splay: 1))
            XCTAssertEqual(simd_length(chain[0] - spec.knuckle), 0, accuracy: 0.0001)
        }
    }

    func testGeneratedPoseIsAnatomicallySized() {
        let pose = HandPoseTemplate.preset(.open).pose()
        // Real adult hands span roughly 0.15 to 0.23 m wrist to middle tip.
        XCTAssertGreaterThan(pose.scale, 0.13)
        XCTAssertLessThan(pose.scale, 0.25)
    }

    func testFingerAndDepthCoversAllHandJoints() {
        var covered = 0
        for joint in HandGesturePose.Joint.allCases {
            if HandPoseTemplate.fingerAndDepth(of: joint) != nil { covered += 1 }
        }
        // 27 joints minus wrist and two forearm joints (thumb has no metacarpal
        // in ARKit, so 4 thumb joints + 5 per finger = 24 finger joints).
        XCTAssertEqual(covered, 24)
        XCTAssertNil(HandPoseTemplate.fingerAndDepth(of: .wrist))
        XCTAssertNil(HandPoseTemplate.fingerAndDepth(of: .forearmArm))
    }

    func testLeftHandMirrorsEveryJoint() {
        let right = HandPoseTemplate.preset(.pinch, chirality: .right).pose()
        let left = HandPoseTemplate.preset(.pinch, chirality: .left).pose()
        for (joint, r) in right.joints {
            let l = left.joints[joint]!
            XCTAssertEqual(l.x, -r.x, accuracy: 0.0001, "\(joint)")
            XCTAssertEqual(l.y, r.y, accuracy: 0.0001, "\(joint)")
            XCTAssertEqual(l.z, r.z, accuracy: 0.0001, "\(joint)")
        }
    }
}

// MARK: - Phase 2: Normalization and alignment

final class AlignmentTests: XCTestCase {

    private let axes: [SIMD3<Float>] = [[1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 1, 0], [1, -2, 3]]

    func testNormalizationCancelsArbitraryRotations() {
        let reference = HandPoseTemplate.preset(.point).pose()
        for axis in axes {
            for angle in [Float(20), 75, 140, 200] {
                let live = rotated(reference, angle: angle * .pi / 180, axis: axis)
                let dev = reference.alignedDeviation(to: live)!
                XCTAssertLessThan(dev, 0.02, "axis \(axis) angle \(angle)")
            }
        }
    }

    func testNormalizationIsIdempotent() {
        let once = HandPoseTemplate.preset(.peace).pose().normalized()
        let twice = once.normalized()
        for (j, p) in once.joints {
            XCTAssertEqual(simd_length(p - twice.joints[j]!), 0, accuracy: 0.0001, "\(j)")
        }
    }

    func testAlignmentDoesNotCollapseDistinctGestures() {
        // Rotation invariance must not make everything look alike.
        let fist = HandPoseTemplate.preset(.fist).pose()
        let open = HandPoseTemplate.preset(.open).pose()
        let rolled = rotated(open, angle: .pi / 4, axis: [0, 0, 1])
        XCTAssertGreaterThan(fist.alignedDeviation(to: rolled)!, 0.25)
    }

    func testSparsePoseDegradesGracefully() {
        var joints = HandPoseTemplate.preset(.open).pose().joints
        joints.removeValue(forKey: .middleFingerKnuckle)
        joints.removeValue(forKey: .middleFingerMetacarpal)
        let sparse = HandGesturePose(joints: joints, chirality: .right)
        // Missing frame joints: normalized() returns self, no crash, still comparable.
        XCTAssertNotNil(sparse.normalized().deviation(to: sparse))
    }

    func testMirroredFlipsChiralityAndX() {
        let right = HandPoseTemplate.preset(.thumbsUp, chirality: .right).pose()
        let mirrored = right.mirrored()
        XCTAssertEqual(mirrored.chirality, .left)
        XCTAssertEqual(mirrored.mirrored().chirality, .right)
        XCTAssertEqual(mirrored.joints[.thumbTip]!.x, -right.joints[.thumbTip]!.x, accuracy: 0.0001)
        // Double mirror is identity.
        let back = mirrored.mirrored()
        for (j, p) in right.joints {
            XCTAssertEqual(simd_length(p - back.joints[j]!), 0, accuracy: 0.0001)
        }
    }

    func testCrossHandedMatchDeviationUsesMirror() {
        let right = HandPoseTemplate.preset(.peace, chirality: .right).pose()
        let left = HandPoseTemplate.preset(.peace, chirality: .left).pose()
        // Same-chirality comparison never mirrors.
        XCTAssertLessThan(right.matchDeviation(to: right)!, 0.001)
        // Opposite hands performing the same gesture should be near zero via mirror.
        XCTAssertLessThan(right.matchDeviation(to: left)!, 0.02)
        // But an asymmetric gesture on the wrong hand without mirroring stays far.
        XCTAssertGreaterThan(right.alignedDeviation(to: left)!, 0.1)
    }

    func testEitherChiralityMatchesBothHands() {
        var reference = HandPoseTemplate.preset(.point, chirality: .right).pose()
        reference.chirality = .either
        for chirality in [HandGesturePose.Chirality.left, .right] {
            let live = HandPoseTemplate.preset(.point, chirality: chirality).pose()
            XCTAssertLessThan(reference.matchDeviation(to: live)!, 0.02, "\(chirality)")
        }
    }
}

// MARK: - Phase 3: Deviation and matching robustness

final class MatchingRobustnessTests: XCTestCase {

    func testDeviationIsScaleInvariant() {
        // Deviation is normalized by hand span: comparing two gestures gives the
        // same score for a child's hand (70%) as for a large hand (120%).
        let a = HandPoseTemplate.preset(.pinch).pose()
        let b = HandPoseTemplate.preset(.point).pose()
        let baseline = a.alignedDeviation(to: b)!
        for factor in [Float(0.7), 1.2] {
            let dev = scaled(a, by: factor).alignedDeviation(to: scaled(b, by: factor))!
            XCTAssertEqual(dev, baseline, accuracy: 0.001, "scale \(factor)")
        }
    }

    func testDeviationSurvivesTrackingJitter() {
        // ARKit joint noise is a few millimeters; matching must tolerate it.
        let reference = HandPoseTemplate.preset(.peace).pose()
        let noisy = jittered(reference, amplitude: 0.003)
        let def = HandGestureDefinition(name: "peace", pose: reference, threshold: 0.12)
        XCTAssertTrue(def.matches(noisy))
    }

    func testJitteredAndRotatedStillMatchesRightGesture() {
        // The realistic case: rolled wrist plus sensor noise, against a full library.
        let matcher = HandGestureMatcher()
        for preset in HandPoseTemplate.PresetName.allCases {
            matcher.register(HandGestureDefinition(
                name: preset.rawValue,
                pose: HandPoseTemplate.preset(preset).pose(),
                threshold: 0.12))
        }
        for preset in HandPoseTemplate.PresetName.allCases {
            var live = HandPoseTemplate.preset(preset).pose()
            live = rotated(live, angle: 30 * .pi / 180, axis: [1, 0, 1])
            live = jittered(live, amplitude: 0.002, seed: 42)
            XCTAssertEqual(matcher.bestMatch(for: live)?.name, preset.rawValue)
        }
    }

    func testDeviationNilWhenNoSharedJoints() {
        let a = HandGesturePose(joints: [.thumbTip: [0, 0.1, 0]], chirality: .right)
        let b = HandGesturePose(joints: [.indexFingerTip: [0, 0.1, 0]], chirality: .right)
        XCTAssertNil(a.deviation(to: b))
    }

    func testDeviationSymmetric() {
        let a = HandPoseTemplate.preset(.open).pose()
        let b = HandPoseTemplate.preset(.fist).pose()
        XCTAssertEqual(a.deviation(to: b)!, b.deviation(to: a)!, accuracy: 0.0001)
    }

    func testChiralityGatingBlocksWrongHand() {
        // Symmetric-ish pose on the wrong hand: deviation may pass via mirror,
        // but the chirality gate must still reject the match.
        let rightDef = HandGestureDefinition(
            name: "point", pose: HandPoseTemplate.preset(.point, chirality: .right).pose(),
            threshold: 0.12)
        let leftLive = HandPoseTemplate.preset(.point, chirality: .left).pose()
        XCTAssertFalse(rightDef.matches(leftLive))
        let matcher = HandGestureMatcher(gestures: [rightDef])
        let scores = matcher.scores(for: leftLive)
        XCTAssertFalse(scores[0].isMatch)
        XCTAssertNil(matcher.bestMatch(for: leftLive))
    }

    func testScoresSortedClosestFirstAndThresholdBoundary() {
        let open = HandPoseTemplate.preset(.open).pose()
        let matcher = HandGestureMatcher()
        matcher.register(HandGestureDefinition(name: "open", pose: open, threshold: 0.12))
        matcher.register(HandGestureDefinition(name: "fist", pose: HandPoseTemplate.preset(.fist).pose(), threshold: 0.12))
        let scores = matcher.scores(for: open)
        XCTAssertEqual(scores.map(\.name), ["open", "fist"])
        // Exact boundary: deviation equal to threshold still matches.
        let dev = scores[0].deviation
        matcher.register(HandGestureDefinition(name: "exact", pose: open, threshold: dev))
        XCTAssertTrue(matcher.scores(for: open).first { $0.name == "exact" }!.isMatch)
    }

    func testRegisterReplacesSameIdAndRemoveDeletes() {
        let id = UUID()
        let matcher = HandGestureMatcher()
        matcher.register(HandGestureDefinition(id: id, name: "v1", pose: HandPoseTemplate.preset(.open).pose()))
        matcher.register(HandGestureDefinition(id: id, name: "v2", pose: HandPoseTemplate.preset(.fist).pose()))
        XCTAssertEqual(matcher.gestures.count, 1)
        XCTAssertEqual(matcher.gestures[0].name, "v2")
        matcher.remove(id: id)
        XCTAssertTrue(matcher.gestures.isEmpty)
    }
}

// MARK: - Phase 4: Serialization

final class SerializationTests: XCTestCase {

    func testJSONRoundTripPreservesEverything() throws {
        let original = HandGestureDefinition(
            name: "Pinch Grab", details: "Grab objects", author: "Hunter",
            pose: HandPoseTemplate.preset(.pinch, chirality: .left).pose(),
            threshold: 0.09, version: 1)
        let decoded = try HandGestureDefinition.decoded(from: original.encodedJSON())
        XCTAssertEqual(decoded, original)
        XCTAssertLessThan(decoded.pose.deviation(to: original.pose)!, 0.0001)
    }

    func testDecoderSkipsUnknownJointsAndBadVectors() throws {
        // A file from a future schema with extra joints must still load.
        let json = """
        {"chirality":"right","joints":{
            "wrist":[0,0,0],
            "indexFingerTip":[0.01,0.15,0.0],
            "futureExtraJoint":[1,2,3],
            "thumbTip":[0.1,0.1]
        }}
        """
        let pose = try JSONDecoder().decode(HandGesturePose.self, from: Data(json.utf8))
        XCTAssertEqual(pose.joints.count, 2)
        XCTAssertNotNil(pose.joints[.indexFingerTip])
        XCTAssertNil(pose.joints[.thumbTip])
    }

    func testSuggestedFileNameSanitization() {
        func name(_ s: String) -> String {
            HandGestureDefinition(name: s, pose: HandPoseTemplate.preset(.open).pose()).suggestedFileName
        }
        XCTAssertEqual(name("Peace Sign"), "peace-sign.handgesture.json")
        XCTAssertEqual(name("OK 👌 / v2!"), "ok---v2.handgesture.json")
        XCTAssertEqual(name("!!!"), "gesture.handgesture.json")
    }

    func testExportedGestureMatchesAfterRoundTrip() throws {
        // End to end: build in editor space, export, reimport, match live pose.
        let def = HandGestureDefinition(
            name: "peace", pose: HandPoseTemplate.preset(.peace).pose(), threshold: 0.12)
        let reloaded = try HandGestureDefinition.decoded(from: def.encodedJSON())
        let live = rotated(HandPoseTemplate.preset(.peace).pose(), angle: 0.5, axis: [0, 1, 1])
        XCTAssertTrue(reloaded.matches(live))
    }
}

// MARK: - Phase 5: Drag solver and fitting

final class DragAndFittingTests: XCTestCase {

    func testDragConvergesTipNearReachableTarget() {
        var t = HandPoseTemplate()
        let target = HandPoseTemplate.chainPositions(finger: .index, shape: .init(curl: 0.5, splay: 0.3))[3]
        t.drag(finger: .index, depth: 3, toward: target)
        let tip = HandPoseTemplate.chainPositions(finger: .index, shape: t[.index])[3]
        XCTAssertLessThan(simd_length(tip - target), 0.01)
    }

    func testDragUnreachableTargetClampsWithoutBlowingUp() {
        var t = HandPoseTemplate()
        t.drag(finger: .little, depth: 3, toward: [0, 0.5, 0])
        XCTAssertGreaterThanOrEqual(t[.little].curl, 0)
        XCTAssertLessThanOrEqual(t[.little].curl, 1)
        XCTAssertLessThanOrEqual(abs(t[.little].splay), 1)
    }

    func testDragKnuckleOnlyChangesSplay() {
        var t = HandPoseTemplate()
        t[.index] = .init(curl: 0.4)
        let before = t[.index].curl
        t.drag(finger: .index, depth: 0, toward: HandPoseTemplate.specs[.index]!.knuckle + SIMD3<Float>(-0.03, 0.05, 0))
        XCTAssertEqual(t[.index].curl, before)
        XCTAssertNotEqual(t[.index].splay, 0)
    }

    func testDragNearKnuckleLeavesSplayUntouched() {
        var t = HandPoseTemplate()
        t[.middle] = .init(curl: 0, splay: 0.5)
        let knuckle = HandPoseTemplate.specs[.middle]!.knuckle
        t.drag(finger: .middle, depth: 3, toward: knuckle + SIMD3<Float>(0.001, 0.001, 0))
        XCTAssertEqual(t[.middle].splay, 0.5)
    }

    func testFittedRoundTripAllPresetsBothHands() {
        for preset in HandPoseTemplate.PresetName.allCases {
            for chirality in [HandGesturePose.Chirality.right, .left] {
                let original = HandPoseTemplate.preset(preset, chirality: chirality)
                let fitted = HandPoseTemplate.fitted(to: original.pose())
                XCTAssertEqual(fitted.chirality, chirality)
                let dev = original.pose().deviation(to: fitted.pose())!
                XCTAssertLessThan(dev, 0.12, "\(preset) \(chirality)")
            }
        }
    }

    func testFittedPresetsRemainDistinguishable() {
        // Fitting must not homogenize gestures: each fitted pose still matches
        // its own preset best.
        let matcher = HandGestureMatcher()
        for preset in HandPoseTemplate.PresetName.allCases {
            matcher.register(HandGestureDefinition(
                name: preset.rawValue,
                pose: HandPoseTemplate.preset(preset).pose(),
                threshold: 0.15))
        }
        for preset in HandPoseTemplate.PresetName.allCases {
            let fitted = HandPoseTemplate.fitted(to: HandPoseTemplate.preset(preset).pose())
            XCTAssertEqual(matcher.bestMatch(for: fitted.pose())?.name, preset.rawValue, "\(preset)")
        }
    }
}

// MARK: - Phase 6: Editor model

@MainActor
final class EditorModelTests: XCTestCase {

    func testPoseRebuildsWhenTemplateChanges() {
        let model = HandPoseEditorModel()
        let openTip = model.pose.joints[.indexFingerTip]!
        model.apply(preset: .fist)
        XCTAssertLessThan(simd_length(model.pose.joints[.indexFingerTip]!), simd_length(openTip))
    }

    func testDragOnLeftHandMirrorsTarget() {
        let model = HandPoseEditorModel(template: .preset(.open, chirality: .left))
        let leftTip = model.pose.joints[.indexFingerTip]!
        // Drag the left index tip toward the wrist in left hand space.
        model.drag(joint: .indexFingerTip, toward: SIMD3<Float>(leftTip.x, 0.09, 0))
        XCTAssertGreaterThan(model.template[.index].curl, 0.3)
        // Result stays a left hand.
        XCTAssertEqual(model.pose.chirality, .left)
    }

    func testNonDraggableJointsIgnored() {
        let model = HandPoseEditorModel()
        let before = model.template
        model.drag(joint: .wrist, toward: [0, 0.2, 0])
        model.drag(joint: .forearmArm, toward: [0, 0.2, 0])
        XCTAssertEqual(model.template, before)
        XCTAssertFalse(HandPoseEditorModel.isDraggable(.wrist))
        XCTAssertFalse(HandPoseEditorModel.isDraggable(.indexFingerMetacarpal))
        XCTAssertTrue(HandPoseEditorModel.isDraggable(.indexFingerKnuckle))
        XCTAssertTrue(HandPoseEditorModel.isDraggable(.thumbTip))
    }

    func testEditingChiralityFollowsExportChirality() {
        let model = HandPoseEditorModel(template: .preset(.open, chirality: .right))
        XCTAssertEqual(model.exportChirality, .right)
        model.editingChirality = .left
        XCTAssertEqual(model.exportChirality, .left)
        // Once the user opts into either, switching hands preserves it.
        model.exportChirality = .either
        model.editingChirality = .right
        XCTAssertEqual(model.exportChirality, .either)
        // Setting either as editing hand is rejected.
        model.editingChirality = .either
        XCTAssertEqual(model.editingChirality, .right)
    }

    func testSeedingFromDefinitionPreservesMetadataAndShape() {
        let source = HandGestureDefinition(
            name: "Grab", details: "d", author: "a",
            pose: HandPoseTemplate.preset(.fist).pose(), threshold: 0.1)
        let model = HandPoseEditorModel(definition: source)
        XCTAssertEqual(model.name, "Grab")
        XCTAssertEqual(model.details, "d")
        XCTAssertEqual(model.author, "a")
        XCTAssertEqual(model.threshold, 0.1)
        XCTAssertEqual(model.exportChirality, .right)
        XCTAssertLessThan(model.pose.deviation(to: source.pose)!, 0.12)
    }

    func testMakeDefinitionDefaultsEmptyName() {
        let model = HandPoseEditorModel()
        XCTAssertEqual(model.makeDefinition().name, "Untitled Gesture")
    }
}
