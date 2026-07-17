import Foundation
import simd
import SwiftUI

/// State for the gesture editor: a `HandPoseTemplate` plus gesture metadata.
/// The 2D view drags joints through `drag(joint:toward:)`, every view reads
/// `pose` for rendering, and `makeDefinition()` produces the shareable result.
@MainActor
public final class HandPoseEditorModel: ObservableObject {

    @Published public var template: HandPoseTemplate {
        didSet { rebuildPose() }
    }
    @Published public var name: String
    @Published public var details: String
    @Published public var author: String
    @Published public var threshold: Float
    /// The chirality stored on the exported gesture. Editing always happens on
    /// the template's hand; `.either` exports the edited hand as match-any.
    @Published public var exportChirality: HandGesturePose.Chirality

    @Published public private(set) var pose: HandGesturePose

    public init(
        template: HandPoseTemplate = .preset(.open),
        name: String = "",
        threshold: Float = 0.18
    ) {
        self.template = template
        self.name = name
        self.details = ""
        self.author = ""
        self.threshold = threshold
        self.exportChirality = template.chirality
        self.pose = template.pose()
    }

    /// Seeds the editor from an existing gesture (imported file or live capture).
    public convenience init(definition: HandGestureDefinition) {
        self.init(
            template: .fitted(to: definition.pose),
            name: definition.name,
            threshold: definition.threshold
        )
        details = definition.details
        author = definition.author
        exportChirality = definition.pose.chirality
    }

    private func rebuildPose() {
        pose = template.pose()
    }

    // MARK: - Editing

    public var editingChirality: HandGesturePose.Chirality {
        get { template.chirality }
        set {
            guard newValue == .left || newValue == .right else { return }
            if exportChirality == template.chirality { exportChirality = newValue }
            template.chirality = newValue
        }
    }

    /// True for joints the 2D editor lets the user grab.
    public static func isDraggable(_ joint: HandGesturePose.Joint) -> Bool {
        guard let (_, depth) = HandPoseTemplate.fingerAndDepth(of: joint) else { return false }
        return depth >= 0
    }

    /// Drags a joint toward a target expressed in wrist local space (meters).
    /// The finger's curl/splay is solved so the chain follows anatomically.
    public func drag(joint: HandGesturePose.Joint, toward target: SIMD3<Float>) {
        guard let (finger, depth) = HandPoseTemplate.fingerAndDepth(of: joint), depth >= 0 else { return }
        var t = target
        if template.chirality == .left { t.x = -t.x }
        template.drag(finger: finger, depth: depth, toward: t)
    }

    public func apply(preset: HandPoseTemplate.PresetName) {
        template = .preset(preset, chirality: template.chirality)
    }

    // MARK: - Output

    public func makeDefinition() -> HandGestureDefinition {
        var exportPose = pose
        exportPose.chirality = exportChirality
        return HandGestureDefinition(
            name: name.isEmpty ? "Untitled Gesture" : name,
            details: details,
            author: author,
            pose: exportPose,
            threshold: threshold
        )
    }
}
