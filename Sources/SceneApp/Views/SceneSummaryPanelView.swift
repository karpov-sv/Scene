import SwiftUI

struct SceneSummaryPanelView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isSummarizing: Bool = false

    private var selectedSummaryPromptBinding: Binding<UUID?> {
        Binding(
            get: { store.project.selectedSummaryPromptID },
            set: { store.setSelectedSummaryPrompt($0) }
        )
    }

    private var sceneSummaryBinding: Binding<String> {
        Binding(
            get: { store.selectedScene?.summary ?? "" },
            set: { store.updateSelectedSceneSummary($0) }
        )
    }

    private var summaryCharacterCount: Int {
        store.selectedScene?.summary.count ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(spacing: 10) {
                Picker("Summary Template", selection: selectedSummaryPromptBinding) {
                    ForEach(store.summaryPrompts) { prompt in
                        Text(prompt.title)
                            .tag(Optional(prompt.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 260)
                .disabled(store.summaryPrompts.isEmpty || isSummarizing)

                Spacer(minLength: 0)

                Button {
                    summarizeScene()
                } label: {
                    Group {
                        if isSummarizing {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Summarizing")
                            }
                        } else {
                            Label("Summarize", systemImage: "text.insert")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isSummarizing
                    || store.selectedScene == nil
                    || store.activeSummaryPrompt == nil
                )
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Scene Summary (\(summaryCharacterCount) chars)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                TextEditor(text: sceneSummaryBinding)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        Rectangle()
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scene Summary")
                .font(.headline)
            Text("Generate and edit a persistent summary for the selected scene.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func summarizeScene() {
        guard !isSummarizing else { return }
        guard store.selectedScene != nil else { return }

        isSummarizing = true
        Task { @MainActor in
            defer {
                isSummarizing = false
            }

            do {
                _ = try await store.summarizeSelectedScene()
            } catch is CancellationError {
                return
            } catch {
                store.lastError = error.localizedDescription
            }
        }
    }
}
