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

            Text("Plan beats first, then draft prose from the plan. Use graph planning to derive paths from compendium nodes and graph edges.")
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
                Button {
                    store.submitProsePlanUpdate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Update Plan")
                .disabled(store.isProseGenerationRunning || store.selectedScene == nil)

                Button {
                    store.submitGraphPathPlanUpdate()
                } label: {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.borderless)
                .help("Plan from Graph")
                .disabled(store.isProseGenerationRunning || store.selectedScene == nil)

                Button {
                    store.submitDraftFromSelectedScenePlan()
                } label: {
                    Image(systemName: "long.text.page.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("Draft from Plan")
                .disabled(store.isProseGenerationRunning || !store.canDraftFromSelectedScenePlan || store.selectedScene == nil)

                Button {
                    store.clearSelectedSceneProsePlanDraft()
                } label: {
                    Image(systemName: "trash.slash")
                }
                .buttonStyle(.borderless)
                .help("Clear Plan")
                .disabled(store.selectedSceneProsePlanDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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
