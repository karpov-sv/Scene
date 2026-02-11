import SwiftUI

struct EditorView: View {
    @EnvironmentObject private var store: AppStore

    private var sceneTitleBinding: Binding<String> {
        Binding(
            get: { store.selectedScene?.title ?? "" },
            set: { store.updateSelectedSceneTitle($0) }
        )
    }

    private var sceneContentBinding: Binding<String> {
        Binding(
            get: { store.selectedScene?.content ?? "" },
            set: { store.updateSelectedSceneContent($0) }
        )
    }

    private var selectedPromptBinding: Binding<UUID?> {
        Binding(
            get: { store.project.selectedProsePromptID },
            set: { store.setSelectedProsePrompt($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.selectedScene != nil {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Scene title", text: sceneTitleBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3.weight(.semibold))

                    TextEditor(text: sceneContentBinding)
                        .font(.body)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    generationPanel
                }
                .padding(16)
            } else {
                ContentUnavailableView("No Scene Selected", systemImage: "text.document", description: Text("Select or create a scene to start writing."))
            }
        }
    }

    private var generationPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Prompt", selection: selectedPromptBinding) {
                        Text("Default")
                            .tag(Optional<UUID>.none)
                        ForEach(store.prosePrompts) { prompt in
                            Text(prompt.title)
                                .tag(Optional(prompt.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260)

                    Spacer(minLength: 0)
                }

                TextEditor(text: $store.beatInput)
                    .frame(minHeight: 120)

                HStack {
                    if store.isGenerating {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Button {
                        Task {
                            await store.generateFromBeat()
                        }
                    } label: {
                        Label(store.isGenerating ? "Generating..." : "Generate Text", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.beatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isGenerating)
                }

                if !store.generationStatus.isEmpty {
                    Text(store.generationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } label: {
            Text("Generate From Beat")
        }
    }
}
