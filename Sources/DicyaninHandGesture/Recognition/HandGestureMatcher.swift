import Foundation

/// Holds a set of gesture definitions and reports which one a live pose matches.
/// Use one matcher for your whole app, register the gestures you care about, then
/// feed live poses each frame.
public final class HandGestureMatcher: @unchecked Sendable {

    public private(set) var gestures: [HandGestureDefinition]

    public init(gestures: [HandGestureDefinition] = []) {
        self.gestures = gestures
    }

    public func register(_ gesture: HandGestureDefinition) {
        gestures.removeAll { $0.id == gesture.id }
        gestures.append(gesture)
    }

    public func remove(id: UUID) {
        gestures.removeAll { $0.id == id }
    }

    /// The result of testing a live pose against one gesture.
    public struct Score: Identifiable, Sendable {
        public var id: UUID
        public var name: String
        public var deviation: Float
        public var isMatch: Bool
    }

    /// Scores every registered gesture against a live pose, closest first.
    public func scores(for live: HandGesturePose) -> [Score] {
        gestures.compactMap { g in
            guard let dev = g.pose.deviation(to: live) else { return nil }
            let chiralityOK = live.chirality == g.pose.chirality
                || g.pose.chirality == .either
                || live.chirality == .either
            return Score(id: g.id, name: g.name, deviation: dev, isMatch: chiralityOK && dev <= g.threshold)
        }
        .sorted { $0.deviation < $1.deviation }
    }

    /// The single best matching gesture for a live pose, or nil if none match.
    public func bestMatch(for live: HandGesturePose) -> HandGestureDefinition? {
        let best = scores(for: live).first { $0.isMatch }
        guard let best else { return nil }
        return gestures.first { $0.id == best.id }
    }
}
