import Foundation

/// A named, shareable gesture. This is the top level object that gets exported to
/// and imported from JSON. A gesture is one reference pose plus a match
/// threshold: a live pose matches when its deviation is at or below the
/// threshold.
public struct HandGestureDefinition: Codable, Identifiable, Equatable, Sendable {

    /// Stable identity, also the suggested file name stem.
    public var id: UUID
    public var name: String
    public var details: String
    public var author: String

    /// The captured reference pose.
    public var pose: HandGesturePose

    /// Max deviation (scale invariant) that still counts as performing this
    /// gesture. Tune per gesture: tight poses want a smaller value.
    public var threshold: Float

    /// Schema version so future readers can migrate old files.
    public var version: Int

    public init(
        id: UUID = UUID(),
        name: String,
        details: String = "",
        author: String = "",
        pose: HandGesturePose,
        threshold: Float = 0.18,
        version: Int = 1
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.author = author
        self.pose = pose
        self.threshold = threshold
        self.version = version
    }

    /// True when a live pose is performing this gesture.
    public func matches(_ live: HandGesturePose) -> Bool {
        guard live.chirality == pose.chirality || pose.chirality == .either || live.chirality == .either else {
            return false
        }
        guard let dev = pose.matchDeviation(to: live) else { return false }
        return dev <= threshold
    }

    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> HandGestureDefinition {
        try JSONDecoder().decode(HandGestureDefinition.self, from: data)
    }

    /// Sanitized file name like `peace-sign.handgesture.json`.
    public var suggestedFileName: String {
        let stem = name.isEmpty ? id.uuidString : name
        let safe = stem.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "\(safe.isEmpty ? "gesture" : safe).handgesture.json"
    }
}
