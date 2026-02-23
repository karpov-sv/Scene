import SwiftUI

struct ScenePlanPanelView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingStoryGraphEdgesSheet = false

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
        .sheet(isPresented: $showingStoryGraphEdgesSheet) {
            StoryGraphEdgesSheet()
                .environmentObject(store)
        }
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
                    showingStoryGraphEdgesSheet = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                .buttonStyle(.borderless)
                .help("Story Graph Edges")

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

private struct StoryGraphEdgesSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var draftFromID: UUID?
    @State private var draftRelation: StoryGraphRelation = .causes
    @State private var draftToID: UUID?

    private var sortedCompendiumEntries: [CompendiumEntry] {
        store.project.compendium.sorted { lhs, rhs in
            let lhsTitle = entryTitle(lhs)
            let rhsTitle = entryTitle(rhs)
            let comparison = lhsTitle.localizedCaseInsensitiveCompare(rhsTitle)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var availableToEntries: [CompendiumEntry] {
        guard let draftFromID else { return sortedCompendiumEntries }
        return sortedCompendiumEntries.filter { $0.id != draftFromID }
    }

    private var sortedEdges: [StoryGraphEdge] {
        store.project.storyGraphEdges.sorted { lhs, rhs in
            let lhsFrom = entryTitle(for: lhs.fromCompendiumID)
            let rhsFrom = entryTitle(for: rhs.fromCompendiumID)
            let fromComparison = lhsFrom.localizedCaseInsensitiveCompare(rhsFrom)
            if fromComparison != .orderedSame {
                return fromComparison == .orderedAscending
            }

            let relationComparison = lhs.relation.label.localizedCaseInsensitiveCompare(rhs.relation.label)
            if relationComparison != .orderedSame {
                return relationComparison == .orderedAscending
            }

            let lhsTo = entryTitle(for: lhs.toCompendiumID)
            let rhsTo = entryTitle(for: rhs.toCompendiumID)
            let toComparison = lhsTo.localizedCaseInsensitiveCompare(rhsTo)
            if toComparison != .orderedSame {
                return toComparison == .orderedAscending
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var canAddEdge: Bool {
        guard let fromID = draftFromID,
              let toID = draftToID else {
            return false
        }
        return fromID != toID
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Story Graph Edges")
                    .font(.headline)

                Spacer(minLength: 0)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Create Edge")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    Picker("From", selection: $draftFromID) {
                        Text("Select From").tag(Optional<UUID>.none)
                        ForEach(sortedCompendiumEntries) { entry in
                            Text(entryTitle(entry)).tag(Optional(entry.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)

                    Picker("Relation", selection: $draftRelation) {
                        ForEach(StoryGraphRelation.allCases) { relation in
                            Text(relation.label).tag(relation)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 150)

                    Picker("To", selection: $draftToID) {
                        Text("Select To").tag(Optional<UUID>.none)
                        ForEach(availableToEntries) { entry in
                            Text(entryTitle(entry)).tag(Optional(entry.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)

                    Button("Add") {
                        addDraftEdge()
                    }
                    .controlSize(.small)
                    .disabled(!canAddEdge)
                }
            }
            .padding(14)

            Divider()

            if sortedEdges.isEmpty {
                ContentUnavailableView(
                    "No Graph Edges",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Create an edge to connect compendium nodes.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sortedEdges) { edge in
                        HStack(spacing: 8) {
                            Text(entryTitle(for: edge.fromCompendiumID))
                                .lineLimit(1)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            Text(edge.relation.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            Text(entryTitle(for: edge.toCompendiumID))
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Button(role: .destructive) {
                                store.deleteStoryGraphEdge(edge.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete Edge")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 780, minHeight: 460)
        .onAppear {
            syncDraftSelection()
        }
        .onChange(of: draftFromID) { _, _ in
            syncDraftToSelection()
        }
        .onChange(of: store.project.compendium.map(\.id)) { _, _ in
            syncDraftSelection()
        }
    }

    private func addDraftEdge() {
        guard let fromID = draftFromID,
              let toID = draftToID else {
            return
        }
        _ = store.addStoryGraphEdge(
            fromCompendiumID: fromID,
            toCompendiumID: toID,
            relation: draftRelation
        )
        syncDraftSelection()
    }

    private func syncDraftSelection() {
        let allIDs = sortedCompendiumEntries.map(\.id)
        guard !allIDs.isEmpty else {
            draftFromID = nil
            draftToID = nil
            return
        }

        if draftFromID == nil || !allIDs.contains(where: { $0 == draftFromID }) {
            draftFromID = allIDs.first
        }
        syncDraftToSelection()
    }

    private func syncDraftToSelection() {
        let candidateIDs = availableToEntries.map(\.id)
        guard !candidateIDs.isEmpty else {
            draftToID = nil
            return
        }

        if let draftToID,
           candidateIDs.contains(where: { $0 == draftToID }) {
            return
        }
        draftToID = candidateIDs.first
    }

    private func entryTitle(_ entry: CompendiumEntry) -> String {
        let trimmed = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Entry" : trimmed
    }

    private func entryTitle(for entryID: UUID) -> String {
        guard let entry = store.project.compendium.first(where: { $0.id == entryID }) else {
            return "Missing Entry"
        }
        return entryTitle(entry)
    }
}
