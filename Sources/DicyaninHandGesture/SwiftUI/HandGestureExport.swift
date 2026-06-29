import Foundation

/// Writes gesture definitions to disk so they can be shared, and reads them back.
public enum HandGestureExport {

    /// Writes the gesture as pretty JSON to a temp file and returns its URL,
    /// suitable for a SwiftUI `ShareLink`.
    public static func writeTemporaryFile(_ gesture: HandGestureDefinition) throws -> URL {
        let data = try gesture.encodedJSON()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(gesture.suggestedFileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Reads a gesture definition from a JSON file URL.
    public static func read(from url: URL) throws -> HandGestureDefinition {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try HandGestureDefinition.decoded(from: data)
    }
}
