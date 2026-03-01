import SwiftUI

struct StoryKnowledgePanelView: View {
    private struct ConflictFocus: Equatable {
        let label: String
        let nodeIDs: Set<UUID>
        let compendiumID: UUID?
    }

    private enum GraphDensityMode: String, CaseIterable, Identifiable {
        case balanced
        case wide
        case project

        var id: String { rawValue }

        var title: String {
            switch self {
            case .balanced:
                return "Balanced"
            case .wide:
                return "Wide"
            case .project:
                return "Project"
            }
        }

        var acceptedEdgeBudget: Int {
            switch self {
            case .balanced:
                return 36
            case .wide:
                return 56
            case .project:
                return 112
            }
        }

        var pendingEdgeBudget: Int {
            switch self {
            case .balanced:
                return 18
            case .wide:
                return 28
            case .project:
                return 52
            }
        }

        var totalEdgeCap: Int {
            switch self {
            case .balanced:
                return 54
            case .wide:
                return 80
            case .project:
                return 164
            }
        }

        var nodeCap: Int {
            switch self {
            case .balanced:
                return 34
            case .wide:
                return 48
            case .project:
                return 96
            }
        }
    }

    private struct GraphClusterRelationSummary: Identifiable {
        let relation: String
        let count: Int

        var id: String { relation }

        var displayLabel: String {
            relation.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private struct GraphClusterSummary: Identifiable {
        let kind: StoryKnowledgeNodeKind
        let nodeCount: Int
        let canonicalNodeCount: Int
        let pendingNodeCount: Int
        let incidentEdgeCount: Int
        let crossKindEdgeCount: Int
        let topRelations: [GraphClusterRelationSummary]

        var id: String { kind.rawValue }
    }

    private struct GraphClusterConnectionSummary: Identifiable {
        let sourceKind: StoryKnowledgeNodeKind
        let targetKind: StoryKnowledgeNodeKind
        let edgeCount: Int
        let pairCount: Int
        let pendingEdgeCount: Int
        let topRelations: [GraphClusterRelationSummary]
        let evidenceItems: [AppStore.StoryKnowledgeEvidenceItem]

        var id: String {
            "\(sourceKind.rawValue)->\(targetKind.rawValue)"
        }

        var title: String {
            "\(sourceKind.rawValue.capitalized) -> \(targetKind.rawValue.capitalized)"
        }
    }

    private struct GraphClusterConnectionFocus: Equatable {
        let sourceKind: StoryKnowledgeNodeKind
        let targetKind: StoryKnowledgeNodeKind

        var label: String {
            "Focused link: \(sourceKind.rawValue.capitalized) -> \(targetKind.rawValue.capitalized)"
        }
    }

    private struct GraphRelationFocus: Equatable {
        let relation: String

        var label: String {
            "Focused relation: \(relation.replacingOccurrences(of: "_", with: " ").capitalized)"
        }
    }

    private struct GraphFocusedLinkRelationSummary: Identifiable {
        let relation: String
        let edgeCount: Int
        let pairCount: Int
        let pendingEdgeCount: Int
        let pairLabels: [String]
        let evidenceItems: [AppStore.StoryKnowledgeEvidenceItem]

        var id: String { relation }

        var displayLabel: String {
            relation.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private struct DerivedStateKey: Equatable {
        let projectUpdatedAt: Date
        let visibilityFilter: StoryKnowledgePanelVisibilityFilter
        let sortMode: StoryKnowledgePanelSortMode
        let nodeKindFilter: StoryKnowledgePanelNodeKindFilter
        let relationFilter: String
        let searchText: String
        let focusLabel: String?
        let focusNodeIDs: [UUID]
        let focusCompendiumID: UUID?
        let showingExpandedGraph: Bool
        let expandedGraphDensity: GraphDensityMode
        let expandedGraphLayoutMode: StoryKnowledgeNeighborhoodGraphView.LayoutMode
        let expandedGraphConnectionFocus: GraphClusterConnectionFocus?
        let expandedGraphRelationFocus: GraphRelationFocus?
        let expandedGraphCollapsedKinds: [String]
        let expandedGraphIsolatedKinds: [String]
    }

    private struct PanelDerivedState {
        var storyKnowledgeNodesByID: [UUID: StoryKnowledgeNode] = [:]
        var filteredAcceptedNodes: [StoryKnowledgeNode] = []
        var filteredConflictItems: [AppStore.StoryKnowledgeConflictItem] = []
        var filteredAcceptedEdges: [StoryKnowledgeEdge] = []
        var filteredPendingNodes: [StoryKnowledgeNode] = []
        var filteredPendingEdges: [StoryKnowledgeEdge] = []
        var filteredAcceptedEdgesIgnoringSearch: [StoryKnowledgeEdge] = []
        var filteredPendingEdgesIgnoringSearch: [StoryKnowledgeEdge] = []
        var collapsedRelationSummaries: [CollapsedRelationSummary] = []
        var graphConnectionFocusedAcceptedEdges: [StoryKnowledgeEdge] = []
        var graphConnectionFocusedPendingEdges: [StoryKnowledgeEdge] = []
        var graphConnectionVisibleEdges: [StoryKnowledgeEdge] = []
        var graphBaseAcceptedEdges: [StoryKnowledgeEdge] = []
        var graphBasePendingEdges: [StoryKnowledgeEdge] = []
        var graphBaseAcceptedEdgesIgnoringSearch: [StoryKnowledgeEdge] = []
        var graphBasePendingEdgesIgnoringSearch: [StoryKnowledgeEdge] = []
        var graphBaseEdgesIgnoringSearch: [StoryKnowledgeEdge] = []
        var graphVisibleEdges: [StoryKnowledgeEdge] = []
        var graphVisibleNodes: [StoryKnowledgeNode] = []
        var graphVisibleNodesByID: [UUID: StoryKnowledgeNode] = [:]
        var graphVisibleEdgesByID: [UUID: StoryKnowledgeEdge] = [:]
        var graphIncidentEdgesByNodeID: [UUID: [StoryKnowledgeEdge]] = [:]
        var graphNavigableNodes: [StoryKnowledgeNode] = []
        var graphNavigableEdges: [StoryKnowledgeEdge] = []
        var graphNodeModels: [StoryKnowledgeNeighborhoodGraphView.NodeModel] = []
        var graphEdgeModels: [StoryKnowledgeNeighborhoodGraphView.EdgeModel] = []
        var graphCoverageLabel: String = "0 filtered nodes • 0 filtered edges"
        var graphClusterSummaries: [GraphClusterSummary] = []
        var graphClusterConnectionSummaries: [GraphClusterConnectionSummary] = []
        var graphClusterConnectionSummaryLookup: [String: GraphClusterConnectionSummary] = [:]
        var graphFocusedLinkRelationSummaries: [GraphFocusedLinkRelationSummary] = []
        var graphFocusedLinkRelationSummaryLookup: [String: GraphFocusedLinkRelationSummary] = [:]
    }

    private struct CollapsedRelationSummary: Identifiable {
        let relation: String
        let observedRelations: [StoryKnowledgeObservedRelation]
        let edgeCount: Int
        let pendingEdgeCount: Int

        var id: String { relation }
    }

    @EnvironmentObject private var store: AppStore
    @State private var refreshTask: Task<Void, Never>?
    @State private var refreshError: String = ""
    @State private var compendiumMergePreview: AppStore.StoryKnowledgeCompendiumMergePreview?
    @State private var selectedPendingNodeIDs: Set<UUID> = []
    @State private var selectedPendingEdgeIDs: Set<UUID> = []
    @State private var conflictFocus: ConflictFocus?
    @State private var graphSelectedNodeID: UUID?
    @State private var graphSelectedEdgeID: UUID?
    @State private var showingExpandedGraph = false
    @State private var expandedGraphDensity: GraphDensityMode = .balanced
    @State private var expandedGraphLayoutMode: StoryKnowledgeNeighborhoodGraphView.LayoutMode = .neighborhood
    @State private var expandedGraphConnectionFocus: GraphClusterConnectionFocus?
    @State private var expandedGraphRelationFocus: GraphRelationFocus?
    @State private var expandedGraphCollapsedKinds: Set<StoryKnowledgeNodeKind> = []
    @State private var expandedGraphIsolatedKinds: Set<StoryKnowledgeNodeKind> = []
    @State private var derivedState = PanelDerivedState()
    let onOpenCompendiumEntry: (UUID) -> Void

    private var isRefreshing: Bool {
        refreshTask != nil
    }

    private var mergedStoryKnowledgeNodes: [StoryKnowledgeNode] {
        deduplicatedStoryKnowledgeNodes(
            store.storyKnowledgeActiveNodes + store.storyKnowledgePendingReviewNodes
        )
    }

    private var deduplicatedAcceptedNodes: [StoryKnowledgeNode] {
        deduplicatedStoryKnowledgeNodes(
            store.storyKnowledgeActiveNodes.filter { $0.status == .canonical }
        )
    }

    private var deduplicatedPendingNodes: [StoryKnowledgeNode] {
        deduplicatedStoryKnowledgeNodes(store.storyKnowledgePendingReviewNodes)
    }

    private var deduplicatedAcceptedEdges: [StoryKnowledgeEdge] {
        deduplicatedStoryKnowledgeEdges(
            store.storyKnowledgeActiveEdges.filter { $0.status == .canonical }
        )
    }

    private var deduplicatedPendingEdges: [StoryKnowledgeEdge] {
        deduplicatedStoryKnowledgeEdges(store.storyKnowledgePendingReviewEdges)
    }

    private var storyKnowledgeNodesByID: [UUID: StoryKnowledgeNode] {
        if !derivedState.storyKnowledgeNodesByID.isEmpty {
            return derivedState.storyKnowledgeNodesByID
        }
        return Dictionary(uniqueKeysWithValues: mergedStoryKnowledgeNodes.map { ($0.id, $0) })
    }

    private var acceptedNodes: [StoryKnowledgeNode] {
        deduplicatedAcceptedNodes
    }

    private var acceptedEdges: [StoryKnowledgeEdge] {
        deduplicatedAcceptedEdges
    }

    private var derivedStateKey: DerivedStateKey {
        DerivedStateKey(
            projectUpdatedAt: store.project.updatedAt,
            visibilityFilter: visibilityFilter,
            sortMode: sortMode,
            nodeKindFilter: nodeKindFilter,
            relationFilter: relationFilter,
            searchText: store.storyKnowledgePanelState.searchText,
            focusLabel: conflictFocus?.label,
            focusNodeIDs: Array(conflictFocus?.nodeIDs ?? []).sorted { $0.uuidString < $1.uuidString },
            focusCompendiumID: conflictFocus?.compendiumID,
            showingExpandedGraph: showingExpandedGraph,
            expandedGraphDensity: expandedGraphDensity,
            expandedGraphLayoutMode: expandedGraphLayoutMode,
            expandedGraphConnectionFocus: expandedGraphConnectionFocus,
            expandedGraphRelationFocus: expandedGraphRelationFocus,
            expandedGraphCollapsedKinds: expandedGraphCollapsedKinds.map(\.rawValue).sorted(),
            expandedGraphIsolatedKinds: expandedGraphIsolatedKinds.map(\.rawValue).sorted()
        )
    }

    private var filteredAcceptedNodes: [StoryKnowledgeNode] {
        derivedState.filteredAcceptedNodes
    }

    private var filteredConflictItems: [AppStore.StoryKnowledgeConflictItem] {
        derivedState.filteredConflictItems
    }

    private var filteredAcceptedEdges: [StoryKnowledgeEdge] {
        derivedState.filteredAcceptedEdges
    }

    private var filteredPendingNodes: [StoryKnowledgeNode] {
        derivedState.filteredPendingNodes
    }

    private var filteredPendingEdges: [StoryKnowledgeEdge] {
        derivedState.filteredPendingEdges
    }

    private var filteredAcceptedEdgesIgnoringSearch: [StoryKnowledgeEdge] {
        derivedState.filteredAcceptedEdgesIgnoringSearch
    }

    private var filteredPendingEdgesIgnoringSearch: [StoryKnowledgeEdge] {
        derivedState.filteredPendingEdgesIgnoringSearch
    }

    private var hasAnyVisibleResults: Bool {
        !filteredConflictItems.isEmpty
            || !filteredAcceptedNodes.isEmpty
            || !filteredAcceptedEdges.isEmpty
            || !filteredPendingNodes.isEmpty
            || !filteredPendingEdges.isEmpty
    }

    private var visibleResultCount: Int {
        let conflictCount = filteredConflictItems.count
        let acceptedCount = visibilityFilter == .pending ? 0 : filteredAcceptedNodes.count + filteredAcceptedEdges.count
        let pendingCount = visibilityFilter == .accepted ? 0 : filteredPendingNodes.count + filteredPendingEdges.count
        return conflictCount + acceptedCount + pendingCount
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

    private var visibleDiagnosticEdges: [StoryKnowledgeEdge] {
        let accepted = visibilityFilter == .pending ? [] : filteredAcceptedEdges
        let pending = visibilityFilter == .accepted ? [] : filteredPendingEdges
        return accepted + pending
    }

    private var collapsedRelationSummaries: [CollapsedRelationSummary] {
        derivedState.collapsedRelationSummaries
    }

    private var collapsedRelationEdgeCount: Int {
        collapsedRelationSummaries.reduce(0) { $0 + $1.edgeCount }
    }

    private var collapsedRelationAliasCount: Int {
        Set(collapsedRelationSummaries.flatMap { $0.observedRelations.map(\.rawRelation) }).count
    }

    private var graphCandidateEdges: [StoryKnowledgeEdge] {
        let accepted = visibilityFilter == .pending ? [] : filteredAcceptedEdges
        let pending = visibilityFilter == .accepted ? [] : filteredPendingEdges
        return deduplicatedStoryKnowledgeEdges(accepted + pending)
    }

    private var graphCandidateNodes: [StoryKnowledgeNode] {
        switch visibilityFilter {
        case .pending:
            return filteredPendingNodes
        case .accepted:
            return filteredAcceptedNodes
        case .all:
            return deduplicatedStoryKnowledgeNodes(filteredAcceptedNodes + filteredPendingNodes)
        }
    }

    private var activeExpandedGraphConnectionFocus: GraphClusterConnectionFocus? {
        guard showingExpandedGraph, expandedGraphLayoutMode == .kindClusters else { return nil }
        return expandedGraphConnectionFocus
    }

    private var activeExpandedGraphCollapsedKinds: Set<StoryKnowledgeNodeKind> {
        guard showingExpandedGraph, expandedGraphLayoutMode == .kindClusters else { return [] }
        return expandedGraphCollapsedKinds
    }

    private var activeExpandedGraphIsolatedKinds: Set<StoryKnowledgeNodeKind> {
        guard showingExpandedGraph, expandedGraphLayoutMode == .kindClusters else { return [] }
        return expandedGraphIsolatedKinds
    }

    private var hasExpandedGraphClusterCanvasScope: Bool {
        !activeExpandedGraphIsolatedKinds.isEmpty || !activeExpandedGraphCollapsedKinds.isEmpty
    }

    private var isolatedClusterScopeLabel: String {
        let names = activeExpandedGraphIsolatedKinds
            .map(\.rawValue.capitalized)
            .sorted()
            .joined(separator: ", ")
        return activeExpandedGraphIsolatedKinds.count == 1
            ? "Isolated cluster: \(names)"
            : "Isolated clusters: \(names)"
    }

    private var activeExpandedGraphRelationFocus: GraphRelationFocus? {
        guard showingExpandedGraph,
              expandedGraphLayoutMode == .kindClusters,
              activeExpandedGraphConnectionFocus != nil else { return nil }
        return expandedGraphRelationFocus
    }

    private var graphConnectionFocusedAcceptedEdges: [StoryKnowledgeEdge] {
        derivedState.graphConnectionFocusedAcceptedEdges
    }

    private var graphConnectionFocusedPendingEdges: [StoryKnowledgeEdge] {
        derivedState.graphConnectionFocusedPendingEdges
    }

    private var graphConnectionVisibleEdges: [StoryKnowledgeEdge] {
        derivedState.graphConnectionVisibleEdges
    }

    private var graphBaseAcceptedEdges: [StoryKnowledgeEdge] {
        derivedState.graphBaseAcceptedEdges
    }

    private var graphBasePendingEdges: [StoryKnowledgeEdge] {
        derivedState.graphBasePendingEdges
    }

    private var graphBaseAcceptedEdgesIgnoringSearch: [StoryKnowledgeEdge] {
        derivedState.graphBaseAcceptedEdgesIgnoringSearch
    }

    private var graphBasePendingEdgesIgnoringSearch: [StoryKnowledgeEdge] {
        derivedState.graphBasePendingEdgesIgnoringSearch
    }

    private var graphBaseEdges: [StoryKnowledgeEdge] {
        let accepted = visibilityFilter == .pending ? [] : graphBaseAcceptedEdges
        let pending = visibilityFilter == .accepted ? [] : graphBasePendingEdges
        return accepted + pending
    }

    private var graphBaseEdgesIgnoringSearch: [StoryKnowledgeEdge] {
        derivedState.graphBaseEdgesIgnoringSearch
    }

    private var activeGraphDensityMode: GraphDensityMode? {
        showingExpandedGraph ? expandedGraphDensity : nil
    }

    private var expandedGraphLabelDensity: StoryKnowledgeNeighborhoodGraphView.LabelDensity {
        switch expandedGraphDensity {
        case .balanced:
            return .standard
        case .wide:
            return .compact
        case .project:
            return .sparse
        }
    }

    private var graphVisibleEdges: [StoryKnowledgeEdge] {
        derivedState.graphVisibleEdges
    }

    private var graphVisibleNodes: [StoryKnowledgeNode] {
        derivedState.graphVisibleNodes
    }

    private var graphPreferredAnchorNodeIDs: [UUID] {
        if let conflictFocus {
            return Array(conflictFocus.nodeIDs)
        }
        return []
    }

    private var selectedGraphNode: StoryKnowledgeNode? {
        guard let graphSelectedNodeID else { return nil }
        return derivedState.graphVisibleNodesByID[graphSelectedNodeID]
    }

    private var selectedGraphNodeIncidentEdges: [StoryKnowledgeEdge] {
        guard let graphSelectedNodeID else { return [] }
        return derivedState.graphIncidentEdgesByNodeID[graphSelectedNodeID] ?? []
    }

    private var selectedGraphEdge: StoryKnowledgeEdge? {
        guard let graphSelectedEdgeID else { return nil }
        return derivedState.graphVisibleEdgesByID[graphSelectedEdgeID]
    }

    private var hasGraphSelection: Bool {
        selectedGraphEdge != nil || selectedGraphNode != nil
    }

    private var graphNavigableNodes: [StoryKnowledgeNode] {
        derivedState.graphNavigableNodes
    }

    private var graphNavigableEdges: [StoryKnowledgeEdge] {
        derivedState.graphNavigableEdges
    }

    private var expandedGraphSelectionNavigation: StoryKnowledgeNeighborhoodGraphView.SelectionNavigation? {
        guard showingExpandedGraph else { return nil }

        if let selectedGraphNode,
           graphNavigableNodes.count > 1,
           let currentIndex = graphNavigableNodes.firstIndex(where: { $0.id == selectedGraphNode.id }) {
            let previousNode = graphNavigableNodes[wrappedIndex(from: currentIndex, step: -1, count: graphNavigableNodes.count)]
            let nextNode = graphNavigableNodes[wrappedIndex(from: currentIndex, step: 1, count: graphNavigableNodes.count)]
            return StoryKnowledgeNeighborhoodGraphView.SelectionNavigation(
                kind: .node,
                title: "Node \(currentIndex + 1) of \(graphNavigableNodes.count)",
                previousTarget: .init(id: previousNode.id, title: previousNode.name),
                nextTarget: .init(id: nextNode.id, title: nextNode.name),
                onPrevious: { cycleVisibleNodeSelection(step: -1) },
                onNext: { cycleVisibleNodeSelection(step: 1) }
            )
        }

        if let selectedGraphEdge,
           graphNavigableEdges.count > 1,
           let currentIndex = graphNavigableEdges.firstIndex(where: { $0.id == selectedGraphEdge.id }) {
            let previousEdge = graphNavigableEdges[wrappedIndex(from: currentIndex, step: -1, count: graphNavigableEdges.count)]
            let nextEdge = graphNavigableEdges[wrappedIndex(from: currentIndex, step: 1, count: graphNavigableEdges.count)]
            return StoryKnowledgeNeighborhoodGraphView.SelectionNavigation(
                kind: .edge,
                title: "Edge \(currentIndex + 1) of \(graphNavigableEdges.count)",
                previousTarget: .init(id: previousEdge.id, title: store.storyKnowledgeEdgeDisplayLabel(previousEdge)),
                nextTarget: .init(id: nextEdge.id, title: store.storyKnowledgeEdgeDisplayLabel(nextEdge)),
                onPrevious: { cycleVisibleEdgeSelection(step: -1) },
                onNext: { cycleVisibleEdgeSelection(step: 1) }
            )
        }

        return nil
    }

    private var selectedGraphEdgeConnectionSummary: GraphClusterConnectionSummary? {
        guard let selectedGraphEdge,
              let sourceKind = storyKnowledgeNodesByID[selectedGraphEdge.sourceNodeID]?.kind,
              let targetKind = storyKnowledgeNodesByID[selectedGraphEdge.targetNodeID]?.kind else {
            return nil
        }
        return derivedState.graphClusterConnectionSummaryLookup[
            graphClusterConnectionSummaryKey(sourceKind: sourceKind, targetKind: targetKind)
        ]
    }

    private var selectedGraphEdgeRelatedActions: [StoryKnowledgeNeighborhoodGraphView.SelectionAction] {
        guard let selectedGraphEdge else { return [] }

        let selectedRelationKey = normalizedRelationKey(selectedGraphEdge.relation)
        let samePairEdges = graphVisibleEdges.filter { edge in
            edge.id != selectedGraphEdge.id
                && edge.sourceNodeID == selectedGraphEdge.sourceNodeID
                && edge.targetNodeID == selectedGraphEdge.targetNodeID
        }

        let relationSourceEdges: [StoryKnowledgeEdge]
        if !samePairEdges.isEmpty {
            relationSourceEdges = samePairEdges
        } else if let connectionSummary = selectedGraphEdgeConnectionSummary {
            relationSourceEdges = graphVisibleEdges.filter { edge in
                guard let sourceKind = storyKnowledgeNodesByID[edge.sourceNodeID]?.kind,
                      let targetKind = storyKnowledgeNodesByID[edge.targetNodeID]?.kind else {
                    return false
                }
                return sourceKind == connectionSummary.sourceKind
                    && targetKind == connectionSummary.targetKind
                    && normalizedRelationKey(edge.relation) != selectedRelationKey
            }
        } else {
            relationSourceEdges = []
        }

        let grouped = Dictionary(grouping: relationSourceEdges) { normalizedRelationKey($0.relation) }

        return grouped.compactMap { _, relationEdges -> (relation: String, count: Int)? in
            guard let firstEdge = relationEdges.first else { return nil }
            return (firstEdge.relation, relationEdges.count)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.relation.localizedCaseInsensitiveCompare(rhs.relation) == .orderedAscending
        }
        .prefix(3)
        .map { relation, count in
            let displayLabel = relation.replacingOccurrences(of: "_", with: " ").capitalized
            if expandedGraphLayoutMode == .kindClusters,
               let connectionSummary = selectedGraphEdgeConnectionSummary {
                return StoryKnowledgeNeighborhoodGraphView.SelectionAction(
                    title: "Focus \(displayLabel) • \(count)",
                    action: { toggleExpandedRelationFocus(relation, within: connectionSummary) }
                )
            }

            return StoryKnowledgeNeighborhoodGraphView.SelectionAction(
                title: "Filter \(displayLabel) • \(count)",
                action: { toggleRelationFilter(relation) }
            )
        }
    }

    private var selectedGraphNodeRelatedActions: [StoryKnowledgeNeighborhoodGraphView.SelectionAction] {
        guard selectedGraphNode != nil else { return [] }

        let grouped = Dictionary(grouping: selectedGraphNodeIncidentEdges) { normalizedRelationKey($0.relation) }

        return grouped.compactMap { _, relationEdges -> (relation: String, count: Int)? in
            guard let firstEdge = relationEdges.first else { return nil }
            return (firstEdge.relation, relationEdges.count)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.relation.localizedCaseInsensitiveCompare(rhs.relation) == .orderedAscending
        }
        .prefix(3)
        .map { relation, count in
            let displayLabel = relation.replacingOccurrences(of: "_", with: " ").capitalized
            let title: String
            if isRelationFiltered(to: relation) {
                title = "Clear \(displayLabel) Filter"
            } else {
                title = "Filter \(displayLabel) • \(count)"
            }

            return StoryKnowledgeNeighborhoodGraphView.SelectionAction(
                title: title,
                action: { toggleRelationFilter(relation) }
            )
        }
    }

    private var selectedGraphNodeNeighborActions: [StoryKnowledgeNeighborhoodGraphView.SelectionAction] {
        guard let selectedGraphNode else { return [] }

        let grouped = Dictionary(grouping: selectedGraphNodeIncidentEdges) { edge -> UUID in
            edge.sourceNodeID == selectedGraphNode.id ? edge.targetNodeID : edge.sourceNodeID
        }

        return grouped.compactMap { neighborNodeID, edges -> (node: StoryKnowledgeNode, count: Int)? in
            guard let node = storyKnowledgeNodesByID[neighborNodeID] else { return nil }
            return (node, edges.count)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.node.name.localizedCaseInsensitiveCompare(rhs.node.name) == .orderedAscending
        }
        .prefix(3)
        .map { neighbor, count in
            StoryKnowledgeNeighborhoodGraphView.SelectionAction(
                title: "Jump to \(neighbor.name) • \(count)",
                action: {
                    graphSelectedEdgeID = nil
                    graphSelectedNodeID = neighbor.id
                }
            )
        }
    }

    private var expandedGraphSelectionOverlay: StoryKnowledgeNeighborhoodGraphView.SelectionOverlay? {
        guard showingExpandedGraph else { return nil }

        if let selectedGraphEdge {
            let diagnostics = store.storyKnowledgeObservedRelationDiagnostics(for: selectedGraphEdge)
            let evidenceItems = store.storyKnowledgeEvidenceItems(for: selectedGraphEdge)
            let evidencePreview = graphEvidencePreviewText(
                evidenceItems,
                maxItems: 3
            )
            let evidenceLinks = Array(evidenceItems.prefix(2)).map { item in
                StoryKnowledgeNeighborhoodGraphView.SelectionEvidenceLink(
                    title: "\(item.chapterTitle) / \(item.sceneTitle)",
                    action: { store.revealStoryKnowledgeEvidenceScene(item.sceneID) }
                )
            }
            let actionSections: [StoryKnowledgeNeighborhoodGraphView.SelectionActionSection] =
                selectedGraphEdgeRelatedActions.isEmpty
                ? []
                : [
                    StoryKnowledgeNeighborhoodGraphView.SelectionActionSection(
                        title: "Related Relations",
                        actions: selectedGraphEdgeRelatedActions
                    )
                ]
            var actions: [StoryKnowledgeNeighborhoodGraphView.SelectionAction] = [
                StoryKnowledgeNeighborhoodGraphView.SelectionAction(
                    title: isSidebarFocused(on: selectedGraphEdge) ? "Clear Pair Focus" : "Focus Pair",
                    action: { toggleSidebarFocus(for: selectedGraphEdge) }
                ),
                StoryKnowledgeNeighborhoodGraphView.SelectionAction(
                    title: isRelationFiltered(to: selectedGraphEdge.relation) ? "Clear Relation Filter" : "Filter Relation",
                    action: { toggleRelationFilter(selectedGraphEdge.relation) }
                )
            ]
            if selectedGraphEdge.status == .inferred {
                actions.append(
                    StoryKnowledgeNeighborhoodGraphView.SelectionAction(
                        title: "Accept",
                        action: {
                            selectedPendingEdgeIDs.remove(selectedGraphEdge.id)
                            store.acceptStoryKnowledgeEdge(selectedGraphEdge.id)
                        }
                    )
                )
                actions.append(
                    StoryKnowledgeNeighborhoodGraphView.SelectionAction(
                        title: "Reject",
                        action: {
                            selectedPendingEdgeIDs.remove(selectedGraphEdge.id)
                            store.rejectStoryKnowledgeEdge(selectedGraphEdge.id)
                        }
                    )
                )
            }

            return StoryKnowledgeNeighborhoodGraphView.SelectionOverlay(
                title: store.storyKnowledgeEdgeDisplayLabel(selectedGraphEdge),
                subtitle: selectedGraphEdge.status.rawValue.capitalized,
                badges: [
                    selectedGraphEdge.status.rawValue.capitalized,
                    confidenceLabel(selectedGraphEdge.confidence)
                ],
                detail: selectedGraphEdge.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Relation: \(selectedGraphEdge.relation.replacingOccurrences(of: "_", with: " ").capitalized)"
                    : selectedGraphEdge.note,
                secondaryLines: Array(diagnostics.map(\.message).prefix(2)),
                actionSections: actionSections,
                evidenceLinks: evidenceLinks,
                footnote: evidencePreview.isEmpty ? nil : evidencePreview,
                actions: actions,
                dismiss: { clearGraphSelection() }
            )
        }

        if let selectedGraphNode {
            let evidenceItems = store.storyKnowledgeEvidenceItems(for: selectedGraphNode)
            let evidencePreview = graphEvidencePreviewText(
                evidenceItems,
                maxItems: 3
            )
            let evidenceLinks = Array(evidenceItems.prefix(2)).map { item in
                StoryKnowledgeNeighborhoodGraphView.SelectionEvidenceLink(
                    title: "\(item.chapterTitle) / \(item.sceneTitle)",
                    action: { store.revealStoryKnowledgeEvidenceScene(item.sceneID) }
                )
            }

            var secondaryLines = Array(
                selectedGraphNodeIncidentEdges.prefix(3).map { edge in
                    "Visible: \(store.storyKnowledgeEdgeDisplayLabel(edge))"
                }
            )
            if secondaryLines.isEmpty {
                secondaryLines = ["Kind: \(selectedGraphNode.kind.rawValue.capitalized)"]
            }

            var actions: [StoryKnowledgeNeighborhoodGraphView.SelectionAction] = [
                StoryKnowledgeNeighborhoodGraphView.SelectionAction(
                    title: isSidebarFocused(on: selectedGraphNode) ? "Clear Focus" : "Focus",
                    action: { toggleSidebarFocus(for: selectedGraphNode) }
                ),
                StoryKnowledgeNeighborhoodGraphView.SelectionAction(
                    title: isKindFiltered(to: selectedGraphNode.kind) ? "Clear Kind Filter" : "Filter Kind",
                    action: { toggleKindFilter(for: selectedGraphNode.kind) }
                )
            ]

            if let compendiumID = selectedGraphNode.resolvedCompendiumID {
                actions.append(
                    StoryKnowledgeNeighborhoodGraphView.SelectionAction(
                        title: "Open Compendium",
                        action: { onOpenCompendiumEntry(compendiumID) }
                    )
                )
                actions.append(
                    StoryKnowledgeNeighborhoodGraphView.SelectionAction(
                        title: "Update Compendium",
                        action: {
                            compendiumMergePreview = store.storyKnowledgeCompendiumMergePreview(for: selectedGraphNode.id)
                        }
                    )
                )
            }

            if selectedGraphNode.status == .inferred {
                actions.append(
                    StoryKnowledgeNeighborhoodGraphView.SelectionAction(
                        title: "Promote to Compendium",
                        action: {
                            selectedPendingNodeIDs.remove(selectedGraphNode.id)
                            store.promoteStoryKnowledgeNodeToCompendium(selectedGraphNode.id)
                        }
                    )
                )
                actions.append(
                    StoryKnowledgeNeighborhoodGraphView.SelectionAction(
                        title: "Reject",
                        action: {
                            selectedPendingNodeIDs.remove(selectedGraphNode.id)
                            store.rejectStoryKnowledgeNode(selectedGraphNode.id)
                        }
                    )
                )
            }

            var actionSections: [StoryKnowledgeNeighborhoodGraphView.SelectionActionSection] = []
            if !selectedGraphNodeRelatedActions.isEmpty {
                actionSections.append(
                    StoryKnowledgeNeighborhoodGraphView.SelectionActionSection(
                        title: "Incident Relations",
                        actions: selectedGraphNodeRelatedActions
                    )
                )
            }
            if !selectedGraphNodeNeighborActions.isEmpty {
                actionSections.append(
                    StoryKnowledgeNeighborhoodGraphView.SelectionActionSection(
                        title: "Neighbor Nodes",
                        actions: selectedGraphNodeNeighborActions
                    )
                )
            }

            return StoryKnowledgeNeighborhoodGraphView.SelectionOverlay(
                title: selectedGraphNode.name,
                subtitle: selectedGraphNode.kind.rawValue.capitalized,
                badges: [
                    selectedGraphNode.kind.rawValue.capitalized,
                    selectedGraphNode.status.rawValue.capitalized,
                    confidenceLabel(selectedGraphNode.confidence)
                ],
                detail: selectedGraphNode.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Visible relations: \(selectedGraphNodeIncidentEdges.count)"
                    : selectedGraphNode.summary,
                secondaryLines: secondaryLines,
                actionSections: actionSections,
                evidenceLinks: evidenceLinks,
                footnote: evidencePreview.isEmpty ? nil : evidencePreview,
                actions: actions,
                dismiss: { clearGraphSelection() }
            )
        }

        return nil
    }

    private var graphNodeModels: [StoryKnowledgeNeighborhoodGraphView.NodeModel] {
        derivedState.graphNodeModels
    }

    private var graphEdgeModels: [StoryKnowledgeNeighborhoodGraphView.EdgeModel] {
        derivedState.graphEdgeModels
    }

    private var graphCoverageLabel: String {
        derivedState.graphCoverageLabel
    }

    private var graphClusterSummaries: [GraphClusterSummary] {
        derivedState.graphClusterSummaries
    }

    private var graphClusterConnectionSummaries: [GraphClusterConnectionSummary] {
        derivedState.graphClusterConnectionSummaries
    }

    private var activeFocusedGraphConnectionSummary: GraphClusterConnectionSummary? {
        guard let focus = activeExpandedGraphConnectionFocus else { return nil }
        return derivedState.graphClusterConnectionSummaryLookup[
            graphClusterConnectionSummaryKey(sourceKind: focus.sourceKind, targetKind: focus.targetKind)
        ]
    }

    private var activeFocusedGraphRelationSummary: GraphFocusedLinkRelationSummary? {
        guard let focus = activeExpandedGraphRelationFocus else { return nil }
        return derivedState.graphFocusedLinkRelationSummaryLookup[normalizedRelationKey(focus.relation)]
    }

    private var expandedGraphFocusHighlights: [StoryKnowledgeNeighborhoodGraphView.FocusHighlight] {
        var highlights: [StoryKnowledgeNeighborhoodGraphView.FocusHighlight] = []

        if let activeExpandedGraphConnectionFocus {
            highlights.append(
                StoryKnowledgeNeighborhoodGraphView.FocusHighlight(
                    label: activeExpandedGraphConnectionFocus.label,
                    systemImage: "point.3.filled.connected.trianglepath.dotted",
                    badges: graphFocusCoverageBadges(
                        edgeCount: activeFocusedGraphConnectionSummary?.edgeCount ?? 0,
                        pairCount: activeFocusedGraphConnectionSummary?.pairCount,
                        pendingEdgeCount: activeFocusedGraphConnectionSummary?.pendingEdgeCount ?? 0,
                        evidenceItems: activeFocusedGraphConnectionSummary?.evidenceItems ?? []
                    ),
                    actionTitle: "Clear Link",
                    action: {
                        expandedGraphConnectionFocus = nil
                        expandedGraphRelationFocus = nil
                    }
                )
            )
        }

        if let activeExpandedGraphRelationFocus {
            highlights.append(
                StoryKnowledgeNeighborhoodGraphView.FocusHighlight(
                    label: activeExpandedGraphRelationFocus.label,
                    systemImage: "line.3.horizontal.decrease.circle",
                    badges: graphFocusCoverageBadges(
                        edgeCount: activeFocusedGraphRelationSummary?.edgeCount ?? 0,
                        pairCount: activeFocusedGraphRelationSummary?.pairCount,
                        pendingEdgeCount: activeFocusedGraphRelationSummary?.pendingEdgeCount ?? 0,
                        evidenceItems: activeFocusedGraphRelationSummary?.evidenceItems ?? []
                    ),
                    actionTitle: "Clear Relation",
                    action: {
                        expandedGraphRelationFocus = nil
                    }
                )
            )
        }

        return highlights
    }

    private var expandedGraphEmptyState: StoryKnowledgeNeighborhoodGraphView.EmptyState? {
        guard showingExpandedGraph, graphVisibleNodes.isEmpty else { return nil }

        let searchText = store.storyKnowledgePanelState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchText.isEmpty, !graphBaseEdgesIgnoringSearch.isEmpty {
            if let relationFocus = activeExpandedGraphRelationFocus {
                return StoryKnowledgeNeighborhoodGraphView.EmptyState(
                    title: "Focused Relation Hidden by Search",
                    systemImage: "magnifyingglass",
                    description: "\(relationFocus.label) still has edges in the active grouped scope, but the current search for \"\(searchText)\" filters them out. Clear the search to render that relation again.",
                    actionTitle: "Clear Search",
                    action: { store.setStoryKnowledgePanelSearchText("") }
                )
            }

            if let connectionFocus = activeExpandedGraphConnectionFocus {
                return StoryKnowledgeNeighborhoodGraphView.EmptyState(
                    title: "Focused Link Hidden by Search",
                    systemImage: "magnifyingglass",
                    description: "\(connectionFocus.label) still has edges in the active grouped scope, but the current search for \"\(searchText)\" filters them out. Clear the search to bring that grouped link back into view.",
                    actionTitle: "Clear Search",
                    action: { store.setStoryKnowledgePanelSearchText("") }
                )
            }
        }

        if let relationFocus = activeExpandedGraphRelationFocus {
            switch visibilityFilter {
            case .accepted where graphBaseAcceptedEdges.isEmpty && !graphBasePendingEdges.isEmpty:
                return StoryKnowledgeNeighborhoodGraphView.EmptyState(
                    title: "Focused Relation Hidden by Visibility",
                    systemImage: "eye.slash",
                    description: "\(relationFocus.label) currently only has pending edges in the active grouped scope. Show accepted and pending edges together to render it again.",
                    actionTitle: "Show All",
                    action: { store.setStoryKnowledgePanelVisibilityFilter(.all) }
                )
            case .pending where !graphBaseAcceptedEdges.isEmpty && graphBasePendingEdges.isEmpty:
                return StoryKnowledgeNeighborhoodGraphView.EmptyState(
                    title: "Focused Relation Hidden by Visibility",
                    systemImage: "eye.slash",
                    description: "\(relationFocus.label) currently only has accepted edges in the active grouped scope. Show accepted and pending edges together to render it again.",
                    actionTitle: "Show All",
                    action: { store.setStoryKnowledgePanelVisibilityFilter(.all) }
                )
            default:
                if !graphConnectionVisibleEdges.isEmpty {
                    return StoryKnowledgeNeighborhoodGraphView.EmptyState(
                        title: "Focused Relation Not Visible in Current Link",
                        systemImage: "arrow.uturn.backward.circle",
                        description: "\(relationFocus.label) has no visible edges right now, but the parent grouped link still has \(graphConnectionVisibleEdges.count) visible edge" + (graphConnectionVisibleEdges.count == 1 ? "" : "s") + ". Return to the parent link scope to keep exploring that connection.",
                        actionTitle: "Back to Link",
                        action: { expandedGraphRelationFocus = nil }
                    )
                }

                return StoryKnowledgeNeighborhoodGraphView.EmptyState(
                    title: "No Visible Edges in Focused Relation",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: "\(relationFocus.label) has no visible edges under the current grouped canvas filters. Clear the local relation focus or broaden the current graph filters.",
                    actionTitle: "Clear Relation",
                    action: { expandedGraphRelationFocus = nil }
                )
            }
        }

        return nil
    }

    private var graphFocusedLinkRelationSummaries: [GraphFocusedLinkRelationSummary] {
        derivedState.graphFocusedLinkRelationSummaries
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

                    if !collapsedRelationSummaries.isEmpty {
                        collapsedRelationSection
                    }

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
        .sheet(isPresented: $showingExpandedGraph) {
            expandedGraphSheet
        }
        .onChange(of: graphVisibleNodes.map(\.id), initial: false) { _, visibleNodeIDs in
            guard let graphSelectedNodeID else { return }
            if !visibleNodeIDs.contains(graphSelectedNodeID) {
                self.graphSelectedNodeID = visibleNodeIDs.first
            }
        }
        .onChange(of: graphVisibleEdges.map(\.id), initial: false) { _, visibleEdgeIDs in
            guard let graphSelectedEdgeID else { return }
            if !visibleEdgeIDs.contains(graphSelectedEdgeID) {
                self.graphSelectedEdgeID = nil
            }
        }
        .onChange(of: expandedGraphLayoutMode, initial: false) { _, newLayoutMode in
            if newLayoutMode != .kindClusters {
                expandedGraphConnectionFocus = nil
                expandedGraphRelationFocus = nil
                expandedGraphCollapsedKinds = []
                expandedGraphIsolatedKinds = []
            }
        }
        .onChange(of: graphBaseEdges.map(\.id), initial: false) { _, _ in
            guard let focus = expandedGraphConnectionFocus else { return }
            if !hasGraphEdges(for: focus) {
                expandedGraphConnectionFocus = nil
            }
        }
        .onChange(of: graphConnectionFocusedAcceptedEdges.map(\.id) + graphConnectionFocusedPendingEdges.map(\.id), initial: false) { _, _ in
            guard let focus = expandedGraphRelationFocus else { return }
            if !hasGraphEdges(forRelation: focus.relation) {
                expandedGraphRelationFocus = nil
            }
        }
        .onChange(of: graphCandidateNodes.map(\.kind), initial: false) { _, _ in
            let availableKinds = Set(graphCandidateNodes.map(\.kind))
            expandedGraphCollapsedKinds = expandedGraphCollapsedKinds.intersection(availableKinds)
            expandedGraphIsolatedKinds = expandedGraphIsolatedKinds.intersection(availableKinds)
        }
        .onChange(of: derivedStateKey, initial: true) { _, _ in
            refreshDerivedState()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Knowledge Graph")
                    .font(.headline)

                Spacer(minLength: 0)

                Button() {
                    showingExpandedGraph = true
                } label: {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                }
                .help("Open canvas.")
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(graphVisibleNodes.isEmpty)
            }

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

            if !collapsedRelationSummaries.isEmpty {
                Text("\(collapsedRelationEdgeCount) edges collapsed from \(collapsedRelationAliasCount) alternate relation labels")
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

            if let conflictFocus {
                HStack(spacing: 8) {
                    Label(conflictFocus.label, systemImage: "scope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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

    private var expandedGraphSheet: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Knowledge Graph Canvas")
                        .font(.title3.weight(.semibold))

                    Text(graphCoverageLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let activeExpandedGraphConnectionFocus {
                        graphFocusScopeLine(
                            label: activeExpandedGraphConnectionFocus.label,
                            systemImage: "point.3.filled.connected.trianglepath.dotted",
                            badges: graphFocusCoverageBadges(
                                edgeCount: activeFocusedGraphConnectionSummary?.edgeCount ?? 0,
                                pairCount: activeFocusedGraphConnectionSummary?.pairCount,
                                pendingEdgeCount: activeFocusedGraphConnectionSummary?.pendingEdgeCount ?? 0,
                                evidenceItems: activeFocusedGraphConnectionSummary?.evidenceItems ?? []
                            )
                        )
                    }

                    if let activeExpandedGraphRelationFocus {
                        graphFocusScopeLine(
                            label: activeExpandedGraphRelationFocus.label,
                            systemImage: "line.3.horizontal.decrease.circle",
                            badges: graphFocusCoverageBadges(
                                edgeCount: activeFocusedGraphRelationSummary?.edgeCount ?? 0,
                                pairCount: activeFocusedGraphRelationSummary?.pairCount,
                                pendingEdgeCount: activeFocusedGraphRelationSummary?.pendingEdgeCount ?? 0,
                                evidenceItems: activeFocusedGraphRelationSummary?.evidenceItems ?? []
                            )
                        )
                    }

                    if !activeExpandedGraphIsolatedKinds.isEmpty {
                        graphFocusScopeLine(
                            label: isolatedClusterScopeLabel,
                            systemImage: "scope",
                            badges: ["\(activeExpandedGraphIsolatedKinds.count) local"]
                        )
                    }

                    if !activeExpandedGraphCollapsedKinds.isEmpty {
                        graphFocusScopeLine(
                            label: "Collapsed clusters: \(activeExpandedGraphCollapsedKinds.map(\.rawValue.capitalized).sorted().joined(separator: ", "))",
                            systemImage: "eye.slash",
                            badges: ["\(activeExpandedGraphCollapsedKinds.count) hidden"]
                        )
                    }
                }

                Spacer(minLength: 0)

                Picker("Canvas Density", selection: $expandedGraphDensity) {
                    ForEach(GraphDensityMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Picker("Layout", selection: $expandedGraphLayoutMode) {
                    ForEach(StoryKnowledgeNeighborhoodGraphView.LayoutMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                if conflictFocus != nil {
                    Button("Clear Focus") {
                        conflictFocus = nil
                    }
                    .buttonStyle(.borderless)
                    .help("Clear the current focus filter")
                }

                if hasGraphSelection {
                    Button("Clear Selection") {
                        clearGraphSelection()
                    }
                    .buttonStyle(.borderless)
                }

                if activeExpandedGraphConnectionFocus != nil {
                    Button("Clear Link Focus") {
                        expandedGraphConnectionFocus = nil
                    }
                    .buttonStyle(.borderless)
                }

                if activeExpandedGraphRelationFocus != nil {
                    Button("Clear Relation Focus") {
                        expandedGraphRelationFocus = nil
                    }
                    .buttonStyle(.borderless)
                }

                if hasExpandedGraphClusterCanvasScope {
                    Button("Clear Cluster Scope") {
                        clearExpandedClusterCanvasScope()
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(16)

            Divider()

            HStack(spacing: 0) {
                StoryKnowledgeNeighborhoodGraphView(
                    nodes: graphNodeModels,
                    edges: graphEdgeModels,
                    preferredAnchorNodeIDs: graphPreferredAnchorNodeIDs,
                    layoutMode: expandedGraphLayoutMode,
                    labelDensity: expandedGraphLabelDensity,
                    focusHighlights: expandedGraphFocusHighlights,
                    emptyState: expandedGraphEmptyState,
                    selectionNavigation: expandedGraphSelectionNavigation,
                    selectionOverlay: nil,
                    selectedClusterKind: expandedGraphLayoutMode == .kindClusters ? nodeKindFilter.nodeKind : nil,
                    focusedClusterLink: activeExpandedGraphConnectionFocus.map {
                        StoryKnowledgeNeighborhoodGraphView.FocusedClusterLink(
                            sourceKind: $0.sourceKind,
                            targetKind: $0.targetKind
                        )
                    },
                    focusedRelation: expandedGraphLayoutMode == .kindClusters ? activeExpandedGraphRelationFocus?.relation : nil,
                    onSelectClusterKind: expandedGraphLayoutMode == .kindClusters ? { kind in
                        toggleKindFilter(for: kind)
                    } : nil,
                    fillsAvailableHeight: true,
                    selectedNodeID: $graphSelectedNodeID,
                    selectedEdgeID: $graphSelectedEdgeID
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Inspector")
                            .font(.headline)

                        if hasGraphSelection {
                            graphSelectionInspector
                        } else {
                            Text("Select a node or edge to inspect it here. The expanded canvas shares the same filters, focus, and selection model as the sidebar graph.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if expandedGraphLayoutMode == .kindClusters {
                                Text("Click a cluster label in the canvas to toggle that node-kind filter.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Current Graph Scope")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text(graphCoverageLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(matchCountLabel())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                if let conflictFocus {
                                    Label(conflictFocus.label, systemImage: "scope")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let activeExpandedGraphConnectionFocus {
                                    graphFocusScopeLine(
                                        label: activeExpandedGraphConnectionFocus.label,
                                        systemImage: "point.3.filled.connected.trianglepath.dotted",
                                        badges: graphFocusCoverageBadges(
                                            edgeCount: activeFocusedGraphConnectionSummary?.edgeCount ?? 0,
                                            pairCount: activeFocusedGraphConnectionSummary?.pairCount,
                                            pendingEdgeCount: activeFocusedGraphConnectionSummary?.pendingEdgeCount ?? 0,
                                            evidenceItems: activeFocusedGraphConnectionSummary?.evidenceItems ?? []
                                        )
                                    )
                                }

                                if let activeExpandedGraphRelationFocus {
                                    graphFocusScopeLine(
                                        label: activeExpandedGraphRelationFocus.label,
                                        systemImage: "line.3.horizontal.decrease.circle",
                                        badges: graphFocusCoverageBadges(
                                            edgeCount: activeFocusedGraphRelationSummary?.edgeCount ?? 0,
                                            pairCount: activeFocusedGraphRelationSummary?.pairCount,
                                            pendingEdgeCount: activeFocusedGraphRelationSummary?.pendingEdgeCount ?? 0,
                                            evidenceItems: activeFocusedGraphRelationSummary?.evidenceItems ?? []
                                        )
                                    )
                                }

                                if !activeExpandedGraphIsolatedKinds.isEmpty {
                                    graphFocusScopeLine(
                                        label: isolatedClusterScopeLabel,
                                        systemImage: "scope",
                                        badges: ["\(activeExpandedGraphIsolatedKinds.count) local"]
                                    )
                                }

                                if !activeExpandedGraphCollapsedKinds.isEmpty {
                                    graphFocusScopeLine(
                                        label: "Collapsed clusters: \(activeExpandedGraphCollapsedKinds.map(\.rawValue.capitalized).sorted().joined(separator: ", "))",
                                        systemImage: "eye.slash",
                                        badges: ["\(activeExpandedGraphCollapsedKinds.count) hidden"]
                                    )
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            if expandedGraphLayoutMode == .kindClusters,
                               (!graphClusterSummaries.isEmpty
                                || !activeExpandedGraphCollapsedKinds.isEmpty
                                || !activeExpandedGraphIsolatedKinds.isEmpty) {
                                if !activeExpandedGraphIsolatedKinds.isEmpty {
                                    isolatedClusterSection
                                }

                                if !activeExpandedGraphCollapsedKinds.isEmpty {
                                    collapsedClusterSection
                                }

                                if !graphClusterSummaries.isEmpty {
                                    graphClusterSummarySection
                                }

                                if activeExpandedGraphConnectionFocus != nil, !graphFocusedLinkRelationSummaries.isEmpty {
                                    graphFocusedLinkRelationSection
                                }

                                if !graphClusterConnectionSummaries.isEmpty {
                                    graphClusterConnectionSection
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(width: 320)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 1100, minHeight: 760)
    }

    @ViewBuilder
    private var graphSelectionInspector: some View {
        if let selectionOverlay = expandedGraphSelectionOverlay {
            graphSelectionInspectorCard(selectionOverlay)
        }
    }

    private func graphSelectionInspectorCard(
        _ overlay: StoryKnowledgeNeighborhoodGraphView.SelectionOverlay
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(overlay.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .textSelection(.enabled)

                    if let subtitle = overlay.subtitle,
                       !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 0)

                if let dismiss = overlay.dismiss {
                    Button("Clear Selection", action: dismiss)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }

            if !overlay.badges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(overlay.badges, id: \.self) { badge in
                        statusBadge(badge)
                    }
                }
            }

            Text(overlay.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if !overlay.secondaryLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(overlay.secondaryLines, id: \.self) { line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

            if !overlay.actionSections.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(overlay.actionSections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(section.actions) { action in
                                Button(action.title, action: action.action)
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }

            if !overlay.evidenceLinks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Evidence")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(overlay.evidenceLinks) { link in
                        Button(link.title, action: link.action)
                            .buttonStyle(.link)
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if let footnote = overlay.footnote,
               !footnote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if !overlay.actions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(overlay.actions) { action in
                        Button(action.title, action: action.action)
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var graphClusterSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visible Clusters")
                .font(.headline)

            Text("Summarizes the currently rendered grouped canvas by node kind. Use these cards to filter, collapse, or isolate one or more local clusters when needed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(graphClusterSummaries) { summary in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(summary.kind.rawValue.capitalized)
                            .font(.subheadline.weight(.semibold))

                        statusBadge("\(summary.nodeCount) node" + (summary.nodeCount == 1 ? "" : "s"))

                        if summary.pendingNodeCount > 0 {
                            statusBadge("\(summary.pendingNodeCount) pending")
                        }

                        Spacer(minLength: 0)

                        Button(isKindFiltered(to: summary.kind) ? "Clear Kind Filter" : "Filter Kind") {
                            toggleKindFilter(for: summary.kind)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                        Button(clusterIsolationActionTitle(for: summary.kind)) {
                            toggleExpandedClusterIsolation(summary.kind)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                        Button(isExpandedClusterCollapsed(summary.kind) ? "Show Cluster" : "Collapse") {
                            toggleExpandedClusterCollapse(summary.kind)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }

                    Text("\(summary.canonicalNodeCount) canonical • \(summary.incidentEdgeCount) visible relations • \(summary.crossKindEdgeCount) cross-cluster")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !summary.topRelations.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Top relations")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(summary.topRelations) { relation in
                                Text("\(relation.relation) • \(relation.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var isolatedClusterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Isolated Clusters")
                .font(.headline)

            Text("These clusters stay emphasized only in the expanded grouped canvas. Add or clear isolated kinds here without changing the global graph filters.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(activeExpandedGraphIsolatedKinds).sorted { $0.rawValue < $1.rawValue }, id: \.rawValue) { kind in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(kind.rawValue.capitalized)
                        .font(.subheadline.weight(.semibold))

                    statusBadge("local")

                    Spacer(minLength: 0)

                    Button("Clear Isolate") {
                        toggleExpandedClusterIsolation(kind)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var collapsedClusterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Collapsed Clusters")
                .font(.headline)

            Text("Clusters hidden only in the expanded grouped canvas. Restore them here without changing the global graph filters.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(activeExpandedGraphCollapsedKinds).sorted { $0.rawValue < $1.rawValue }, id: \.rawValue) { kind in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(kind.rawValue.capitalized)
                        .font(.subheadline.weight(.semibold))

                    statusBadge("hidden")

                    Spacer(minLength: 0)

                    Button("Show Cluster") {
                        toggleExpandedClusterCollapse(kind)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var graphClusterConnectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cluster Connections")
                .font(.headline)

            Text("Summarizes visible cross-cluster edges in the grouped canvas so you can see which kinds are interacting most strongly.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(graphClusterConnectionSummaries.prefix(8)) { summary in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(summary.title)
                            .font(.subheadline.weight(.semibold))

                        statusBadge("\(summary.edgeCount) edge" + (summary.edgeCount == 1 ? "" : "s"))
                        statusBadge("\(summary.pairCount) pair" + (summary.pairCount == 1 ? "" : "s"))

                        if summary.pendingEdgeCount > 0 {
                            statusBadge("\(summary.pendingEdgeCount) pending")
                        }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        Button(isKindFiltered(to: summary.sourceKind) ? "Clear \(summary.sourceKind.rawValue.capitalized) Filter" : "Filter \(summary.sourceKind.rawValue.capitalized)") {
                            toggleKindFilter(for: summary.sourceKind)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                        Button(isKindFiltered(to: summary.targetKind) ? "Clear \(summary.targetKind.rawValue.capitalized) Filter" : "Filter \(summary.targetKind.rawValue.capitalized)") {
                            toggleKindFilter(for: summary.targetKind)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                        Button(isExpandedConnectionFocused(on: summary) ? "Clear Link Focus" : "Focus Link") {
                            toggleExpandedConnectionFocus(summary)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                        Spacer(minLength: 0)
                    }

                    if !summary.topRelations.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dominant relations")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(summary.topRelations) { relation in
                                HStack(spacing: 8) {
                                    Text("\(relation.displayLabel) • \(relation.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)

                                    Spacer(minLength: 0)

                                    Button(isExpandedRelationFocused(on: relation.relation, within: summary) ? "Clear Relation Focus" : "Focus Relation") {
                                        toggleExpandedRelationFocus(relation.relation, within: summary)
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)

                                    Button(isRelationFiltered(to: relation.relation) ? "Clear Relation Filter" : "Filter Relation") {
                                        toggleRelationFilter(relation.relation)
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }

                    if !summary.evidenceItems.isEmpty {
                        evidenceSection(
                            items: summary.evidenceItems,
                            onRevealScene: { store.revealStoryKnowledgeEvidenceScene($0) }
                        )
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var graphFocusedLinkRelationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Focused Link Relations")
                .font(.headline)

            Text("Breaks the active kind-to-kind link into relation families so you can inspect which relation is driving that connection.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(graphFocusedLinkRelationSummaries) { summary in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(summary.displayLabel)
                            .font(.subheadline.weight(.semibold))

                        statusBadge("\(summary.edgeCount) edge" + (summary.edgeCount == 1 ? "" : "s"))
                        statusBadge("\(summary.pairCount) pair" + (summary.pairCount == 1 ? "" : "s"))

                        if summary.pendingEdgeCount > 0 {
                            statusBadge("\(summary.pendingEdgeCount) pending")
                        }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        Button(isExpandedRelationFocused(on: summary.relation, within: activeFocusedGraphConnectionSummary) ? "Clear Relation Focus" : "Focus Relation") {
                            toggleExpandedRelationFocus(summary.relation, within: activeFocusedGraphConnectionSummary)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                        Button(isRelationFiltered(to: summary.relation) ? "Clear Relation Filter" : "Filter Relation") {
                            toggleRelationFilter(summary.relation)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                        Spacer(minLength: 0)
                    }

                    if !summary.pairLabels.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Visible pairs")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(summary.pairLabels, id: \.self) { label in
                                Text(label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    if !summary.evidenceItems.isEmpty {
                        evidenceSection(
                            items: summary.evidenceItems,
                            onRevealScene: { store.revealStoryKnowledgeEvidenceScene($0) }
                        )
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var collapsedRelationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collapsed Relations")
                .font(.headline)

            Text("Canonical relations that absorbed alternate extracted labels in the current view.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(collapsedRelationSummaries.prefix(6))) { summary in
                let diagnostics = store.storyKnowledgeObservedRelationDiagnostics(
                    canonicalRelation: summary.relation,
                    observedRelations: summary.observedRelations
                )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(summary.relation.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.subheadline.weight(.semibold))
                        statusBadge("\(summary.edgeCount) edge" + (summary.edgeCount == 1 ? "" : "s"))
                        if summary.pendingEdgeCount > 0 {
                            statusBadge("\(summary.pendingEdgeCount) pending")
                        }
                        Spacer(minLength: 0)

                        Button(isCollapsedRelationSelected(summary.relation) ? "Clear Filter" : "Filter") {
                            toggleCollapsedRelationFilter(summary.relation)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }

                    ForEach(diagnostics) { diagnostic in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(diagnostic.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            if !diagnostic.evidenceItems.isEmpty {
                                evidenceSection(
                                    items: diagnostic.evidenceItems,
                                    onRevealScene: { store.revealStoryKnowledgeEvidenceScene($0) }
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if collapsedRelationSummaries.count > 6 {
                Text("+\(collapsedRelationSummaries.count - 6) more canonical relation families")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                    onResolveNodeToCompendium: { nodeID, compendiumID in
                        selectedPendingNodeIDs.remove(nodeID)
                        store.resolveStoryKnowledgeNodeToCompendium(nodeID, compendiumID: compendiumID)
                    },
                    onReviewCompendiumMerge: { nodeID in
                        compendiumMergePreview = store.storyKnowledgeCompendiumMergePreview(for: nodeID)
                    },
                    onFocus: { focus(on: item) },
                    onRejectNode: { nodeID in
                        selectedPendingNodeIDs.remove(nodeID)
                        store.rejectStoryKnowledgeNode(nodeID)
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
                        observedRelationDiagnostics: store.storyKnowledgeObservedRelationDiagnostics(for: edge),
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
                        observedRelationDiagnostics: store.storyKnowledgeObservedRelationDiagnostics(for: edge),
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

    private func refreshDerivedState() {
        let storyKnowledgeNodesByID = Dictionary(
            uniqueKeysWithValues: mergedStoryKnowledgeNodes.map { ($0.id, $0) }
        )
        let filteredAcceptedNodes = sort(nodes: acceptedNodes.filter {
            matchesFocus(node: $0) && matchesNodeKind(node: $0) && matchesSearch(node: $0)
        })
        let filteredConflictItems = store.storyKnowledgeConflictItems.filter {
            matchesFocus(conflict: $0) && matchesConflict($0)
        }
        let filteredAcceptedEdges = sort(edges: acceptedEdges.filter {
            matchesFocus(edge: $0) && matchesNodeKind(edge: $0) && matchesRelation(edge: $0) && matchesSearch(edge: $0)
        })
        let filteredPendingNodes = sort(nodes: deduplicatedPendingNodes.filter {
            matchesFocus(node: $0) && matchesNodeKind(node: $0) && matchesSearch(node: $0)
        })
        let filteredPendingEdges = sort(edges: deduplicatedPendingEdges.filter {
            matchesFocus(edge: $0) && matchesNodeKind(edge: $0) && matchesRelation(edge: $0) && matchesSearch(edge: $0)
        })
        let filteredAcceptedEdgesIgnoringSearch = sort(edges: acceptedEdges.filter {
            matchesFocus(edge: $0) && matchesNodeKind(edge: $0) && matchesRelation(edge: $0)
        })
        let filteredPendingEdgesIgnoringSearch = sort(edges: deduplicatedPendingEdges.filter {
            matchesFocus(edge: $0) && matchesNodeKind(edge: $0) && matchesRelation(edge: $0)
        })

        let visibleDiagnosticEdges: [StoryKnowledgeEdge] = {
            let accepted = visibilityFilter == .pending ? [] : filteredAcceptedEdges
            let pending = visibilityFilter == .accepted ? [] : filteredPendingEdges
            return accepted + pending
        }()
        let collapsedRelationSummaries = buildCollapsedRelationSummaries(from: visibleDiagnosticEdges)

        let graphCandidateNodes: [StoryKnowledgeNode] = {
            switch visibilityFilter {
            case .pending:
                return filteredPendingNodes
            case .accepted:
                return filteredAcceptedNodes
            case .all:
                return deduplicatedStoryKnowledgeNodes(filteredAcceptedNodes + filteredPendingNodes)
            }
        }()

        let clusterScopedAcceptedEdges = applyExpandedClusterCanvasScope(to: filteredAcceptedEdges)
        let clusterScopedPendingEdges = applyExpandedClusterCanvasScope(to: filteredPendingEdges)
        let clusterScopedAcceptedEdgesIgnoringSearch = applyExpandedClusterCanvasScope(to: filteredAcceptedEdgesIgnoringSearch)
        let clusterScopedPendingEdgesIgnoringSearch = applyExpandedClusterCanvasScope(to: filteredPendingEdgesIgnoringSearch)
        let connectionFocusedAcceptedEdges = applyExpandedConnectionFocus(to: clusterScopedAcceptedEdges)
        let connectionFocusedPendingEdges = applyExpandedConnectionFocus(to: clusterScopedPendingEdges)
        let connectionFocusedAcceptedEdgesIgnoringSearch = applyExpandedConnectionFocus(to: clusterScopedAcceptedEdgesIgnoringSearch)
        let connectionFocusedPendingEdgesIgnoringSearch = applyExpandedConnectionFocus(to: clusterScopedPendingEdgesIgnoringSearch)
        let baseAcceptedEdges = applyExpandedRelationFocus(to: connectionFocusedAcceptedEdges)
        let basePendingEdges = applyExpandedRelationFocus(to: connectionFocusedPendingEdges)
        let baseAcceptedEdgesIgnoringSearch = applyExpandedRelationFocus(to: connectionFocusedAcceptedEdgesIgnoringSearch)
        let basePendingEdgesIgnoringSearch = applyExpandedRelationFocus(to: connectionFocusedPendingEdgesIgnoringSearch)
        let connectionVisibleEdges: [StoryKnowledgeEdge] = {
            let accepted = visibilityFilter == .pending ? [] : connectionFocusedAcceptedEdges
            let pending = visibilityFilter == .accepted ? [] : connectionFocusedPendingEdges
            return accepted + pending
        }()
        let baseEdges: [StoryKnowledgeEdge] = {
            let accepted = visibilityFilter == .pending ? [] : baseAcceptedEdges
            let pending = visibilityFilter == .accepted ? [] : basePendingEdges
            return accepted + pending
        }()
        let baseEdgesIgnoringSearch: [StoryKnowledgeEdge] = {
            let accepted = visibilityFilter == .pending ? [] : baseAcceptedEdgesIgnoringSearch
            let pending = visibilityFilter == .accepted ? [] : basePendingEdgesIgnoringSearch
            return accepted + pending
        }()
        let baseNodes: [StoryKnowledgeNode] = {
            if activeExpandedGraphConnectionFocus != nil || activeExpandedGraphRelationFocus != nil || hasExpandedGraphClusterCanvasScope {
                let nodeIDs = Set(baseEdges.flatMap { [$0.sourceNodeID, $0.targetNodeID] })
                return graphCandidateNodes.filter { nodeIDs.contains($0.id) }
            }
            return graphCandidateNodes
        }()

        let graphVisibleEdges = buildGraphVisibleEdges(
            mode: activeGraphDensityMode,
            baseAcceptedEdges: baseAcceptedEdges,
            basePendingEdges: basePendingEdges
        )
        let graphVisibleNodes = buildGraphVisibleNodes(
            mode: activeGraphDensityMode,
            edges: graphVisibleEdges,
            baseNodes: baseNodes
        )
        let graphVisibleNodesByID = Dictionary(uniqueKeysWithValues: graphVisibleNodes.map { ($0.id, $0) })
        let graphVisibleEdgesByID = Dictionary(uniqueKeysWithValues: graphVisibleEdges.map { ($0.id, $0) })
        let graphIncidentEdgesByNodeID = buildGraphIncidentEdgesByNodeID(from: graphVisibleEdges)
        let graphNavigableNodes = graphVisibleNodes.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        let graphNavigableEdges = sort(edges: graphVisibleEdges)
        let graphNodeModels = buildGraphNodeModels(from: graphVisibleNodes)
        let graphEdgeModels = buildGraphEdgeModels(from: graphVisibleEdges)
        let graphCoverageLabel = buildGraphCoverageLabel(
            visibleNodes: graphVisibleNodes,
            visibleEdges: graphVisibleEdges,
            totalNodes: baseNodes,
            totalEdges: baseEdges
        )
        let graphClusterSummaries = buildGraphClusterSummaries(
            visibleNodes: graphVisibleNodes,
            visibleEdges: graphVisibleEdges
        )
        let graphClusterConnectionSummaries = buildGraphClusterConnectionSummaries(
            visibleEdges: graphVisibleEdges
        )
        let graphClusterConnectionSummaryLookup = Dictionary(
            uniqueKeysWithValues: graphClusterConnectionSummaries.map {
                (graphClusterConnectionSummaryKey(sourceKind: $0.sourceKind, targetKind: $0.targetKind), $0)
            }
        )
        let graphFocusedLinkRelationSummaries = buildGraphFocusedLinkRelationSummaries(
            connectionFocusedAcceptedEdges: connectionFocusedAcceptedEdges,
            connectionFocusedPendingEdges: connectionFocusedPendingEdges
        )
        let graphFocusedLinkRelationSummaryLookup = Dictionary(
            uniqueKeysWithValues: graphFocusedLinkRelationSummaries.map {
                (normalizedRelationKey($0.relation), $0)
            }
        )

        derivedState = PanelDerivedState(
            storyKnowledgeNodesByID: storyKnowledgeNodesByID,
            filteredAcceptedNodes: filteredAcceptedNodes,
            filteredConflictItems: filteredConflictItems,
            filteredAcceptedEdges: filteredAcceptedEdges,
            filteredPendingNodes: filteredPendingNodes,
            filteredPendingEdges: filteredPendingEdges,
            filteredAcceptedEdgesIgnoringSearch: filteredAcceptedEdgesIgnoringSearch,
            filteredPendingEdgesIgnoringSearch: filteredPendingEdgesIgnoringSearch,
            collapsedRelationSummaries: collapsedRelationSummaries,
            graphConnectionFocusedAcceptedEdges: connectionFocusedAcceptedEdges,
            graphConnectionFocusedPendingEdges: connectionFocusedPendingEdges,
            graphConnectionVisibleEdges: connectionVisibleEdges,
            graphBaseAcceptedEdges: baseAcceptedEdges,
            graphBasePendingEdges: basePendingEdges,
            graphBaseAcceptedEdgesIgnoringSearch: baseAcceptedEdgesIgnoringSearch,
            graphBasePendingEdgesIgnoringSearch: basePendingEdgesIgnoringSearch,
            graphBaseEdgesIgnoringSearch: baseEdgesIgnoringSearch,
            graphVisibleEdges: graphVisibleEdges,
            graphVisibleNodes: graphVisibleNodes,
            graphVisibleNodesByID: graphVisibleNodesByID,
            graphVisibleEdgesByID: graphVisibleEdgesByID,
            graphIncidentEdgesByNodeID: graphIncidentEdgesByNodeID,
            graphNavigableNodes: graphNavigableNodes,
            graphNavigableEdges: graphNavigableEdges,
            graphNodeModels: graphNodeModels,
            graphEdgeModels: graphEdgeModels,
            graphCoverageLabel: graphCoverageLabel,
            graphClusterSummaries: graphClusterSummaries,
            graphClusterConnectionSummaries: graphClusterConnectionSummaries,
            graphClusterConnectionSummaryLookup: graphClusterConnectionSummaryLookup,
            graphFocusedLinkRelationSummaries: graphFocusedLinkRelationSummaries,
            graphFocusedLinkRelationSummaryLookup: graphFocusedLinkRelationSummaryLookup
        )
    }

    private func buildCollapsedRelationSummaries(from edges: [StoryKnowledgeEdge]) -> [CollapsedRelationSummary] {
        let groupedEdges = Dictionary(grouping: edges.filter { !$0.observedRelations.isEmpty }) { $0.relation }
        return groupedEdges.compactMap { relation, relationEdges in
            let observedRelations = mergedObservedRelations(relationEdges.flatMap(\.observedRelations))
            guard !observedRelations.isEmpty else { return nil }
            return CollapsedRelationSummary(
                relation: relation,
                observedRelations: observedRelations,
                edgeCount: relationEdges.count,
                pendingEdgeCount: relationEdges.filter { $0.status == .inferred }.count
            )
        }
        .sorted { lhs, rhs in
            if lhs.edgeCount != rhs.edgeCount {
                return lhs.edgeCount > rhs.edgeCount
            }
            if lhs.observedRelations.count != rhs.observedRelations.count {
                return lhs.observedRelations.count > rhs.observedRelations.count
            }
            return lhs.relation.localizedCaseInsensitiveCompare(rhs.relation) == .orderedAscending
        }
    }

    private func buildGraphVisibleEdges(
        mode: GraphDensityMode?,
        baseAcceptedEdges: [StoryKnowledgeEdge],
        basePendingEdges: [StoryKnowledgeEdge]
    ) -> [StoryKnowledgeEdge] {
        if let mode {
            let focusMultiplier = conflictFocus == nil ? 1 : 2
            let acceptedBudget = min(mode.acceptedEdgeBudget * focusMultiplier, baseAcceptedEdges.count)
            let pendingBudget = min(mode.pendingEdgeBudget * focusMultiplier, basePendingEdges.count)

            var edges: [StoryKnowledgeEdge] = []
            if visibilityFilter != .pending {
                edges.append(contentsOf: baseAcceptedEdges.prefix(acceptedBudget))
            }
            if visibilityFilter != .accepted {
                edges.append(contentsOf: basePendingEdges.prefix(pendingBudget))
            }
            return Array(edges.prefix(mode.totalEdgeCap))
        }

        let acceptedBudget = conflictFocus == nil ? 16 : 24
        let pendingBudget = conflictFocus == nil ? 8 : 12
        var edges: [StoryKnowledgeEdge] = []
        if visibilityFilter != .pending {
            edges.append(contentsOf: baseAcceptedEdges.prefix(acceptedBudget))
        }
        if visibilityFilter != .accepted {
            edges.append(contentsOf: basePendingEdges.prefix(pendingBudget))
        }
        return Array(edges.prefix(28))
    }

    private func buildGraphVisibleNodes(
        mode: GraphDensityMode?,
        edges: [StoryKnowledgeEdge],
        baseNodes: [StoryKnowledgeNode]
    ) -> [StoryKnowledgeNode] {
        let nodeCap = mode?.nodeCap ?? 18
        let edgeNodeIDs = Set(edges.flatMap { [$0.sourceNodeID, $0.targetNodeID] })
        var nodes: [StoryKnowledgeNode] = []
        var seen = Set<UUID>()

        for nodeID in edgeNodeIDs.sorted(by: { lhs, rhs in
            let lhsName = storyKnowledgeNodesByID[lhs]?.name ?? ""
            let rhsName = storyKnowledgeNodesByID[rhs]?.name ?? ""
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }) {
            guard let node = storyKnowledgeNodesByID[nodeID], seen.insert(node.id).inserted else { continue }
            nodes.append(node)
        }

        for node in baseNodes where seen.insert(node.id).inserted {
            nodes.append(node)
            if nodes.count >= nodeCap {
                break
            }
        }

        return nodes
    }

    private func buildGraphIncidentEdgesByNodeID(
        from edges: [StoryKnowledgeEdge]
    ) -> [UUID: [StoryKnowledgeEdge]] {
        let groupedEdges = Dictionary(grouping: edges.flatMap { edge in
            [(edge.sourceNodeID, edge), (edge.targetNodeID, edge)]
        }, by: \.0)

        return groupedEdges.mapValues { entries in
            sort(edges: entries.map(\.1))
        }
    }

    private func buildGraphNodeModels(
        from nodes: [StoryKnowledgeNode]
    ) -> [StoryKnowledgeNeighborhoodGraphView.NodeModel] {
        nodes.map { node in
            StoryKnowledgeNeighborhoodGraphView.NodeModel(
                id: node.id,
                title: node.name,
                subtitle: node.kind.rawValue.capitalized,
                summary: node.summary,
                evidenceSummary: graphEvidencePreviewText(store.storyKnowledgeEvidenceItems(for: node)),
                kind: node.kind,
                status: node.status,
                confidence: node.confidence,
                isLinkedToCompendium: node.resolvedCompendiumID != nil
            )
        }
    }

    private func buildGraphEdgeModels(
        from edges: [StoryKnowledgeEdge]
    ) -> [StoryKnowledgeNeighborhoodGraphView.EdgeModel] {
        edges.map { edge in
            StoryKnowledgeNeighborhoodGraphView.EdgeModel(
                id: edge.id,
                sourceNodeID: edge.sourceNodeID,
                targetNodeID: edge.targetNodeID,
                relation: edge.relation,
                label: store.storyKnowledgeEdgeDisplayLabel(edge),
                note: edge.note,
                evidenceSummary: graphEvidencePreviewText(store.storyKnowledgeEvidenceItems(for: edge)),
                status: edge.status
            )
        }
    }

    private func buildGraphCoverageLabel(
        visibleNodes: [StoryKnowledgeNode],
        visibleEdges: [StoryKnowledgeEdge],
        totalNodes: [StoryKnowledgeNode],
        totalEdges: [StoryKnowledgeEdge]
    ) -> String {
        if visibleNodes.count == totalNodes.count && visibleEdges.count == totalEdges.count {
            return "\(visibleNodes.count) filtered nodes • \(visibleEdges.count) filtered edges"
        }
        return "Showing \(visibleNodes.count) of \(totalNodes.count) filtered nodes • \(visibleEdges.count) of \(totalEdges.count) filtered edges"
    }

    private func buildGraphClusterSummaries(
        visibleNodes: [StoryKnowledgeNode],
        visibleEdges: [StoryKnowledgeEdge]
    ) -> [GraphClusterSummary] {
        let nodesByKind = Dictionary(grouping: visibleNodes) { $0.kind }
        return StoryKnowledgeNodeKind.allCases.compactMap { kind in
            let nodes = nodesByKind[kind] ?? []
            guard !nodes.isEmpty else { return nil }

            let nodeIDs = Set(nodes.map(\.id))
            let incidentEdges = visibleEdges.filter { edge in
                nodeIDs.contains(edge.sourceNodeID) || nodeIDs.contains(edge.targetNodeID)
            }
            let crossKindEdgeCount = incidentEdges.filter { edge in
                guard let sourceKind = storyKnowledgeNodesByID[edge.sourceNodeID]?.kind,
                      let targetKind = storyKnowledgeNodesByID[edge.targetNodeID]?.kind else {
                    return false
                }
                return sourceKind != targetKind
            }.count
            let topRelations = Dictionary(grouping: incidentEdges) { edge in
                store.storyKnowledgeEdgeDisplayLabel(edge)
            }
            .map { GraphClusterRelationSummary(relation: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.relation.localizedCaseInsensitiveCompare(rhs.relation) == .orderedAscending
            }

            return GraphClusterSummary(
                kind: kind,
                nodeCount: nodes.count,
                canonicalNodeCount: nodes.filter { $0.status == .canonical }.count,
                pendingNodeCount: nodes.filter { $0.status == .inferred }.count,
                incidentEdgeCount: incidentEdges.count,
                crossKindEdgeCount: crossKindEdgeCount,
                topRelations: Array(topRelations.prefix(3))
            )
        }
    }

    private func buildGraphClusterConnectionSummaries(
        visibleEdges: [StoryKnowledgeEdge]
    ) -> [GraphClusterConnectionSummary] {
        let groupedEdges = Dictionary(grouping: visibleEdges.compactMap { edge -> (String, StoryKnowledgeEdge)? in
            guard let sourceKind = storyKnowledgeNodesByID[edge.sourceNodeID]?.kind,
                  let targetKind = storyKnowledgeNodesByID[edge.targetNodeID]?.kind,
                  sourceKind != targetKind else {
                return nil
            }
            return ("\(sourceKind.rawValue)->\(targetKind.rawValue)", edge)
        }, by: \.0)

        return groupedEdges.compactMap { _, entries in
            guard let firstEdge = entries.first?.1,
                  let sourceKind = storyKnowledgeNodesByID[firstEdge.sourceNodeID]?.kind,
                  let targetKind = storyKnowledgeNodesByID[firstEdge.targetNodeID]?.kind else {
                return nil
            }

            let edges = entries.map(\.1)
            let pairCount = Set(edges.map { "\($0.sourceNodeID.uuidString)->\($0.targetNodeID.uuidString)" }).count
            let topRelations = Dictionary(grouping: edges) { $0.relation }
                .map { GraphClusterRelationSummary(relation: $0.key, count: $0.value.count) }
                .sorted { lhs, rhs in
                    if lhs.count != rhs.count {
                        return lhs.count > rhs.count
                    }
                    return lhs.relation.localizedCaseInsensitiveCompare(rhs.relation) == .orderedAscending
                }

            return GraphClusterConnectionSummary(
                sourceKind: sourceKind,
                targetKind: targetKind,
                edgeCount: edges.count,
                pairCount: pairCount,
                pendingEdgeCount: edges.filter { $0.status == .inferred }.count,
                topRelations: Array(topRelations.prefix(3)),
                evidenceItems: mergedEvidenceItems(
                    edges.flatMap { store.storyKnowledgeEvidenceItems(for: $0) }
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.edgeCount != rhs.edgeCount {
                return lhs.edgeCount > rhs.edgeCount
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func buildGraphFocusedLinkRelationSummaries(
        connectionFocusedAcceptedEdges: [StoryKnowledgeEdge],
        connectionFocusedPendingEdges: [StoryKnowledgeEdge]
    ) -> [GraphFocusedLinkRelationSummary] {
        guard activeExpandedGraphConnectionFocus != nil else { return [] }

        let edges = connectionFocusedAcceptedEdges + connectionFocusedPendingEdges
        let groupedEdges = Dictionary(grouping: edges) { normalizedRelationKey($0.relation) }

        return groupedEdges.compactMap { _, relationEdges in
            guard let firstEdge = relationEdges.first else { return nil }

            let pairCount = Set(
                relationEdges.map { "\($0.sourceNodeID.uuidString)->\($0.targetNodeID.uuidString)" }
            ).count
            let pairLabels = Array(Set(relationEdges.map { store.storyKnowledgeEdgeDisplayLabel($0) }))
                .sorted { lhs, rhs in
                    lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                }

            return GraphFocusedLinkRelationSummary(
                relation: firstEdge.relation,
                edgeCount: relationEdges.count,
                pairCount: pairCount,
                pendingEdgeCount: relationEdges.filter { $0.status == .inferred }.count,
                pairLabels: Array(pairLabels.prefix(3)),
                evidenceItems: mergedEvidenceItems(
                    relationEdges.flatMap { store.storyKnowledgeEvidenceItems(for: $0) }
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.edgeCount != rhs.edgeCount {
                return lhs.edgeCount > rhs.edgeCount
            }
            return lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
        }
    }

    private func graphClusterConnectionSummaryKey(
        sourceKind: StoryKnowledgeNodeKind,
        targetKind: StoryKnowledgeNodeKind
    ) -> String {
        "\(sourceKind.rawValue)->\(targetKind.rawValue)"
    }

    private func clearGraphSelection() {
        graphSelectedNodeID = nil
        graphSelectedEdgeID = nil
    }

    private func cycleVisibleNodeSelection(step: Int) {
        guard !graphNavigableNodes.isEmpty else { return }

        let currentIndex = graphNavigableNodes.firstIndex { $0.id == graphSelectedNodeID } ?? (step > 0 ? -1 : 0)
        let nextIndex = wrappedIndex(from: currentIndex, step: step, count: graphNavigableNodes.count)
        graphSelectedEdgeID = nil
        graphSelectedNodeID = graphNavigableNodes[nextIndex].id
    }

    private func cycleVisibleEdgeSelection(step: Int) {
        guard !graphNavigableEdges.isEmpty else { return }

        let currentIndex = graphNavigableEdges.firstIndex { $0.id == graphSelectedEdgeID } ?? (step > 0 ? -1 : 0)
        let nextIndex = wrappedIndex(from: currentIndex, step: step, count: graphNavigableEdges.count)
        graphSelectedNodeID = nil
        graphSelectedEdgeID = graphNavigableEdges[nextIndex].id
    }

    private func wrappedIndex(from currentIndex: Int, step: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (currentIndex + step + count) % count
    }

    private func applyExpandedConnectionFocus(
        to edges: [StoryKnowledgeEdge]
    ) -> [StoryKnowledgeEdge] {
        guard let focus = activeExpandedGraphConnectionFocus else { return edges }
        return edges.filter { edge in
            guard let sourceKind = storyKnowledgeNodesByID[edge.sourceNodeID]?.kind,
                  let targetKind = storyKnowledgeNodesByID[edge.targetNodeID]?.kind else {
                return false
            }
            return sourceKind == focus.sourceKind && targetKind == focus.targetKind
        }
    }

    private func applyExpandedRelationFocus(
        to edges: [StoryKnowledgeEdge]
    ) -> [StoryKnowledgeEdge] {
        guard let focus = activeExpandedGraphRelationFocus else { return edges }
        return edges.filter { normalizedRelationKey($0.relation) == normalizedRelationKey(focus.relation) }
    }

    private func isExpandedConnectionFocused(on summary: GraphClusterConnectionSummary) -> Bool {
        guard let focus = expandedGraphConnectionFocus else { return false }
        return focus.sourceKind == summary.sourceKind && focus.targetKind == summary.targetKind
    }

    private func toggleExpandedConnectionFocus(_ summary: GraphClusterConnectionSummary) {
        if isExpandedConnectionFocused(on: summary) {
            expandedGraphConnectionFocus = nil
            expandedGraphRelationFocus = nil
        } else {
            expandedGraphConnectionFocus = GraphClusterConnectionFocus(
                sourceKind: summary.sourceKind,
                targetKind: summary.targetKind
            )
            expandedGraphRelationFocus = nil
            clearGraphSelection()
        }
    }

    private func isExpandedRelationFocused(
        on relation: String,
        within summary: GraphClusterConnectionSummary?
    ) -> Bool {
        guard let focus = expandedGraphRelationFocus,
              let summary,
              isExpandedConnectionFocused(on: summary) else { return false }
        return normalizedRelationKey(focus.relation) == normalizedRelationKey(relation)
    }

    private func toggleExpandedRelationFocus(
        _ relation: String,
        within summary: GraphClusterConnectionSummary?
    ) {
        guard let summary else { return }

        if isExpandedRelationFocused(on: relation, within: summary) {
            expandedGraphRelationFocus = nil
        } else {
            expandedGraphConnectionFocus = GraphClusterConnectionFocus(
                sourceKind: summary.sourceKind,
                targetKind: summary.targetKind
            )
            expandedGraphRelationFocus = GraphRelationFocus(relation: relation)
            clearGraphSelection()
        }
    }

    private func hasGraphEdges(for focus: GraphClusterConnectionFocus) -> Bool {
        graphCandidateEdges.contains { edge in
            guard let sourceKind = storyKnowledgeNodesByID[edge.sourceNodeID]?.kind,
                  let targetKind = storyKnowledgeNodesByID[edge.targetNodeID]?.kind else {
                return false
            }
            return sourceKind == focus.sourceKind && targetKind == focus.targetKind
        }
    }

    private func hasGraphEdges(forRelation relation: String) -> Bool {
        let relationKey = normalizedRelationKey(relation)
        return (graphConnectionFocusedAcceptedEdges + graphConnectionFocusedPendingEdges).contains {
            normalizedRelationKey($0.relation) == relationKey
        }
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

    private func matchesFocus(node: StoryKnowledgeNode) -> Bool {
        guard let conflictFocus else { return true }
        if conflictFocus.nodeIDs.contains(node.id) {
            return true
        }
        if let compendiumID = conflictFocus.compendiumID,
           node.resolvedCompendiumID == compendiumID {
            return true
        }
        return false
    }

    private func matchesNodeKind(edge: StoryKnowledgeEdge) -> Bool {
        guard let selectedKind = nodeKindFilter.nodeKind else { return true }
        let sourceKind = storyKnowledgeNodesByID[edge.sourceNodeID]?.kind
        let targetKind = storyKnowledgeNodesByID[edge.targetNodeID]?.kind
        return sourceKind == selectedKind || targetKind == selectedKind
    }

    private func matchesFocus(edge: StoryKnowledgeEdge) -> Bool {
        guard let conflictFocus else { return true }

        let edgeNodeIDs = Set([edge.sourceNodeID, edge.targetNodeID])
        if conflictFocus.nodeIDs.count > 1, conflictFocus.compendiumID == nil {
            return edgeNodeIDs == conflictFocus.nodeIDs
        }
        if !edgeNodeIDs.isDisjoint(with: conflictFocus.nodeIDs) {
            return true
        }
        guard let compendiumID = conflictFocus.compendiumID else {
            return false
        }
        let sourceCompendiumID = storyKnowledgeNodesByID[edge.sourceNodeID]?.resolvedCompendiumID
        let targetCompendiumID = storyKnowledgeNodesByID[edge.targetNodeID]?.resolvedCompendiumID
        return sourceCompendiumID == compendiumID || targetCompendiumID == compendiumID
    }

    private func matchesRelation(edge: StoryKnowledgeEdge) -> Bool {
        relationFilter.isEmpty || edge.relation == relationFilter
    }

    private func matchesSearch(edge: StoryKnowledgeEdge) -> Bool {
        let query = normalizedSearchQuery()
        guard !query.isEmpty else { return true }
        let observedRelationDiagnostics = store.storyKnowledgeObservedRelationDiagnostics(for: edge)
        let haystack = [
            store.storyKnowledgeEdgeDisplayLabel(edge),
            edge.status.rawValue,
            edge.note,
            observedRelationDiagnostics.map(\.message).joined(separator: " "),
            observedRelationDiagnostics.flatMap { diagnostic in
                diagnostic.evidenceItems.map { "\($0.chapterTitle) \($0.sceneTitle)" }
            }
            .joined(separator: " ")
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
            + item.acceptedAssertions.map(\.label)
            + item.evidenceItems.map { "\($0.chapterTitle) \($0.sceneTitle)" }
            + item.acceptedAssertions.flatMap { assertion in
                assertion.evidenceItems.map { "\($0.chapterTitle) \($0.sceneTitle)" }
            }
        )
        .joined(separator: "\n")
        .lowercased()
        return haystack.contains(query)
    }

    private func matchesFocus(conflict item: AppStore.StoryKnowledgeConflictItem) -> Bool {
        guard let conflictFocus else { return true }

        if conflictFocus.nodeIDs.count > 1,
           conflictFocus.compendiumID == nil,
           let sourceNodeID = item.sourceNodeID,
           let targetNodeID = item.targetNodeID {
            return Set([sourceNodeID, targetNodeID]) == conflictFocus.nodeIDs
        }
        if let sourceNodeID = item.sourceNodeID,
           conflictFocus.nodeIDs.contains(sourceNodeID) {
            return true
        }
        if let targetNodeID = item.targetNodeID,
           conflictFocus.nodeIDs.contains(targetNodeID) {
            return true
        }
        if let nodeID = item.nodeID,
           conflictFocus.nodeIDs.contains(nodeID) {
            return true
        }
        if let compendiumID = item.compendiumID,
           conflictFocus.compendiumID == compendiumID {
            return true
        }
        return false
    }

    private func focus(on item: AppStore.StoryKnowledgeConflictItem) {
        switch item.kind {
        case .edgeRelationConflict:
            let nodeIDs = Set([item.sourceNodeID, item.targetNodeID].compactMap { $0 })
            guard nodeIDs.count == 2 else { return }
            conflictFocus = ConflictFocus(label: "Focused Pair: \(item.title)", nodeIDs: nodeIDs, compendiumID: nil)
        case .compendiumDrift:
            guard let nodeID = item.nodeID else { return }
            conflictFocus = ConflictFocus(
                label: "Focused Node: \(item.title)",
                nodeIDs: [nodeID],
                compendiumID: item.compendiumID
            )
        case .compendiumMatchConflict:
            guard let nodeID = item.nodeID else { return }
            conflictFocus = ConflictFocus(
                label: "Focused Match: \(item.title)",
                nodeIDs: [nodeID],
                compendiumID: item.compendiumID
            )
        }
    }

    private func sidebarFocus(for node: StoryKnowledgeNode) -> ConflictFocus {
        ConflictFocus(
            label: "Focused Node: \(node.name)",
            nodeIDs: [node.id],
            compendiumID: node.resolvedCompendiumID
        )
    }

    private func isSidebarFocused(on node: StoryKnowledgeNode) -> Bool {
        guard let conflictFocus else { return false }
        return conflictFocus.nodeIDs == Set([node.id])
            && conflictFocus.compendiumID == node.resolvedCompendiumID
    }

    private func sidebarFocus(for edge: StoryKnowledgeEdge) -> ConflictFocus {
        ConflictFocus(
            label: "Focused Pair: \(store.storyKnowledgeEdgeDisplayLabel(edge))",
            nodeIDs: [edge.sourceNodeID, edge.targetNodeID],
            compendiumID: nil
        )
    }

    private func isSidebarFocused(on edge: StoryKnowledgeEdge) -> Bool {
        guard let conflictFocus else { return false }
        return conflictFocus.nodeIDs == Set([edge.sourceNodeID, edge.targetNodeID])
            && conflictFocus.compendiumID == nil
    }

    private func toggleSidebarFocus(for node: StoryKnowledgeNode) {
        if isSidebarFocused(on: node) {
            conflictFocus = nil
        } else {
            conflictFocus = sidebarFocus(for: node)
            graphSelectedNodeID = node.id
        }
    }

    private func toggleSidebarFocus(for edge: StoryKnowledgeEdge) {
        if isSidebarFocused(on: edge) {
            conflictFocus = nil
        } else {
            conflictFocus = sidebarFocus(for: edge)
            graphSelectedEdgeID = edge.id
        }
    }

    private func isKindFiltered(to kind: StoryKnowledgeNodeKind) -> Bool {
        nodeKindFilter.nodeKind == kind
    }

    private func toggleKindFilter(for kind: StoryKnowledgeNodeKind) {
        let nextFilter: StoryKnowledgePanelNodeKindFilter
        if isKindFiltered(to: kind) {
            nextFilter = .all
        } else {
            switch kind {
            case .character:
                nextFilter = .character
            case .location:
                nextFilter = .location
            case .object:
                nextFilter = .object
            case .concept:
                nextFilter = .concept
            case .group:
                nextFilter = .group
            case .event:
                nextFilter = .event
            case .unknown:
                nextFilter = .unknown
            }
        }
        store.setStoryKnowledgePanelNodeKindFilter(nextFilter)
    }

    private func applyExpandedClusterCanvasScope(
        to edges: [StoryKnowledgeEdge]
    ) -> [StoryKnowledgeEdge] {
        guard showingExpandedGraph, expandedGraphLayoutMode == .kindClusters else { return edges }

        return edges.filter { edge in
            guard let sourceKind = storyKnowledgeNodesByID[edge.sourceNodeID]?.kind,
                  let targetKind = storyKnowledgeNodesByID[edge.targetNodeID]?.kind else {
                return false
            }

            if activeExpandedGraphCollapsedKinds.contains(sourceKind) || activeExpandedGraphCollapsedKinds.contains(targetKind) {
                return false
            }

            if !activeExpandedGraphIsolatedKinds.isEmpty {
                return activeExpandedGraphIsolatedKinds.contains(sourceKind)
                    || activeExpandedGraphIsolatedKinds.contains(targetKind)
            }

            return true
        }
    }

    private func isExpandedClusterCollapsed(_ kind: StoryKnowledgeNodeKind) -> Bool {
        activeExpandedGraphCollapsedKinds.contains(kind)
    }

    private func isExpandedClusterIsolated(_ kind: StoryKnowledgeNodeKind) -> Bool {
        activeExpandedGraphIsolatedKinds.contains(kind)
    }

    private func clusterIsolationActionTitle(for kind: StoryKnowledgeNodeKind) -> String {
        if isExpandedClusterIsolated(kind) {
            return "Clear Isolate"
        }
        if !activeExpandedGraphIsolatedKinds.isEmpty {
            return "Add Isolate"
        }
        return "Isolate"
    }

    private func toggleExpandedClusterCollapse(_ kind: StoryKnowledgeNodeKind) {
        if expandedGraphCollapsedKinds.contains(kind) {
            expandedGraphCollapsedKinds.remove(kind)
        } else {
            expandedGraphCollapsedKinds.insert(kind)
            expandedGraphIsolatedKinds.remove(kind)
        }
    }

    private func toggleExpandedClusterIsolation(_ kind: StoryKnowledgeNodeKind) {
        if expandedGraphIsolatedKinds.contains(kind) {
            expandedGraphIsolatedKinds.remove(kind)
        } else {
            expandedGraphIsolatedKinds.insert(kind)
            expandedGraphCollapsedKinds.remove(kind)
        }
    }

    private func clearExpandedClusterCanvasScope() {
        expandedGraphCollapsedKinds = []
        expandedGraphIsolatedKinds = []
    }

    private func isRelationFiltered(to relation: String) -> Bool {
        normalizedRelationKey(relationFilter) == normalizedRelationKey(relation)
    }

    private func toggleRelationFilter(_ relation: String) {
        if isRelationFiltered(to: relation) {
            store.setStoryKnowledgePanelRelationFilter("")
        } else {
            store.setStoryKnowledgePanelRelationFilter(relation)
        }
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

    private func deduplicatedStoryKnowledgeNodes(
        _ nodes: [StoryKnowledgeNode]
    ) -> [StoryKnowledgeNode] {
        var mergedByID: [UUID: StoryKnowledgeNode] = [:]
        var orderedIDs: [UUID] = []

        for node in nodes {
            if let existing = mergedByID[node.id] {
                mergedByID[node.id] = mergeStoryKnowledgeNode(existing, node)
            } else {
                orderedIDs.append(node.id)
                mergedByID[node.id] = node
            }
        }

        return orderedIDs.compactMap { mergedByID[$0] }
    }

    private func deduplicatedStoryKnowledgeEdges(
        _ edges: [StoryKnowledgeEdge]
    ) -> [StoryKnowledgeEdge] {
        var mergedByID: [UUID: StoryKnowledgeEdge] = [:]
        var orderedIDs: [UUID] = []

        for edge in edges {
            if let existing = mergedByID[edge.id] {
                mergedByID[edge.id] = mergeStoryKnowledgeEdge(existing, edge)
            } else {
                orderedIDs.append(edge.id)
                mergedByID[edge.id] = edge
            }
        }

        return orderedIDs.compactMap { mergedByID[$0] }
    }

    private func mergeStoryKnowledgeNode(
        _ lhs: StoryKnowledgeNode,
        _ rhs: StoryKnowledgeNode
    ) -> StoryKnowledgeNode {
        let preferred = preferredStoryKnowledgeNode(lhs, rhs)
        let secondary = preferred.id == lhs.id
            && preferred.updatedAt == lhs.updatedAt
            && preferred.name == lhs.name
            && preferred.kind == lhs.kind
            && preferred.summary == lhs.summary
            && preferred.status == lhs.status
            && preferred.confidence == lhs.confidence
            && preferred.resolvedCompendiumID == lhs.resolvedCompendiumID
            && preferred.aliases == lhs.aliases
            && preferred.evidenceSceneIDs == lhs.evidenceSceneIDs ? rhs : lhs

        var merged = preferred
        if merged.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.name = secondary.name
        }
        if merged.kind == .unknown, secondary.kind != .unknown {
            merged.kind = secondary.kind
        }
        if merged.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.summary = secondary.summary
        }
        if merged.resolvedCompendiumID == nil {
            merged.resolvedCompendiumID = secondary.resolvedCompendiumID
        }
        merged.aliases = Array(Set(merged.aliases + secondary.aliases))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        merged.evidenceSceneIDs = Array(Set(merged.evidenceSceneIDs + secondary.evidenceSceneIDs))
            .sorted { $0.uuidString < $1.uuidString }
        merged.confidence = max(merged.confidence, secondary.confidence)
        merged.updatedAt = max(merged.updatedAt, secondary.updatedAt)
        return merged
    }

    private func mergeStoryKnowledgeEdge(
        _ lhs: StoryKnowledgeEdge,
        _ rhs: StoryKnowledgeEdge
    ) -> StoryKnowledgeEdge {
        let preferred = preferredStoryKnowledgeEdge(lhs, rhs)
        let secondary = preferred.id == lhs.id
            && preferred.updatedAt == lhs.updatedAt
            && preferred.relation == lhs.relation
            && preferred.note == lhs.note
            && preferred.status == lhs.status
            && preferred.confidence == lhs.confidence
            && preferred.sourceNodeID == lhs.sourceNodeID
            && preferred.targetNodeID == lhs.targetNodeID
            && preferred.observedRelations == lhs.observedRelations
            && preferred.evidenceSceneIDs == lhs.evidenceSceneIDs ? rhs : lhs

        var merged = preferred
        if merged.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.note = secondary.note
        }
        merged.observedRelations = mergedObservedRelations(
            merged.observedRelations + secondary.observedRelations
        )
        merged.evidenceSceneIDs = Array(Set(merged.evidenceSceneIDs + secondary.evidenceSceneIDs))
            .sorted { $0.uuidString < $1.uuidString }
        merged.confidence = max(merged.confidence, secondary.confidence)
        merged.updatedAt = max(merged.updatedAt, secondary.updatedAt)
        return merged
    }

    private func preferredStoryKnowledgeNode(
        _ lhs: StoryKnowledgeNode,
        _ rhs: StoryKnowledgeNode
    ) -> StoryKnowledgeNode {
        if storyKnowledgeStatusPriority(lhs.status) != storyKnowledgeStatusPriority(rhs.status) {
            return storyKnowledgeStatusPriority(lhs.status) > storyKnowledgeStatusPriority(rhs.status) ? lhs : rhs
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
        }
        if lhs.confidence != rhs.confidence {
            return lhs.confidence >= rhs.confidence ? lhs : rhs
        }
        let lhsSummaryLength = lhs.summary.trimmingCharacters(in: .whitespacesAndNewlines).count
        let rhsSummaryLength = rhs.summary.trimmingCharacters(in: .whitespacesAndNewlines).count
        if lhsSummaryLength != rhsSummaryLength {
            return lhsSummaryLength >= rhsSummaryLength ? lhs : rhs
        }
        return lhs
    }

    private func preferredStoryKnowledgeEdge(
        _ lhs: StoryKnowledgeEdge,
        _ rhs: StoryKnowledgeEdge
    ) -> StoryKnowledgeEdge {
        if storyKnowledgeStatusPriority(lhs.status) != storyKnowledgeStatusPriority(rhs.status) {
            return storyKnowledgeStatusPriority(lhs.status) > storyKnowledgeStatusPriority(rhs.status) ? lhs : rhs
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
        }
        if lhs.confidence != rhs.confidence {
            return lhs.confidence >= rhs.confidence ? lhs : rhs
        }
        let lhsObservedCount = lhs.observedRelations.count
        let rhsObservedCount = rhs.observedRelations.count
        if lhsObservedCount != rhsObservedCount {
            return lhsObservedCount >= rhsObservedCount ? lhs : rhs
        }
        return lhs
    }

    private func storyKnowledgeStatusPriority(_ status: StoryKnowledgeRecordStatus) -> Int {
        switch status {
        case .canonical:
            return 2
        case .inferred:
            return 1
        case .rejected:
            return 0
        }
    }

    private func mergedObservedRelations(
        _ observedRelations: [StoryKnowledgeObservedRelation]
    ) -> [StoryKnowledgeObservedRelation] {
        var mergedByRelation: [String: StoryKnowledgeObservedRelation] = [:]

        for observedRelation in observedRelations {
            let normalizedRawRelation = observedRelation.rawRelation.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedTextKey(normalizedRawRelation)
            guard !normalizedRawRelation.isEmpty, !key.isEmpty else { continue }

            if var existing = mergedByRelation[key] {
                existing.sceneIDs = Array(Set(existing.sceneIDs + observedRelation.sceneIDs))
                    .sorted { $0.uuidString < $1.uuidString }
                mergedByRelation[key] = existing
            } else {
                mergedByRelation[key] = StoryKnowledgeObservedRelation(
                    rawRelation: normalizedRawRelation,
                    sceneIDs: Array(Set(observedRelation.sceneIDs)).sorted { $0.uuidString < $1.uuidString }
                )
            }
        }

        return mergedByRelation.values.sorted {
            $0.rawRelation.localizedCaseInsensitiveCompare($1.rawRelation) == .orderedAscending
        }
    }

    private func mergedEvidenceItems(
        _ items: [AppStore.StoryKnowledgeEvidenceItem]
    ) -> [AppStore.StoryKnowledgeEvidenceItem] {
        var mergedBySceneID: [UUID: AppStore.StoryKnowledgeEvidenceItem] = [:]
        var orderedSceneIDs: [UUID] = []

        for item in items {
            if mergedBySceneID[item.sceneID] == nil {
                orderedSceneIDs.append(item.sceneID)
            }
            mergedBySceneID[item.sceneID] = item
        }

        return orderedSceneIDs.compactMap { mergedBySceneID[$0] }
    }

    private func graphFocusCoverageBadges(
        edgeCount: Int,
        pairCount: Int? = nil,
        pendingEdgeCount: Int,
        evidenceItems: [AppStore.StoryKnowledgeEvidenceItem]
    ) -> [String] {
        var labels: [String] = []
        labels.append("\(edgeCount) edge" + (edgeCount == 1 ? "" : "s"))
        if let pairCount {
            labels.append("\(pairCount) pair" + (pairCount == 1 ? "" : "s"))
        }
        if pendingEdgeCount > 0 {
            labels.append("\(pendingEdgeCount) pending")
        }

        let sceneCount = evidenceItems.count
        if sceneCount > 0 {
            labels.append("\(sceneCount) scene" + (sceneCount == 1 ? "" : "s"))
        }
        return labels
    }

    private func graphEvidencePreviewText(
        _ items: [AppStore.StoryKnowledgeEvidenceItem],
        maxItems: Int = 2
    ) -> String {
        guard !items.isEmpty else { return "" }

        let visibleItems = Array(items.prefix(maxItems))
        let labels = visibleItems.map { "\($0.chapterTitle) / \($0.sceneTitle)" }
        let remainingCount = items.count - visibleItems.count

        if remainingCount > 0 {
            return "Evidence: \(labels.joined(separator: " • ")) • +\(remainingCount) more"
        }
        return "Evidence: \(labels.joined(separator: " • "))"
    }

    private func isCollapsedRelationSelected(_ relation: String) -> Bool {
        isRelationFiltered(to: relation)
    }

    private func toggleCollapsedRelationFilter(_ relation: String) {
        toggleRelationFilter(relation)
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
    let observedRelationDiagnostics: [AppStore.StoryKnowledgeObservedRelationDiagnostic]
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

            if !observedRelationDiagnostics.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Observed normalization")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(observedRelationDiagnostics) { diagnostic in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(diagnostic.message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            if !diagnostic.evidenceItems.isEmpty {
                                evidenceSection(items: diagnostic.evidenceItems, onRevealScene: onRevealScene)
                            }
                        }
                    }
                }
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
    let onResolveNodeToCompendium: (UUID, UUID) -> Void
    let onReviewCompendiumMerge: (UUID) -> Void
    let onFocus: () -> Void
    let onRejectNode: (UUID) -> Void
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

            if !item.acceptedAssertions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accepted References")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(item.acceptedAssertions) { assertion in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(assertion.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            if !assertion.evidenceItems.isEmpty {
                                evidenceSection(items: assertion.evidenceItems, onRevealScene: onRevealScene)
                            }
                        }
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
                        Button("Focus Pair") {
                            onFocus()
                        }
                        .disabled(isUpdating)

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
                    Button("Focus Node") {
                        onFocus()
                    }
                    .disabled(isUpdating)

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
                case .compendiumMatchConflict:
                    Button("Focus Match") {
                        onFocus()
                    }
                    .disabled(isUpdating)

                    if let compendiumID = item.compendiumID {
                        Button("Open Compendium") {
                            onOpenCompendiumEntry(compendiumID)
                        }
                        .disabled(isUpdating)
                    }

                    if let nodeID = item.nodeID,
                       let compendiumID = item.compendiumID {
                        Button("Resolve to Compendium") {
                            onResolveNodeToCompendium(nodeID, compendiumID)
                        }
                        .disabled(isUpdating)

                        Button("Reject Pending", role: .destructive) {
                            onRejectNode(nodeID)
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

@ViewBuilder
private func graphFocusScopeLine(
    label: String,
    systemImage: String,
    badges: [String]
) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Label(label, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)

        if !badges.isEmpty {
            HStack(spacing: 6) {
                ForEach(badges, id: \.self) { badge in
                    statusBadge(badge)
                }
            }
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
