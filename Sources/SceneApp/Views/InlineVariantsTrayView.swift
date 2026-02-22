import SwiftUI

struct InlineVariantsTrayView: View {
    @EnvironmentObject private var store: AppStore

    private var visibleState: AppStore.InlineVariantGenerationState? {
        guard let state = store.inlineVariantGeneration else { return nil }
        guard state.sceneID == store.selectedSceneID else { return nil }
        return state
    }

    var body: some View {
        if let state = visibleState {
            VStack(alignment: .leading, spacing: 10) {
                headerRow(state: state)

                Picker("Variant", selection: variantSelectionBinding) {
                    ForEach(Array(state.candidates.indices), id: \.self) { index in
                        Text(variantTitle(index))
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
            get: { store.inlineVariantGeneration?.selectedIndex ?? 0 },
            set: { store.selectInlineVariantCandidate(index: $0) }
        )
    }

    private func headerRow(state: AppStore.InlineVariantGenerationState) -> some View {
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

    private func statusRow(state: AppStore.InlineVariantGenerationState) -> some View {
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
                Text(statusLabel(candidate.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func previewBox(state: AppStore.InlineVariantGenerationState) -> some View {
        let candidate = state.selectedCandidate
        let previewText = (candidate?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let errorText = candidate?.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let placeholder = state.isRunning ? "Generating..." : "No text."

        return VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(previewText.isEmpty ? placeholder : previewText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .font(.callout)
                    .foregroundStyle(previewText.isEmpty ? .secondary : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .frame(height: 180)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private func actionRow(state: AppStore.InlineVariantGenerationState) -> some View {
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

    private func variantTitle(_ index: Int) -> String {
        switch index {
        case 0: return "A"
        case 1: return "B"
        case 2: return "C"
        default: return "\(index + 1)"
        }
    }

    private func statusLabel(_ status: AppStore.InlineVariantCandidate.Status) -> String {
        switch status {
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .completed:
            return "Ready"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

