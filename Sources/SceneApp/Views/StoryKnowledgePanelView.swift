import SwiftUI

struct StoryKnowledgePanelView: View {
    @EnvironmentObject private var store: AppStore
    @State private var refreshTask: Task<Void, Never>?
    @State private var refreshError: String = ""
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

                    nodeSection(
                        title: "Accepted Nodes",
                        emptyTitle: "No accepted nodes.",
                        nodes: acceptedNodes
                    )

                    edgeSection(
                        title: "Accepted Edges",
                        emptyTitle: "No accepted edges.",
                        edges: acceptedEdges
                    )

                    nodeSection(
                        title: "Pending Node Suggestions",
                        emptyTitle: "No node suggestions awaiting review.",
                        nodes: store.storyKnowledgePendingReviewNodes
                    )

                    edgeSection(
                        title: "Pending Edge Suggestions",
                        emptyTitle: "No edge suggestions awaiting review.",
                        edges: store.storyKnowledgePendingReviewEdges
                    )
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
                        onRevealScene: { store.revealStoryKnowledgeEvidenceScene($0) },
                        onOpenCompendiumEntry: onOpenCompendiumEntry,
                        onUpdateCompendium: { store.mergeStoryKnowledgeNodeIntoCompendium(node.id) },
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
                        onRevealScene: { store.revealStoryKnowledgeEvidenceScene($0) },
                        onAccept: { store.acceptStoryKnowledgeEdge(edge.id) },
                        onReject: { store.rejectStoryKnowledgeEdge(edge.id) }
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
}

private struct StoryKnowledgeNodeCard: View {
    let node: StoryKnowledgeNode
    let evidenceItems: [AppStore.StoryKnowledgeEvidenceItem]
    let isUpdating: Bool
    let onRevealScene: @MainActor (UUID) -> Void
    let onOpenCompendiumEntry: (UUID) -> Void
    let onUpdateCompendium: () -> Void
    let onPromote: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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
        .cardStyle()
    }
}

private struct StoryKnowledgeEdgeCard: View {
    let label: String
    let edge: StoryKnowledgeEdge
    let evidenceItems: [AppStore.StoryKnowledgeEvidenceItem]
    let isUpdating: Bool
    let onRevealScene: @MainActor (UUID) -> Void
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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
        .cardStyle()
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
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

private func confidenceLabel(_ confidence: Double) -> String {
    "\(Int((confidence * 100).rounded()))%"
}
