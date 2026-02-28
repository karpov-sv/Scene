import SwiftUI

struct StoryKnowledgePanelView: View {
    @EnvironmentObject private var store: AppStore
    @State private var refreshTask: Task<Void, Never>?
    @State private var refreshError: String = ""
    @State private var compendiumMergePreview: AppStore.StoryKnowledgeCompendiumMergePreview?
    @State private var selectedPendingNodeIDs: Set<UUID> = []
    @State private var selectedPendingEdgeIDs: Set<UUID> = []
    let onOpenCompendiumEntry: (UUID) -> Void

    private var isRefreshing: Bool {
        refreshTask != nil
    }

    private var acceptedNodes: [StoryKnowledgeNode] {
        store.storyKnowledgeActiveNodes.filter { $0.status == .canonical }
    }

    private var acceptedEdges: [StoryKnowledgeEdge] {
        store.storyKnowledgeActiveEdges.filter { $0.status == .canonical }
    }

    private var filteredAcceptedNodes: [StoryKnowledgeNode] {
        sort(nodes: acceptedNodes.filter { matchesNodeKind(node: $0) && matchesSearch(node: $0) })
    }

    private var filteredConflictItems: [AppStore.StoryKnowledgeConflictItem] {
        store.storyKnowledgeConflictItems.filter(matchesConflict(_:))
    }

    private var filteredAcceptedEdges: [StoryKnowledgeEdge] {
        sort(edges: acceptedEdges.filter {
            matchesNodeKind(edge: $0) && matchesRelation(edge: $0) && matchesSearch(edge: $0)
        })
    }

    private var filteredPendingNodes: [StoryKnowledgeNode] {
        sort(nodes: store.storyKnowledgePendingReviewNodes.filter {
            matchesNodeKind(node: $0) && matchesSearch(node: $0)
        })
    }

    private var filteredPendingEdges: [StoryKnowledgeEdge] {
        sort(edges: store.storyKnowledgePendingReviewEdges.filter {
            matchesNodeKind(edge: $0) && matchesRelation(edge: $0) && matchesSearch(edge: $0)
        })
    }

    private var hasAnyVisibleResults: Bool {
        !filteredAcceptedNodes.isEmpty
            || !filteredAcceptedEdges.isEmpty
            || !filteredPendingNodes.isEmpty
            || !filteredPendingEdges.isEmpty
    }

    private var visibleResultCount: Int {
        let acceptedCount = visibilityFilter == .pending ? 0 : filteredAcceptedNodes.count + filteredAcceptedEdges.count
        let pendingCount = visibilityFilter == .accepted ? 0 : filteredPendingNodes.count + filteredPendingEdges.count
        return acceptedCount + pendingCount
    }

    private var visiblePendingNodeIDSet: Set<UUID> {
        Set(filteredPendingNodes.map(\.id))
    }

    private var visiblePendingEdgeIDSet: Set<UUID> {
        Set(filteredPendingEdges.map(\.id))
    }

    private var visibleSelectedPendingNodeIDs: [UUID] {
        filteredPendingNodes.map(\.id).filter { selectedPendingNodeIDs.contains($0) }
    }

    private var visibleSelectedPendingEdgeIDs: [UUID] {
        filteredPendingEdges.map(\.id).filter { selectedPendingEdgeIDs.contains($0) }
    }

    private var visibilityFilter: StoryKnowledgePanelVisibilityFilter {
        store.storyKnowledgePanelState.visibilityFilter
    }

    private var sortMode: StoryKnowledgePanelSortMode {
        store.storyKnowledgePanelState.sortMode
    }

    private var nodeKindFilter: StoryKnowledgePanelNodeKindFilter {
        store.storyKnowledgePanelState.nodeKindFilter
    }

    private var relationFilter: String {
        store.storyKnowledgePanelState.relationFilter
    }

    private var relationFilterLabel: String {
        if relationFilter.isEmpty {
            return "All Relations"
        }
        return relationFilter.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var relationFilterOptions: [String] {
        var options = Set(
            (store.storyKnowledgeActiveEdges + store.storyKnowledgePendingReviewEdges)
                .map(\.relation)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
        if !relationFilter.isEmpty {
            options.insert(relationFilter)
        }
        return options.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { store.storyKnowledgePanelState.searchText },
            set: { store.setStoryKnowledgePanelSearchText($0) }
        )
    }

    private var visibilityFilterBinding: Binding<StoryKnowledgePanelVisibilityFilter> {
        Binding(
            get: { store.storyKnowledgePanelState.visibilityFilter },
            set: { store.setStoryKnowledgePanelVisibilityFilter($0) }
        )
    }

    private var sortModeBinding: Binding<StoryKnowledgePanelSortMode> {
        Binding(
            get: { store.storyKnowledgePanelState.sortMode },
            set: { store.setStoryKnowledgePanelSortMode($0) }
        )
    }

    private var nodeKindFilterBinding: Binding<StoryKnowledgePanelNodeKindFilter> {
        Binding(
            get: { store.storyKnowledgePanelState.nodeKindFilter },
            set: { store.setStoryKnowledgePanelNodeKindFilter($0) }
        )
    }

    private var relationFilterBinding: Binding<String> {
        Binding(
            get: { store.storyKnowledgePanelState.relationFilter },
            set: { store.setStoryKnowledgePanelRelationFilter($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    summarySection

                    if !store.selectedSceneRelevantStoryKnowledge.isEmpty {
                        textSection(
                            title: "Current Scene Neighborhood",
                            body: store.selectedSceneRelevantStoryKnowledge,
                            monospaced: true
                        )
                    }

                    if !filteredConflictItems.isEmpty {
                        conflictSection
                    }

                    if visibilityFilter != .pending {
                        nodeSection(
                            title: "Accepted Nodes",
                            emptyTitle: "No accepted nodes match the current filter.",
                            nodes: filteredAcceptedNodes
                        )

                        edgeSection(
                            title: "Accepted Edges",
                            emptyTitle: "No accepted edges match the current filter.",
                            edges: filteredAcceptedEdges
                        )
                    }

                    if visibilityFilter != .accepted {
                        pendingNodeSection(
                            title: "Pending Node Suggestions",
                            emptyTitle: "No node suggestions match the current filter.",
                            nodes: filteredPendingNodes
                        )

                        pendingEdgeSection(
                            title: "Pending Edge Suggestions",
                            emptyTitle: "No edge suggestions match the current filter.",
                            edges: filteredPendingEdges
                        )
                    }

                    if !hasAnyVisibleResults {
                        ContentUnavailableView(
                            "No Matches",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Try a different filter or search term.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(12)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Rebuild Scene") {
                    rebuildScene()
                }
                .disabled(isRefreshing || store.selectedScene == nil)

                Button("Rebuild Project") {
                    rebuildProject()
                }
                .disabled(isRefreshing)

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer(minLength: 0)
            }
            .padding(12)

            if !refreshError.isEmpty {
                Text(refreshError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .onDisappear {
            cancelRefresh()
        }
        .sheet(item: $compendiumMergePreview) { preview in
            StoryKnowledgeCompendiumMergeSheet(
                preview: preview,
                onOpenCompendiumEntry: onOpenCompendiumEntry
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Knowledge Graph")
                .font(.headline)

            Text("\(store.storyKnowledgeNodeCount) active nodes • \(store.storyKnowledgeEdgeCount) active edges")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(store.storyKnowledgePendingNodeCount) pending nodes • \(store.storyKnowledgePendingEdgeCount) pending edges")
                .font(.caption)
                .foregroundStyle(.secondary)

            if store.storyKnowledgeConflictCount > 0 {
                Text("\(store.storyKnowledgeConflictCount) potential conflicts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Visibility", selection: visibilityFilterBinding) {
                ForEach(StoryKnowledgePanelVisibilityFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Filter nodes and edges", text: searchTextBinding)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

            HStack(spacing: 8) {
                Picker("Sort", selection: sortModeBinding) {
                    ForEach(StoryKnowledgePanelSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Picker("Kind", selection: nodeKindFilterBinding) {
                    ForEach(StoryKnowledgePanelNodeKindFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Picker("Relation", selection: relationFilterBinding) {
                    Text("All Relations").tag("")
                    ForEach(relationFilterOptions, id: \.self) { relation in
                        Text(relation.replacingOccurrences(of: "_", with: " ").capitalized)
                            .tag(relation)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Spacer(minLength: 0)

                Text(matchCountLabel())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project Memory")
                .font(.headline)

            if store.projectStoryMemorySummary.isEmpty {
                Text("No project memory available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(store.projectStoryMemorySummary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardStyle()
    }

    private var conflictSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Potential Conflicts")
                .font(.headline)

            ForEach(filteredConflictItems) { item in
                StoryKnowledgeConflictCard(
                    item: item,
                    isUpdating: isRefreshing,
                    onRevealScene: { store.revealStoryKnowledgeEvidenceScene($0) },
                    onOpenCompendiumEntry: onOpenCompendiumEntry,
                    onReviewCompendiumMerge: { nodeID in
                        compendiumMergePreview = store.storyKnowledgeCompendiumMergePreview(for: nodeID)
                    },
                    onAcceptEdge: { edgeID in
                        selectedPendingEdgeIDs.remove(edgeID)
                        store.acceptStoryKnowledgeEdge(edgeID)
                    },
                    onRejectEdge: { edgeID in
                        selectedPendingEdgeIDs.remove(edgeID)
                        store.rejectStoryKnowledgeEdge(edgeID)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func textSection(title: String, body: String, monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(body)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle()
    }

    @ViewBuilder
    private func nodeSection(title: String, emptyTitle: String, nodes: [StoryKnowledgeNode]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if nodes.isEmpty {
                Text(emptyTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(nodes) { node in
                    StoryKnowledgeNodeCard(
                        node: node,
                        evidenceItems: store.storyKnowledgeEvidenceItems(for: node),
                        isUpdating: isRefreshing,
                        isSelected: false,
                        onToggleSelection: nil,
                        onRevealScene: { store.revealStoryKnowledgeEvidenceScene($0) },
                        onOpenCompendiumEntry: onOpenCompendiumEntry,
                        onUpdateCompendium: {
                            compendiumMergePreview = store.storyKnowledgeCompendiumMergePreview(for: node.id)
                        },
                        onPromote: { store.promoteStoryKnowledgeNodeToCompendium(node.id) },
                        onReject: { store.rejectStoryKnowledgeNode(node.id) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func edgeSection(title: String, emptyTitle: String, edges: [StoryKnowledgeEdge]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if edges.isEmpty {
                Text(emptyTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(edges) { edge in
                    StoryKnowledgeEdgeCard(
                        label: store.storyKnowledgeEdgeDisplayLabel(edge),
                        edge: edge,
                        evidenceItems: store.storyKnowledgeEvidenceItems(for: edge),
                        isUpdating: isRefreshing,
                        isSelected: false,
                        onToggleSelection: nil,
                        onRevealScene: { store.revealStoryKnowledgeEvidenceScene($0) },
                        onAccept: { store.acceptStoryKnowledgeEdge(edge.id) },
                        onReject: { store.rejectStoryKnowledgeEdge(edge.id) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func pendingNodeSection(title: String, emptyTitle: String, nodes: [StoryKnowledgeNode]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
                Text("\(visibleSelectedPendingNodeIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if nodes.isEmpty {
                Text(emptyTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                pendingBatchActionRow(
                    selectionCount: visibleSelectedPendingNodeIDs.count,
                    selectAllDisabled: visiblePendingNodeIDSet.isSubset(of: selectedPendingNodeIDs),
                    onSelectAll: { selectedPendingNodeIDs.formUnion(visiblePendingNodeIDSet) },
                    onClear: { selectedPendingNodeIDs.subtract(visiblePendingNodeIDSet) }
                ) {
                    Button("Promote Selected") {
                        let selectedIDs = visibleSelectedPendingNodeIDs
                        store.promoteStoryKnowledgeNodesToCompendium(selectedIDs)
                        selectedPendingNodeIDs.subtract(selectedIDs)
                    }
                    .disabled(visibleSelectedPendingNodeIDs.isEmpty || isRefreshing)

                    Button("Reject Selected", role: .destructive) {
                        let selectedIDs = visibleSelectedPendingNodeIDs
                        store.rejectStoryKnowledgeNodes(selectedIDs)
                        selectedPendingNodeIDs.subtract(selectedIDs)
                    }
                    .disabled(visibleSelectedPendingNodeIDs.isEmpty || isRefreshing)
                }

                ForEach(nodes) { node in
                    StoryKnowledgeNodeCard(
                        node: node,
                        evidenceItems: store.storyKnowledgeEvidenceItems(for: node),
                        isUpdating: isRefreshing,
                        isSelected: selectedPendingNodeIDs.contains(node.id),
                        onToggleSelection: { togglePendingNodeSelection(node.id) },
                        onRevealScene: { store.revealStoryKnowledgeEvidenceScene($0) },
                        onOpenCompendiumEntry: onOpenCompendiumEntry,
                        onUpdateCompendium: {
                            compendiumMergePreview = store.storyKnowledgeCompendiumMergePreview(for: node.id)
                        },
                        onPromote: {
                            selectedPendingNodeIDs.remove(node.id)
                            store.promoteStoryKnowledgeNodeToCompendium(node.id)
                        },
                        onReject: {
                            selectedPendingNodeIDs.remove(node.id)
                            store.rejectStoryKnowledgeNode(node.id)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func pendingEdgeSection(title: String, emptyTitle: String, edges: [StoryKnowledgeEdge]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
                Text("\(visibleSelectedPendingEdgeIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if edges.isEmpty {
                Text(emptyTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                pendingBatchActionRow(
                    selectionCount: visibleSelectedPendingEdgeIDs.count,
                    selectAllDisabled: visiblePendingEdgeIDSet.isSubset(of: selectedPendingEdgeIDs),
                    onSelectAll: { selectedPendingEdgeIDs.formUnion(visiblePendingEdgeIDSet) },
                    onClear: { selectedPendingEdgeIDs.subtract(visiblePendingEdgeIDSet) }
                ) {
                    Button("Accept Selected") {
                        let selectedIDs = visibleSelectedPendingEdgeIDs
                        store.acceptStoryKnowledgeEdges(selectedIDs)
                        selectedPendingEdgeIDs.subtract(selectedIDs)
                    }
                    .disabled(visibleSelectedPendingEdgeIDs.isEmpty || isRefreshing)

                    Button("Reject Selected", role: .destructive) {
                        let selectedIDs = visibleSelectedPendingEdgeIDs
                        store.rejectStoryKnowledgeEdges(selectedIDs)
                        selectedPendingEdgeIDs.subtract(selectedIDs)
                    }
                    .disabled(visibleSelectedPendingEdgeIDs.isEmpty || isRefreshing)
                }

                ForEach(edges) { edge in
                    StoryKnowledgeEdgeCard(
                        label: store.storyKnowledgeEdgeDisplayLabel(edge),
                        edge: edge,
                        evidenceItems: store.storyKnowledgeEvidenceItems(for: edge),
                        isUpdating: isRefreshing,
                        isSelected: selectedPendingEdgeIDs.contains(edge.id),
                        onToggleSelection: { togglePendingEdgeSelection(edge.id) },
                        onRevealScene: { store.revealStoryKnowledgeEvidenceScene($0) },
                        onAccept: {
                            selectedPendingEdgeIDs.remove(edge.id)
                            store.acceptStoryKnowledgeEdge(edge.id)
                        },
                        onReject: {
                            selectedPendingEdgeIDs.remove(edge.id)
                            store.rejectStoryKnowledgeEdge(edge.id)
                        }
                    )
                }
            }
        }
    }

    private func rebuildScene() {
        cancelRefresh()
        refreshError = ""

        refreshTask = Task { @MainActor in
            defer { refreshTask = nil }

            do {
                _ = try await store.rebuildSelectedSceneStoryMemory()
            } catch is CancellationError {
                return
            } catch {
                refreshError = error.localizedDescription
                store.lastError = error.localizedDescription
            }
        }
    }

    private func rebuildProject() {
        cancelRefresh()
        refreshError = ""

        refreshTask = Task { @MainActor in
            defer { refreshTask = nil }

            do {
                try await store.rebuildAllStoryMemory()
            } catch is CancellationError {
                return
            } catch {
                refreshError = error.localizedDescription
                store.lastError = error.localizedDescription
            }
        }
    }

    private func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func togglePendingNodeSelection(_ nodeID: UUID) {
        if selectedPendingNodeIDs.contains(nodeID) {
            selectedPendingNodeIDs.remove(nodeID)
        } else {
            selectedPendingNodeIDs.insert(nodeID)
        }
    }

    private func togglePendingEdgeSelection(_ edgeID: UUID) {
        if selectedPendingEdgeIDs.contains(edgeID) {
            selectedPendingEdgeIDs.remove(edgeID)
        } else {
            selectedPendingEdgeIDs.insert(edgeID)
        }
    }

    private func matchesSearch(node: StoryKnowledgeNode) -> Bool {
        let query = normalizedSearchQuery()
        guard !query.isEmpty else { return true }
        let haystack = [
            node.name,
            node.kind.rawValue,
            node.status.rawValue,
            node.summary,
            node.aliases.joined(separator: " ")
        ]
            .joined(separator: "\n")
            .lowercased()
        return haystack.contains(query)
    }

    private func matchesNodeKind(node: StoryKnowledgeNode) -> Bool {
        guard let selectedKind = nodeKindFilter.nodeKind else { return true }
        return node.kind == selectedKind
    }

    private func matchesNodeKind(edge: StoryKnowledgeEdge) -> Bool {
        guard let selectedKind = nodeKindFilter.nodeKind else { return true }
        let sourceKind = store.storyKnowledgeActiveNodes.first(where: { $0.id == edge.sourceNodeID })?.kind
            ?? store.storyKnowledgePendingReviewNodes.first(where: { $0.id == edge.sourceNodeID })?.kind
        let targetKind = store.storyKnowledgeActiveNodes.first(where: { $0.id == edge.targetNodeID })?.kind
            ?? store.storyKnowledgePendingReviewNodes.first(where: { $0.id == edge.targetNodeID })?.kind
        return sourceKind == selectedKind || targetKind == selectedKind
    }

    private func matchesRelation(edge: StoryKnowledgeEdge) -> Bool {
        relationFilter.isEmpty || edge.relation == relationFilter
    }

    private func matchesSearch(edge: StoryKnowledgeEdge) -> Bool {
        let query = normalizedSearchQuery()
        guard !query.isEmpty else { return true }
        let haystack = [
            store.storyKnowledgeEdgeDisplayLabel(edge),
            edge.status.rawValue,
            edge.note
        ]
            .joined(separator: "\n")
            .lowercased()
        return haystack.contains(query)
    }

    private func matchesConflict(_ item: AppStore.StoryKnowledgeConflictItem) -> Bool {
        if let selectedKind = nodeKindFilter.nodeKind,
           !item.nodeKinds.contains(selectedKind) {
            return false
        }
        if !relationFilter.isEmpty,
           normalizedRelationKey(item.relation) != normalizedRelationKey(relationFilter) {
            return false
        }

        let query = normalizedSearchQuery()
        guard !query.isEmpty else { return true }
        let haystack = (
            [item.title, item.detail]
            + item.acceptedReferences
            + item.evidenceItems.map { "\($0.chapterTitle) \($0.sceneTitle)" }
        )
        .joined(separator: "\n")
        .lowercased()
        return haystack.contains(query)
    }

    private func normalizedSearchQuery() -> String {
        store.storyKnowledgePanelState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedRelationKey(_ relation: String?) -> String {
        normalizedTextKey(relation ?? "")
    }

    private func normalizedTextKey(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
    }

    private func sort(nodes: [StoryKnowledgeNode]) -> [StoryKnowledgeNode] {
        nodes.sorted { lhs, rhs in
            switch sortMode {
            case .recent:
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
            case .confidence:
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
            case .evidence:
                if lhs.evidenceSceneIDs.count != rhs.evidenceSceneIDs.count {
                    return lhs.evidenceSceneIDs.count > rhs.evidenceSceneIDs.count
                }
            case .name:
                let lhsName = lhs.name.localizedLowercase
                let rhsName = rhs.name.localizedLowercase
                if lhsName != rhsName {
                    return lhsName < rhsName
                }
            }

            let lhsName = lhs.name.localizedLowercase
            let rhsName = rhs.name.localizedLowercase
            if lhsName != rhsName {
                return lhsName < rhsName
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func sort(edges: [StoryKnowledgeEdge]) -> [StoryKnowledgeEdge] {
        edges.sorted { lhs, rhs in
            switch sortMode {
            case .recent:
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
            case .confidence:
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
            case .evidence:
                if lhs.evidenceSceneIDs.count != rhs.evidenceSceneIDs.count {
                    return lhs.evidenceSceneIDs.count > rhs.evidenceSceneIDs.count
                }
            case .name:
                let lhsLabel = store.storyKnowledgeEdgeDisplayLabel(lhs).localizedLowercase
                let rhsLabel = store.storyKnowledgeEdgeDisplayLabel(rhs).localizedLowercase
                if lhsLabel != rhsLabel {
                    return lhsLabel < rhsLabel
                }
            }

            let lhsLabel = store.storyKnowledgeEdgeDisplayLabel(lhs).localizedLowercase
            let rhsLabel = store.storyKnowledgeEdgeDisplayLabel(rhs).localizedLowercase
            if lhsLabel != rhsLabel {
                return lhsLabel < rhsLabel
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func matchCountLabel() -> String {
        if nodeKindFilter != .all || !relationFilter.isEmpty {
            let scopeParts = [nodeKindFilter == .all ? nil : nodeKindFilter.title, relationFilter.isEmpty ? nil : relationFilterLabel]
                .compactMap { $0 }
                .joined(separator: " • ")
            if normalizedSearchQuery().isEmpty {
                return scopeParts.isEmpty ? "\(visibleResultCount) visible" : "\(visibleResultCount) visible • \(scopeParts)"
            }
            return scopeParts.isEmpty ? "\(visibleResultCount) matches" : "\(visibleResultCount) matches • \(scopeParts)"
        }
        if normalizedSearchQuery().isEmpty {
            return "\(visibleResultCount) visible"
        }
        return "\(visibleResultCount) matches"
    }
}

private struct StoryKnowledgeNodeCard: View {
    let node: StoryKnowledgeNode
    let evidenceItems: [AppStore.StoryKnowledgeEvidenceItem]
    let isUpdating: Bool
    let isSelected: Bool
    let onToggleSelection: (() -> Void)?
    let onRevealScene: @MainActor (UUID) -> Void
    let onOpenCompendiumEntry: (UUID) -> Void
    let onUpdateCompendium: () -> Void
    let onPromote: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let onToggleSelection {
                    selectionButton(isSelected: isSelected, action: onToggleSelection)
                        .disabled(isUpdating)
                }
                Text(node.name)
                    .font(.subheadline.weight(.semibold))
                statusBadge(node.status.rawValue.capitalized)
                statusBadge(node.kind.rawValue.capitalized)
                Spacer(minLength: 0)
                Text(confidenceLabel(node.confidence))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !node.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(node.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !node.aliases.isEmpty {
                Text("Aliases: \(node.aliases.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if node.resolvedCompendiumID != nil {
                Text("Linked to compendium")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !evidenceItems.isEmpty {
                evidenceSection(items: evidenceItems, onRevealScene: onRevealScene)
            }

            HStack(spacing: 8) {
                if let compendiumID = node.resolvedCompendiumID {
                    Button("Open Compendium") {
                        onOpenCompendiumEntry(compendiumID)
                    }
                    .disabled(isUpdating)

                    Button("Update Compendium") {
                        onUpdateCompendium()
                    }
                    .disabled(isUpdating)
                }

                if node.status == .inferred {
                    Button("Promote to Compendium") {
                        onPromote()
                    }
                    .disabled(isUpdating)

                    Button("Reject", role: .destructive) {
                        onReject()
                    }
                    .disabled(isUpdating)
                }
            }
            .buttonStyle(.borderless)
        }
        .cardStyle(isSelected: isSelected)
    }
}

private struct StoryKnowledgeEdgeCard: View {
    let label: String
    let edge: StoryKnowledgeEdge
    let evidenceItems: [AppStore.StoryKnowledgeEvidenceItem]
    let isUpdating: Bool
    let isSelected: Bool
    let onToggleSelection: (() -> Void)?
    let onRevealScene: @MainActor (UUID) -> Void
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let onToggleSelection {
                    selectionButton(isSelected: isSelected, action: onToggleSelection)
                        .disabled(isUpdating)
                }
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .textSelection(.enabled)
                statusBadge(edge.status.rawValue.capitalized)
                Spacer(minLength: 0)
                Text(confidenceLabel(edge.confidence))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !edge.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(edge.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !evidenceItems.isEmpty {
                evidenceSection(items: evidenceItems, onRevealScene: onRevealScene)
            }

            if edge.status == .inferred {
                HStack(spacing: 8) {
                    Button("Accept") {
                        onAccept()
                    }
                    .disabled(isUpdating)

                    Button("Reject", role: .destructive) {
                        onReject()
                    }
                    .disabled(isUpdating)
                }
                .buttonStyle(.borderless)
            }
        }
        .cardStyle(isSelected: isSelected)
    }
}

private struct StoryKnowledgeConflictCard: View {
    let item: AppStore.StoryKnowledgeConflictItem
    let isUpdating: Bool
    let onRevealScene: @MainActor (UUID) -> Void
    let onOpenCompendiumEntry: (UUID) -> Void
    let onReviewCompendiumMerge: (UUID) -> Void
    let onAcceptEdge: (UUID) -> Void
    let onRejectEdge: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .textSelection(.enabled)
                statusBadge(item.kind.title)
                Spacer(minLength: 0)
            }

            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !item.acceptedReferences.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accepted References")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(item.acceptedReferences, id: \.self) { reference in
                        Text(reference)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if !item.evidenceItems.isEmpty {
                evidenceSection(items: item.evidenceItems, onRevealScene: onRevealScene)
            }

            HStack(spacing: 8) {
                switch item.kind {
                case .edgeRelationConflict:
                    if let pendingEdgeID = item.pendingEdgeID {
                        Button("Accept Pending") {
                            onAcceptEdge(pendingEdgeID)
                        }
                        .disabled(isUpdating)

                        Button("Reject Pending", role: .destructive) {
                            onRejectEdge(pendingEdgeID)
                        }
                        .disabled(isUpdating)
                    }
                case .compendiumDrift:
                    if let compendiumID = item.compendiumID {
                        Button("Open Compendium") {
                            onOpenCompendiumEntry(compendiumID)
                        }
                        .disabled(isUpdating)
                    }

                    if let nodeID = item.nodeID {
                        Button("Review Merge") {
                            onReviewCompendiumMerge(nodeID)
                        }
                        .disabled(isUpdating)
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .cardStyle()
    }
}

private extension View {
    func cardStyle(isSelected: Bool = false) -> some View {
        self
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : Color(nsColor: .controlBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected
                            ? Color.accentColor
                            : Color(nsColor: .separatorColor),
                        lineWidth: 1
                    )
            )
    }
}

@MainActor
@ViewBuilder
private func pendingBatchActionRow<Actions: View>(
    selectionCount: Int,
    selectAllDisabled: Bool,
    onSelectAll: @escaping () -> Void,
    onClear: @escaping () -> Void,
    @ViewBuilder actions: () -> Actions
) -> some View {
    HStack(spacing: 8) {
        Button("Select All") {
            onSelectAll()
        }
        .disabled(selectAllDisabled)

        Button("Clear") {
            onClear()
        }
        .disabled(selectionCount == 0)

        Spacer(minLength: 0)

        actions()
    }
    .buttonStyle(.borderless)
}

@MainActor
@ViewBuilder
private func evidenceSection(
    items: [AppStore.StoryKnowledgeEvidenceItem],
    onRevealScene: @escaping @MainActor (UUID) -> Void
) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text("Evidence")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

        ForEach(items.prefix(6)) { item in
            Button("\(item.chapterTitle) / \(item.sceneTitle)") {
                onRevealScene(item.sceneID)
            }
            .buttonStyle(.link)
        }
    }
}

private func statusBadge(_ label: String) -> some View {
    Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(Capsule())
}

@MainActor
private func selectionButton(isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .imageScale(.medium)
    }
    .buttonStyle(.plain)
}

private func confidenceLabel(_ confidence: Double) -> String {
    "\(Int((confidence * 100).rounded()))%"
}

private struct StoryKnowledgeCompendiumMergeSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var preview: AppStore.StoryKnowledgeCompendiumMergePreview
    let onOpenCompendiumEntry: (UUID) -> Void

    init(
        preview: AppStore.StoryKnowledgeCompendiumMergePreview,
        onOpenCompendiumEntry: @escaping (UUID) -> Void
    ) {
        _preview = State(initialValue: preview)
        self.onOpenCompendiumEntry = onOpenCompendiumEntry
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Update Compendium Entry")
                        .font(.title3.weight(.semibold))
                    Text("\(preview.nodeName) -> \(preview.compendiumTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if preview.hasChanges {
                        if preview.currentTags != preview.updatedTags {
                            GroupBox("Tags") {
                                VStack(alignment: .leading, spacing: 8) {
                                    if !preview.addedTags.isEmpty {
                                        Text("Adding: \(preview.addedTags.joined(separator: ", "))")
                                            .font(.caption)
                                    }

                                    knowledgeMergeField(
                                        title: "Current",
                                        value: preview.currentTags.joined(separator: ", "),
                                        emptyLabel: "No tags"
                                    )

                                    knowledgeMergeField(
                                        title: "Updated",
                                        value: preview.updatedTags.joined(separator: ", "),
                                        emptyLabel: "No tags"
                                    )
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if preview.bodyWillChange {
                            GroupBox("Body") {
                                VStack(alignment: .leading, spacing: 8) {
                                    knowledgeMergeField(
                                        title: "Current",
                                        value: preview.currentBody,
                                        emptyLabel: "No body text"
                                    )

                                    knowledgeMergeField(
                                        title: "Updated",
                                        value: preview.updatedBody,
                                        emptyLabel: "No body text"
                                    )
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "No Canonical Changes",
                            systemImage: "checkmark.circle",
                            description: Text("This node is already reflected in the linked compendium entry.")
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Open Compendium") {
                    onOpenCompendiumEntry(preview.compendiumID)
                }

                Spacer(minLength: 0)

                if preview.hasTagChanges {
                    Button("Apply Tags") {
                        store.mergeStoryKnowledgeNodeTagsIntoCompendium(preview.nodeID)
                        refreshPreview()
                    }
                }

                if preview.bodyWillChange {
                    Button("Apply Summary") {
                        store.mergeStoryKnowledgeNodeSummaryIntoCompendium(preview.nodeID)
                        refreshPreview()
                    }
                }

                Button("Apply All") {
                    store.mergeStoryKnowledgeNodeIntoCompendium(preview.nodeID)
                    onOpenCompendiumEntry(preview.compendiumID)
                    refreshPreview(dismissIfUnchanged: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!preview.hasChanges)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private func refreshPreview(dismissIfUnchanged: Bool = false) {
        if let refreshed = store.storyKnowledgeCompendiumMergePreview(for: preview.nodeID) {
            preview = refreshed
            if dismissIfUnchanged && !refreshed.hasChanges {
                dismiss()
            }
        } else {
            dismiss()
        }
    }
}

@ViewBuilder
private func knowledgeMergeField(title: String, value: String, emptyLabel: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

        Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? emptyLabel : value)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
