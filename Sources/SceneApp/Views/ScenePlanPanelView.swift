import SwiftUI

struct ScenePlanPanelView: View {
    private struct SceneGraphEdgesSheetRequest: Identifiable {
        let sceneID: UUID
        var id: UUID { sceneID }
    }

    @EnvironmentObject private var store: AppStore
    @State private var storyGraphSheetRequest: SceneGraphEdgesSheetRequest?

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
        .sheet(item: $storyGraphSheetRequest) { request in
            StoryGraphEdgesSheet(sceneID: request.sceneID)
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
                    guard let selectedSceneID = store.selectedSceneID else { return }
                    storyGraphSheetRequest = SceneGraphEdgesSheetRequest(sceneID: selectedSceneID)
                } label: {
                    Image(systemName: "list.bullet")
                }
                .buttonStyle(.borderless)
                .help("Story Graph Edges")
                .disabled(store.selectedSceneID == nil)

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

    let sceneID: UUID

    @State private var draftFromID: UUID?
    @State private var draftRelation: StoryGraphRelation = .causes
    @State private var draftToID: UUID?
    @State private var draftWeight: Double = 1.0
    @State private var draftNote: String = ""

    private var sceneTitle: String {
        for chapter in store.project.chapters {
            if let scene = chapter.scenes.first(where: { $0.id == sceneID }) {
                let trimmed = scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "Untitled Scene" : trimmed
            }
        }
        return "Unknown Scene"
    }

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

    private var sceneEdges: [StoryGraphEdge] {
        store.storyGraphEdges(for: sceneID).sorted { lhs, rhs in
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
        guard let fromID = draftFromID, let toID = draftToID else { return false }
        return fromID != toID
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Story Graph Edges")
                        .font(.headline)
                    Text("Scene: \(sceneTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
                }

                HStack(spacing: 8) {
                    Text("Weight")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Slider(value: $draftWeight, in: 0 ... 1, step: 0.05)

                    Text(String(format: "%.2f", draftWeight))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)

                    TextField("Optional note", text: $draftNote)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)

                    Button("Add") {
                        addDraftEdge()
                    }
                    .controlSize(.small)
                    .disabled(!canAddEdge)
                }
            }
            .padding(14)

            Divider()

            if sceneEdges.isEmpty {
                ContentUnavailableView(
                    "No Graph Edges",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Create scene-specific edges for graph planning.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sceneEdges) { edge in
                        storyGraphEdgeRow(edge)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 900, minHeight: 520)
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

    private func storyGraphEdgeRow(_ edge: StoryGraphEdge) -> some View {
        HStack(spacing: 8) {
            Picker("From", selection: fromCompendiumBinding(for: edge.id)) {
                ForEach(sortedCompendiumEntries) { entry in
                    Text(entryTitle(entry)).tag(Optional(entry.id))
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .labelsHidden()

            Picker("Relation", selection: relationBinding(for: edge.id)) {
                ForEach(StoryGraphRelation.allCases) { relation in
                    Text(relation.label).tag(relation)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 150)
            .labelsHidden()

            Picker("To", selection: toCompendiumBinding(for: edge.id)) {
                ForEach(sortedCompendiumEntries) { entry in
                    Text(entryTitle(entry)).tag(Optional(entry.id))
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .labelsHidden()

            Slider(value: weightBinding(for: edge.id), in: 0 ... 1, step: 0.05)
                .frame(width: 100)
                .help(String(format: "Weight: %.2f", edge.weight))

            TextField("Optional note", text: noteBinding(for: edge.id))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

            Button(role: .destructive) {
                store.deleteStoryGraphEdge(edge.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete Edge")
        }
        .padding(.vertical, 2)
    }

    private func edge(for edgeID: UUID) -> StoryGraphEdge? {
        store.project.storyGraphEdges.first(where: { $0.id == edgeID })
    }

    private func fromCompendiumBinding(for edgeID: UUID) -> Binding<UUID?> {
        Binding(
            get: { edge(for: edgeID)?.fromCompendiumID },
            set: { newFromID in
                guard let newFromID, let edge = edge(for: edgeID) else { return }
                store.updateStoryGraphEdgeEndpoints(
                    edgeID,
                    fromCompendiumID: newFromID,
                    toCompendiumID: edge.toCompendiumID
                )
            }
        )
    }

    private func toCompendiumBinding(for edgeID: UUID) -> Binding<UUID?> {
        Binding(
            get: { edge(for: edgeID)?.toCompendiumID },
            set: { newToID in
                guard let newToID, let edge = edge(for: edgeID) else { return }
                store.updateStoryGraphEdgeEndpoints(
                    edgeID,
                    fromCompendiumID: edge.fromCompendiumID,
                    toCompendiumID: newToID
                )
            }
        )
    }

    private func relationBinding(for edgeID: UUID) -> Binding<StoryGraphRelation> {
        Binding(
            get: { edge(for: edgeID)?.relation ?? .causes },
            set: { relation in
                store.updateStoryGraphEdgeRelation(edgeID, relation: relation)
            }
        )
    }

    private func weightBinding(for edgeID: UUID) -> Binding<Double> {
        Binding(
            get: { edge(for: edgeID)?.weight ?? 1.0 },
            set: { weight in
                store.updateStoryGraphEdgeWeight(edgeID, weight: weight)
            }
        )
    }

    private func noteBinding(for edgeID: UUID) -> Binding<String> {
        Binding(
            get: { edge(for: edgeID)?.note ?? "" },
            set: { note in
                store.updateStoryGraphEdgeNote(edgeID, note: note)
            }
        )
    }

    private func addDraftEdge() {
        guard let fromID = draftFromID, let toID = draftToID else {
            return
        }
        _ = store.addStoryGraphEdge(
            sceneID: sceneID,
            fromCompendiumID: fromID,
            toCompendiumID: toID,
            relation: draftRelation,
            weight: draftWeight,
            note: draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        draftNote = ""
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
