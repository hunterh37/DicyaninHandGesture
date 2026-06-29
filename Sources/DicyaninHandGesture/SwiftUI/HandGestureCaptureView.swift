import SwiftUI

/// A self contained authoring panel: shows the live hand skeleton in 2D, lets the
/// user name the gesture, press Capture to freeze the current pose, tune the match
/// threshold against the live hand, and share the result as a `.handgesture.json`
/// file.
///
/// Drive it by updating `livePose` every frame from your hand tracking loop
/// (see `HandGestureRecorder`). The view owns no tracking itself, so it builds
/// and previews on any platform.
public struct HandGestureCaptureView: View {

    /// The current live pose from your tracking loop. Set this each frame.
    public var livePose: HandGesturePose?

    /// Called whenever a gesture is captured or its metadata changes.
    public var onCapture: ((HandGestureDefinition) -> Void)?

    public init(livePose: HandGesturePose?, onCapture: ((HandGestureDefinition) -> Void)? = nil) {
        self.livePose = livePose
        self.onCapture = onCapture
    }

    @State private var name: String = ""
    @State private var author: String = ""
    @State private var threshold: Float = 0.18
    @State private var captured: HandGesturePose?
    @State private var shareURL: URL?
    @State private var errorText: String?

    private var liveDeviation: Float? {
        guard let captured, let livePose else { return nil }
        return captured.deviation(to: livePose)
    }

    private var isLiveMatch: Bool {
        guard let dev = liveDeviation else { return false }
        return dev <= threshold
    }

    public var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                skeletonPanel(title: "Live", pose: livePose, tint: .accentColor)
                skeletonPanel(title: "Captured", pose: captured, tint: .green)
            }
            .frame(maxHeight: 280)

            if let dev = liveDeviation {
                HStack {
                    Circle()
                        .fill(isLiveMatch ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(isLiveMatch ? "Match" : "No match")
                        .foregroundStyle(isLiveMatch ? .green : .orange)
                    Spacer()
                    Text(String(format: "deviation %.3f", dev))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            controls

            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(20)
    }

    private func skeletonPanel(title: String, pose: HandGesturePose?, tint: Color) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HandSkeleton2DView(pose: pose, tint: tint)
                .background(RoundedRectangle(cornerRadius: 16).fill(.quaternary.opacity(0.25)))
        }
    }

    @ViewBuilder
    private var controls: some View {
        TextField("Gesture name", text: $name)
            .textFieldStyle(.roundedBorder)
        TextField("Author (optional)", text: $author)
            .textFieldStyle(.roundedBorder)

        VStack(alignment: .leading) {
            HStack {
                Text("Threshold")
                Spacer()
                Text(String(format: "%.3f", threshold)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $threshold, in: 0.02...0.5)
        }

        HStack(spacing: 12) {
            Button {
                captured = livePose
                shareURL = nil
                errorText = livePose == nil ? "No hand to capture" : nil
            } label: {
                Label("Capture Gesture", systemImage: "hand.raised.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(livePose == nil)

            Button {
                exportCaptured()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(captured == nil)
        }

        if let shareURL {
            ShareLink(item: shareURL) {
                Label("Share \(shareURL.lastPathComponent)", systemImage: "square.and.arrow.up.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func buildDefinition(from pose: HandGesturePose) -> HandGestureDefinition {
        HandGestureDefinition(
            name: name.isEmpty ? "Untitled Gesture" : name,
            author: author,
            pose: pose,
            threshold: threshold
        )
    }

    private func exportCaptured() {
        guard let captured else { return }
        let def = buildDefinition(from: captured)
        onCapture?(def)
        do {
            shareURL = try HandGestureExport.writeTemporaryFile(def)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
