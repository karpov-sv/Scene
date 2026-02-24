import SwiftUI

struct InlineVariantsTrayView: View {
    @EnvironmentObject private var store: AppStore

    private var visibleState: AppStore.ProseCandidateSessionState? {
        guard let state = store.inlineVariantSession else { return nil }
        guard state.sceneID == store.selectedSceneID else { return nil }
        return state
    }

    var body: some View {
        if let state = visibleState {
            VStack(alignment: .leading, spacing: 10) {
                headerRow(state: state)

                Picker("Variant", selection: variantSelectionBinding) {
                    ForEach(Array(state.candidates.indices), id: \.self) { index in
                        Text(candidateTitle(state: state, index: index))
                            .tag(index)
                    }
                }
                .pickerStyle(.segmented)

                statusRow(state: state)

                previewBox(state: state)

                actionRow(state: state)
            }
            .frame(width: 380)
            .padding(10)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.quaternary)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        }
    }

    private var variantSelectionBinding: Binding<Int> {
        Binding(
            get: { store.inlineVariantSession?.selectedIndex ?? 0 },
            set: { store.selectInlineVariantCandidate(index: $0) }
        )
    }

    private func headerRow(state: AppStore.ProseCandidateSessionState) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Variants")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button {
                if store.isGenerating {
                    store.cancelBeatGeneration()
                }
                store.dismissInlineVariantGeneration()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close variants.")
        }
    }

    private func statusRow(state: AppStore.ProseCandidateSessionState) -> some View {
        let completed = min(state.completedCount, state.candidates.count)
        let total = state.candidates.count

        return HStack(alignment: .center, spacing: 8) {
            if state.isRunning {
                ProgressView()
                    .controlSize(.small)
            }

            Text(state.isRunning ? "Generating \(completed)/\(total)..." : "\(state.successCount)/\(total) ready")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let candidate = state.selectedCandidate {
                Text(GenerationCandidateUI.statusLabel(candidate.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func previewBox(state: AppStore.ProseCandidateSessionState) -> some View {
        let candidate = state.selectedCandidate
        let previewText = (candidate?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let errorText = candidate?.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let placeholder = state.isRunning ? "Generating..." : "No text."

        return VStack(alignment: .leading, spacing: 8) {
            GenerationCandidateTextPreview(
                text: previewText,
                placeholder: placeholder,
                fixedHeight: 180,
                font: .callout,
                chromeStyle: .subtle
            )

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private func actionRow(state: AppStore.ProseCandidateSessionState) -> some View {
        let selectedText = state.selectedCandidate?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedFailed = state.selectedCandidate?.status == .failed
        let canAccept = !store.isGenerating && !state.isRunning && !selectedText.isEmpty && !selectedFailed

        return HStack(alignment: .center, spacing: 8) {
            Button {
                store.acceptInlineVariantCandidate()
            } label: {
                Text("Accept")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAccept)

            Button {
                store.regenerateInlineVariants()
            } label: {
                Text("Regenerate")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(store.isGenerating)
        }
    }

    private func candidateTitle(state: AppStore.ProseCandidateSessionState, index: Int) -> String {
        guard state.candidates.indices.contains(index) else { return "\(index + 1)" }
        let label = state.candidates[index].model.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "\(index + 1)" : label
    }

}
