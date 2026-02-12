import SwiftUI

struct SceneSummaryPanelView: View {
    @EnvironmentObject private var store: AppStore
    @Binding private var scope: SummaryScope
    @State private var isSummarizing: Bool = false

    init(scope: Binding<SummaryScope>) {
        self._scope = scope
    }

    private var selectedSummaryPromptBinding: Binding<UUID?> {
        Binding(
            get: { store.project.selectedSummaryPromptID },
            set: { store.setSelectedSummaryPrompt($0) }
        )
    }

    private var summaryBinding: Binding<String> {
        Binding(
            get: {
                switch scope {
                case .scene:
                    return store.selectedScene?.summary ?? ""
                case .chapter:
                    return store.selectedChapter?.summary ?? ""
                }
            },
            set: { value in
                switch scope {
                case .scene:
                    store.updateSelectedSceneSummary(value)
                case .chapter:
                    store.updateSelectedChapterSummary(value)
                }
            }
        )
    }

    private var summaryCharacterCount: Int {
        switch scope {
        case .scene:
            return store.selectedScene?.summary.count ?? 0
        case .chapter:
            return store.selectedChapter?.summary.count ?? 0
        }
    }

    private var summaryTitle: String {
        switch scope {
        case .scene:
            return "Scene Summary"
        case .chapter:
            return "Chapter Summary"
        }
    }

    private var summaryDescription: String {
        switch scope {
        case .scene:
            return "Generate and edit a persistent summary for the selected scene."
        case .chapter:
            return "Generate and edit a persistent summary for the selected chapter."
        }
    }

    private var canSummarizeCurrentScope: Bool {
        switch scope {
        case .scene:
            return store.selectedScene != nil
        case .chapter:
            return store.selectedChapter != nil
        }
    }

    private var canClearCurrentScope: Bool {
        guard canSummarizeCurrentScope, !isSummarizing else {
            return false
        }
        return !summaryBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Picker("Summary Scope", selection: $scope) {
                        ForEach(SummaryScope.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Picker("Summary Template", selection: selectedSummaryPromptBinding) {
                        ForEach(store.summaryPrompts) { prompt in
                            Text(prompt.title)
                                .tag(Optional(prompt.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    .disabled(store.summaryPrompts.isEmpty || isSummarizing)

                    Spacer(minLength: 0)

                    Button("Clear") {
                        clearCurrentScope()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canClearCurrentScope)

                    Button {
                        summarizeCurrentScope()
                    } label: {
                        Group {
                            if isSummarizing {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Summarizing \(scope.title)")
                                }
                            } else {
                                Label("Summarize", systemImage: "text.insert")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isSummarizing
                        || !canSummarizeCurrentScope
                        || store.activeSummaryPrompt == nil
                    )
                }
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("\(summaryTitle) (\(summaryCharacterCount) chars)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                TextEditor(text: summaryBinding)
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
            Text("Summary")
                .font(.headline)
            Text(summaryDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func summarizeCurrentScope() {
        guard !isSummarizing else { return }
        guard canSummarizeCurrentScope else { return }

        isSummarizing = true
        let targetScope = scope
        Task { @MainActor in
            defer {
                isSummarizing = false
            }

            do {
                switch targetScope {
                case .scene:
                    _ = try await store.summarizeSelectedScene()
                case .chapter:
                    _ = try await store.summarizeSelectedChapter()
                }
            } catch is CancellationError {
                return
            } catch {
                store.lastError = error.localizedDescription
            }
        }
    }

    private func clearCurrentScope() {
        switch scope {
        case .scene:
            store.updateSelectedSceneSummary("")
        case .chapter:
            store.updateSelectedChapterSummary("")
        }
    }
}
