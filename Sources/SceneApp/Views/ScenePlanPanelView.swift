import SwiftUI

struct ScenePlanPanelView: View {
    @EnvironmentObject private var store: AppStore

    private var planBinding: Binding<String> {
        Binding(
            get: { store.selectedSceneProsePlanDraft },
            set: { store.updateSelectedSceneProsePlanDraft($0) }
        )
    }

    private var selectedSceneTitle: String {
        guard let scene = store.selectedScene else { return "No Scene Selected" }
        let trimmed = scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Scene" : trimmed
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.selectedScene != nil {
                editor
            } else {
                ContentUnavailableView(
                    "No Scene Selected",
                    systemImage: "list.number",
                    description: Text("Select a scene to edit its generation plan.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scene Plan")
                .font(.headline)

            Text("Plan beats first, then draft prose from the plan.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Scene: \(selectedSceneTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button("Update Plan") {
                    store.submitProsePlanUpdate()
                }
                .disabled(store.isProseGenerationRunning || store.selectedScene == nil)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Draft from Plan") {
                    store.submitDraftFromSelectedScenePlan()
                }
                .disabled(store.isProseGenerationRunning || !store.canDraftFromSelectedScenePlan || store.selectedScene == nil)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Clear Plan", role: .destructive) {
                    store.clearSelectedSceneProsePlanDraft()
                }
                .disabled(store.selectedSceneProsePlanDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)

                Text("\(store.selectedSceneProsePlanDraft.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editor: some View {
        TextEditor(text: planBinding)
            .font(.system(size: 13))
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                Rectangle()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(store.isProseGenerationRunning)
    }
}
