import SwiftUI

/// The full gesture authoring loop in one view: drag joints on the 2D hand, a
/// 3D skeleton preview floats over the editor (RealityView, slowly rotating),
/// then name it, tune the threshold, and save or export a
/// `.handgesture.json` anyone can load with `HandGestureExport.read(from:)`.
///
/// ```swift
/// HandGestureEditorView { definition in
///     matcher.register(definition)
/// }
/// ```
public struct HandGestureEditorView: View {

    @StateObject private var model: HandPoseEditorModel
    @State private var exportURL: URL?
    @State private var showFineTune = false
    private let onSave: ((HandGestureDefinition) -> Void)?

    public init(
        definition: HandGestureDefinition? = nil,
        onSave: ((HandGestureDefinition) -> Void)? = nil
    ) {
        if let definition {
            _model = StateObject(wrappedValue: HandPoseEditorModel(definition: definition))
        } else {
            _model = StateObject(wrappedValue: HandPoseEditorModel())
        }
        self.onSave = onSave
    }

    public var body: some View {
        VStack(spacing: 12) {
            editorHeader
            ZStack(alignment: .topTrailing) {
                HandPoseEditor2DView(model: model)
                    .background(RoundedRectangle(cornerRadius: 20).fill(.quaternary.opacity(0.3)))
                #if canImport(RealityKit)
                HandSkeleton3DView(pose: model.pose)
                    .frame(width: 170, height: 170)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.thinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator, lineWidth: 0.5))
                    .padding(10)
                    .allowsHitTesting(true)
                #endif
            }
            controls
        }
        .padding()
        .onChange(of: model.pose) { _, _ in exportURL = nil }
    }

    private var editorHeader: some View {
        HStack {
            Menu {
                ForEach(HandPoseTemplate.PresetName.allCases) { preset in
                    Button(preset.displayName) { model.apply(preset: preset) }
                }
            } label: {
                Label("Preset", systemImage: "hand.wave")
            }
            Spacer()
            Picker("Hand", selection: Binding(
                get: { model.editingChirality },
                set: { model.editingChirality = $0 }
            )) {
                Text("Left").tag(HandGesturePose.Chirality.left)
                Text("Right").tag(HandGesturePose.Chirality.right)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)
            Spacer()
            Toggle("Match either hand", isOn: Binding(
                get: { model.exportChirality == .either },
                set: { model.exportChirality = $0 ? .either : model.editingChirality }
            ))
            .toggleStyle(.switch)
            .fixedSize()
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                TextField("Gesture name", text: $model.name)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 6) {
                    Text("Threshold")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Slider(value: $model.threshold, in: 0.05...0.4)
                        .frame(width: 140)
                    Text(model.threshold, format: .number.precision(.fractionLength(2)))
                        .font(.callout.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }
            }

            DisclosureGroup("Fine tune fingers", isExpanded: $showFineTune) {
                ForEach(HandPoseTemplate.Finger.allCases) { finger in
                    fingerRow(finger)
                }
            }
            .font(.callout)

            HStack {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share JSON", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        exportURL = try? HandGestureExport.writeTemporaryFile(model.makeDefinition())
                    } label: {
                        Label("Export JSON", systemImage: "doc.badge.arrow.up")
                    }
                }
                Spacer()
                Button {
                    onSave?(model.makeDefinition())
                } label: {
                    Label("Save Gesture", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(onSave == nil)
            }
        }
    }

    private func fingerRow(_ finger: HandPoseTemplate.Finger) -> some View {
        HStack(spacing: 10) {
            Text(finger.rawValue.capitalized)
                .frame(width: 60, alignment: .leading)
                .foregroundStyle(.secondary)
            Text("Curl")
                .foregroundStyle(.tertiary)
            Slider(value: Binding(
                get: { model.template[finger].curl },
                set: { model.template[finger].curl = $0 }
            ), in: 0...1)
            Text("Splay")
                .foregroundStyle(.tertiary)
            Slider(value: Binding(
                get: { model.template[finger].splay },
                set: { model.template[finger].splay = $0 }
            ), in: -1...1)
        }
        .padding(.vertical, 2)
    }
}
