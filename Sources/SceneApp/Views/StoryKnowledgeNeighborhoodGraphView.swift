import SwiftUI

struct StoryKnowledgeNeighborhoodGraphView: View {
    enum LayoutMode: String, CaseIterable, Identifiable {
        case neighborhood
        case kindClusters

        var id: String { rawValue }

        var title: String {
            switch self {
            case .neighborhood:
                return "Neighborhood"
            case .kindClusters:
                return "Kind Clusters"
            }
        }

        var graphTitle: String {
            switch self {
            case .neighborhood:
                return "Neighborhood Graph"
            case .kindClusters:
                return "Clustered Graph"
            }
        }

        var graphDescription: String {
            switch self {
            case .neighborhood:
                return "Visualizes the current filtered knowledge neighborhood. Select a node to anchor and inspect its local graph. Drag to pan, pinch to zoom, or use Command--, Command-Plus, Shift-Command-F, and Command-0."
            case .kindClusters:
                return "Groups visible knowledge by node kind to keep broader project views readable. Drag to pan, pinch to zoom, or use Command--, Command-Plus, Shift-Command-F, and Command-0."
            }
        }
    }

    struct NodeModel: Identifiable, Equatable {
        let id: UUID
        let title: String
        let subtitle: String
        let summary: String
        let kind: StoryKnowledgeNodeKind
        let status: StoryKnowledgeRecordStatus
        let confidence: Double
        let isLinkedToCompendium: Bool
    }

    struct EdgeModel: Identifiable, Equatable {
        let id: UUID
        let sourceNodeID: UUID
        let targetNodeID: UUID
        let relation: String
        let label: String
        let note: String
        let status: StoryKnowledgeRecordStatus
    }

    private struct ClusterLabel: Identifiable {
        let id: String
        let title: String
        let center: CGPoint
        let color: Color
    }

    private struct LayoutResult {
        let positions: [UUID: CGPoint]
        let labelPositions: [UUID: CGPoint]
        let clusterLabels: [ClusterLabel]
    }

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1
    @State private var contentOffset: CGSize = .zero
    @State private var contentScale: CGFloat = 1
    @State private var canvasSize: CGSize = .zero
    @State private var isInteractingWithViewport = false
    @State private var hoveredNodeID: UUID?
    @State private var hoveredEdgeID: UUID?

    let nodes: [NodeModel]
    let edges: [EdgeModel]
    let preferredAnchorNodeIDs: [UUID]
    let layoutMode: LayoutMode
    @Binding var selectedNodeID: UUID?
    @Binding var selectedEdgeID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(layoutMode.graphTitle)
                    .font(.headline)
                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        stepZoom(by: 0.85)
                    }
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .keyboardShortcut("-", modifiers: [.command])
                .help("Zoom Out (Command--)")

                Text("\(zoomPercentage)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 42, alignment: .center)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        stepZoom(by: 1.18)
                    }
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .keyboardShortcut("=", modifiers: [.command])
                .help("Zoom In (Command-Plus)")

                Button(fitButtonTitle) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        fitViewport()
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(nodes.isEmpty)
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .help("\(fitButtonTitle) (Shift-Command-F)")

                Button("Reset View") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        resetViewport()
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .keyboardShortcut("0", modifiers: [.command])
                .help("Reset View (Command-0)")

                Text("\(nodes.count) nodes • \(edges.count) edges")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(layoutMode.graphDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            legendView

            if nodes.isEmpty {
                ContentUnavailableView(
                    "No Graph Data",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Adjust filters or accept more knowledge to render a neighborhood graph.")
                )
                .frame(maxWidth: .infinity)
                .frame(height: 220)
            } else {
                GeometryReader { geometry in
                    let layout = layout(in: geometry.size)

                    ZStack {
                        ZStack {
                            Canvas { context, _ in
                                for edge in edges {
                                    guard let source = layout.positions[edge.sourceNodeID],
                                          let target = layout.positions[edge.targetNodeID] else {
                                        continue
                                    }

                                    var path = Path()
                                    path.move(to: source)
                                    path.addLine(to: target)

                                    context.stroke(
                                        path,
                                        with: .color(edgeColor(edge).opacity(edgeOpacity(edge))),
                                        style: StrokeStyle(
                                            lineWidth: selectedNodeID == nil ? 2 : 2.5,
                                            lineCap: .round,
                                            dash: edge.status == .inferred ? [6, 5] : []
                                        )
                                    )
                                }
                            }

                            ForEach(layout.clusterLabels) { clusterLabel in
                                clusterLabelBadge(clusterLabel)
                                    .position(x: clusterLabel.center.x, y: clusterLabel.center.y - 54)
                            }

                            ForEach(nodes) { node in
                                if let position = layout.positions[node.id] {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            selectedEdgeID = nil
                                            selectedNodeID = selectedNodeID == node.id ? nil : node.id
                                        }
                                    } label: {
                                        nodeBubble(node)
                                    }
                                    .buttonStyle(.plain)
                                    .position(position)
                                    .opacity(nodeOpacity(node.id))
                                    .onHover { isHovering in
                                        hoveredNodeID = isHovering ? node.id : (hoveredNodeID == node.id ? nil : hoveredNodeID)
                                    }
                                    .shadow(
                                        color: selectionRingColor(node).opacity(selectedNodeID == node.id ? 0.22 : 0.08),
                                        radius: selectedNodeID == node.id ? 8 : 3,
                                        y: 2
                                    )
                                }
                            }

                            ForEach(edges) { edge in
                                if let labelPosition = layout.labelPositions[edge.id] {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            selectedNodeID = nil
                                            selectedEdgeID = selectedEdgeID == edge.id ? nil : edge.id
                                        }
                                    } label: {
                                        edgeSelectionBadge(edge)
                                    }
                                    .buttonStyle(.plain)
                                    .position(labelPosition)
                                    .opacity(edgeSelectionOpacity(edge))
                                    .onHover { isHovering in
                                        hoveredEdgeID = isHovering ? edge.id : (hoveredEdgeID == edge.id ? nil : hoveredEdgeID)
                                    }
                                }
                            }

                            if !isInteractingWithViewport,
                               let hoveredEdgeID,
                               let edge = edges.first(where: { $0.id == hoveredEdgeID }),
                               let position = layout.labelPositions[hoveredEdgeID] {
                                hoverCard(
                                    title: edge.label,
                                    detail: edge.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? "Relation: \(edge.relation.replacingOccurrences(of: "_", with: " "))"
                                        : edge.note
                                )
                                .position(x: position.x, y: position.y - 42)
                            } else if !isInteractingWithViewport,
                                      let hoveredNodeID,
                                      let node = nodes.first(where: { $0.id == hoveredNodeID }),
                                      let position = layout.positions[hoveredNodeID] {
                                hoverCard(
                                    title: node.title,
                                    detail: node.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? node.subtitle
                                        : node.summary
                                )
                                .position(x: position.x, y: position.y - 74)
                            }
                        }
                        .scaleEffect(effectiveScale)
                        .offset(effectiveOffset)
                    }
                    .animation(.easeInOut(duration: 0.18), value: selectedNodeID)
                    .animation(.easeInOut(duration: 0.18), value: selectedEdgeID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(nsColor: .controlBackgroundColor),
                                        Color(nsColor: .windowBackgroundColor)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .clipped()
                    .simultaneousGesture(dragGesture)
                    .simultaneousGesture(magnificationGesture)
                    .onAppear {
                        canvasSize = geometry.size
                    }
                    .onChange(of: geometry.size, initial: true) { _, newSize in
                        canvasSize = newSize
                    }
                }
                .frame(height: 320)
            }
        }
        .onChange(of: nodes.map(\.id), initial: false) { _, _ in
            resetViewport()
        }
    }

    private var legendView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Text("Legend")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                legendNodeStatusSample(
                    title: "Canonical node",
                    status: .canonical
                )

                legendNodeStatusSample(
                    title: "Suggested node",
                    status: .inferred
                )

                Divider()
                    .frame(height: 16)

                legendNodeKindSample(
                    title: "Character",
                    kind: .character
                )

                legendNodeKindSample(
                    title: "Location",
                    kind: .location
                )

                legendNodeKindSample(
                    title: "Object",
                    kind: .object
                )

                Divider()
                    .frame(height: 16)

                legendEdgeSample(
                    title: "Canonical edge",
                    status: .canonical
                )

                legendEdgeSample(
                    title: "Suggested edge",
                    status: .inferred
                )
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private var effectiveScale: CGFloat {
        min(max(contentScale * gestureScale, 0.75), 2.2)
    }

    private var effectiveOffset: CGSize {
        CGSize(
            width: contentOffset.width + dragTranslation.width,
            height: contentOffset.height + dragTranslation.height
        )
    }

    private var zoomPercentage: Int {
        Int((effectiveScale * 100).rounded())
    }

    private var fitButtonTitle: String {
        if selectedEdgeID != nil {
            return "Fit Pair"
        }
        if selectedNodeID != nil {
            return "Fit Node"
        }
        return "Fit Graph"
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onChanged { _ in
                beginViewportInteraction()
            }
            .onEnded { value in
                contentOffset.width += value.translation.width
                contentOffset.height += value.translation.height
                endViewportInteraction()
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .updating($gestureScale) { value, state, _ in
                state = value.magnification
            }
            .onChanged { _ in
                beginViewportInteraction()
            }
            .onEnded { value in
                contentScale = min(max(contentScale * value.magnification, 0.75), 2.2)
                endViewportInteraction()
            }
    }

    private func resetViewport() {
        contentOffset = .zero
        contentScale = 1
    }

    private func stepZoom(by factor: CGFloat) {
        contentScale = clampedScale(contentScale * factor)
    }

    private func fitViewport() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let layoutResult = layout(in: canvasSize)
        guard let bounds = focusBounds(in: layoutResult) else {
            resetViewport()
            return
        }

        let availableWidth = max(canvasSize.width - 56, 80)
        let availableHeight = max(canvasSize.height - 56, 80)
        let targetScale = clampedScale(
            min(
                availableWidth / max(bounds.width, 1),
                availableHeight / max(bounds.height, 1)
            )
        )
        let canvasCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let boundsCenter = CGPoint(x: bounds.midX, y: bounds.midY)

        contentScale = targetScale
        contentOffset = CGSize(
            width: -(boundsCenter.x - canvasCenter.x) * targetScale,
            height: -(boundsCenter.y - canvasCenter.y) * targetScale
        )
    }

    private func focusBounds(in layout: LayoutResult) -> CGRect? {
        if let selectedEdgeID,
           let edge = edges.first(where: { $0.id == selectedEdgeID }),
           let source = layout.positions[edge.sourceNodeID],
           let target = layout.positions[edge.targetNodeID] {
            return expandedBounds(for: [source, target], nodePadding: CGSize(width: 96, height: 72))
        }

        if let selectedNodeID,
           let position = layout.positions[selectedNodeID] {
            return CGRect(
                x: position.x - 86,
                y: position.y - 58,
                width: 172,
                height: 116
            )
        }

        let positions = nodes.compactMap { layout.positions[$0.id] }
        return expandedBounds(for: positions, nodePadding: CGSize(width: 96, height: 72))
    }

    private func expandedBounds(for positions: [CGPoint], nodePadding: CGSize) -> CGRect? {
        guard let first = positions.first else { return nil }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for position in positions.dropFirst() {
            minX = min(minX, position.x)
            maxX = max(maxX, position.x)
            minY = min(minY, position.y)
            maxY = max(maxY, position.y)
        }

        return CGRect(
            x: minX - nodePadding.width / 2,
            y: minY - nodePadding.height / 2,
            width: max(maxX - minX, 1) + nodePadding.width,
            height: max(maxY - minY, 1) + nodePadding.height
        )
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, 0.75), 2.2)
    }

    private func beginViewportInteraction() {
        guard !isInteractingWithViewport else { return }
        isInteractingWithViewport = true
        hoveredNodeID = nil
        hoveredEdgeID = nil
    }

    private func endViewportInteraction() {
        isInteractingWithViewport = false
    }

    private func layout(in size: CGSize) -> LayoutResult {
        switch layoutMode {
        case .neighborhood:
            return neighborhoodLayout(in: size)
        case .kindClusters:
            return clusteredLayout(in: size)
        }
    }

    private func neighborhoodLayout(in size: CGSize) -> LayoutResult {
        let sortedNodes = nodes.sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        guard !sortedNodes.isEmpty else {
            return LayoutResult(positions: [:], labelPositions: [:], clusterLabels: [])
        }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        if sortedNodes.count == 1, let node = sortedNodes.first {
            return LayoutResult(
                positions: [node.id: center],
                labelPositions: [:],
                clusterLabels: []
            )
        }

        let adjacency = adjacencyMap()
        let anchorNodeIDs = resolvedAnchorNodeIDs(from: sortedNodes.map(\.id), adjacency: adjacency)
        let distances = minimumDistances(from: anchorNodeIDs, adjacency: adjacency)

        var positions: [UUID: CGPoint] = [:]

        if anchorNodeIDs.count == 1, let anchorID = anchorNodeIDs.first {
            positions[anchorID] = center
        } else {
            let spacing = min(max(size.width * 0.18, 80), 140)
            let startX = center.x - (CGFloat(anchorNodeIDs.count - 1) * spacing / 2)
            for (index, nodeID) in anchorNodeIDs.enumerated() {
                positions[nodeID] = CGPoint(
                    x: startX + CGFloat(index) * spacing,
                    y: center.y
                )
            }
        }

        let remainingNodeIDs = sortedNodes.map(\.id).filter { !positions.keys.contains($0) }
        if edges.isEmpty {
            placeNodesOnRing(
                remainingNodeIDs,
                level: 1,
                around: center,
                in: size,
                positions: &positions
            )
        } else {
            let groupedNodeIDs = Dictionary(grouping: remainingNodeIDs) { nodeID in
                min(max(distances[nodeID] ?? 2, 1), 3)
            }
            for level in 1...3 {
                placeNodesOnRing(
                    groupedNodeIDs[level] ?? [],
                    level: level,
                    around: center,
                    in: size,
                    positions: &positions
                )
            }
        }

        let labelPositions = Dictionary(uniqueKeysWithValues: edges.compactMap { edge -> (UUID, CGPoint)? in
            guard let source = positions[edge.sourceNodeID],
                  let target = positions[edge.targetNodeID] else {
                return nil
            }
            return (
                edge.id,
                CGPoint(
                    x: (source.x + target.x) / 2,
                    y: (source.y + target.y) / 2
                )
            )
        })

        return LayoutResult(positions: positions, labelPositions: labelPositions, clusterLabels: [])
    }

    private func clusteredLayout(in size: CGSize) -> LayoutResult {
        let groupedNodes = Dictionary(grouping: nodes) { $0.kind }
        let orderedKinds = StoryKnowledgeNodeKind.allCases.filter { !(groupedNodes[$0] ?? []).isEmpty }

        guard !orderedKinds.isEmpty else {
            return LayoutResult(positions: [:], labelPositions: [:], clusterLabels: [])
        }

        let columnCount = min(3, max(1, orderedKinds.count))
        let rowCount = Int(ceil(Double(orderedKinds.count) / Double(columnCount)))
        let horizontalSpacing = size.width / CGFloat(columnCount + 1)
        let verticalSpacing = size.height / CGFloat(rowCount + 1)

        var positions: [UUID: CGPoint] = [:]
        var clusterLabels: [ClusterLabel] = []

        for (index, kind) in orderedKinds.enumerated() {
            let column = index % columnCount
            let row = index / columnCount
            let center = CGPoint(
                x: horizontalSpacing * CGFloat(column + 1),
                y: verticalSpacing * CGFloat(row + 1)
            )

            clusterLabels.append(
                ClusterLabel(
                    id: kind.rawValue,
                    title: kind.rawValue.capitalized,
                    center: center,
                    color: nodeFillColor(kind: kind)
                )
            )

            let clusterNodes = (groupedNodes[kind] ?? []).sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

            if clusterNodes.count == 1, let node = clusterNodes.first {
                positions[node.id] = center
                continue
            }

            let ringRadiusX = min(max(size.width * 0.08, 54), 110)
            let ringRadiusY = min(max(size.height * 0.07, 40), 84)

            for (nodeIndex, node) in clusterNodes.enumerated() {
                let angle = (-CGFloat.pi / 2)
                    + (2 * CGFloat.pi * CGFloat(nodeIndex) / CGFloat(max(clusterNodes.count, 1)))
                positions[node.id] = CGPoint(
                    x: center.x + cos(angle) * ringRadiusX,
                    y: center.y + sin(angle) * ringRadiusY
                )
            }
        }

        let labelPositions = Dictionary(uniqueKeysWithValues: edges.compactMap { edge -> (UUID, CGPoint)? in
            guard let source = positions[edge.sourceNodeID],
                  let target = positions[edge.targetNodeID] else {
                return nil
            }
            return (
                edge.id,
                CGPoint(
                    x: (source.x + target.x) / 2,
                    y: (source.y + target.y) / 2
                )
            )
        })

        return LayoutResult(
            positions: positions,
            labelPositions: labelPositions,
            clusterLabels: clusterLabels
        )
    }

    private func placeNodesOnRing(
        _ nodeIDs: [UUID],
        level: Int,
        around center: CGPoint,
        in size: CGSize,
        positions: inout [UUID: CGPoint]
    ) {
        guard !nodeIDs.isEmpty else { return }

        let radiusX = min(size.width * (0.2 + CGFloat(level) * 0.12), size.width / 2 - 70)
        let radiusY = min(size.height * (0.18 + CGFloat(level) * 0.11), size.height / 2 - 48)
        let orderedNodeIDs = nodeIDs.sorted { lhs, rhs in
            let lhsNode = nodes.first(where: { $0.id == lhs })?.title ?? ""
            let rhsNode = nodes.first(where: { $0.id == rhs })?.title ?? ""
            return lhsNode.localizedCaseInsensitiveCompare(rhsNode) == .orderedAscending
        }

        for (index, nodeID) in orderedNodeIDs.enumerated() {
            let angle = (-CGFloat.pi / 2) + (2 * CGFloat.pi * CGFloat(index) / CGFloat(max(orderedNodeIDs.count, 1)))
            positions[nodeID] = CGPoint(
                x: center.x + cos(angle) * radiusX,
                y: center.y + sin(angle) * radiusY
            )
        }
    }

    private func adjacencyMap() -> [UUID: Set<UUID>] {
        var adjacency: [UUID: Set<UUID>] = [:]

        for edge in edges {
            adjacency[edge.sourceNodeID, default: []].insert(edge.targetNodeID)
            adjacency[edge.targetNodeID, default: []].insert(edge.sourceNodeID)
        }

        for node in nodes {
            adjacency[node.id, default: []] = adjacency[node.id, default: []]
        }

        return adjacency
    }

    private func resolvedAnchorNodeIDs(
        from availableNodeIDs: [UUID],
        adjacency: [UUID: Set<UUID>]
    ) -> [UUID] {
        let availableNodeIDSet = Set(availableNodeIDs)

        if let selectedNodeID, availableNodeIDSet.contains(selectedNodeID) {
            return [selectedNodeID]
        }

        let preferred = preferredAnchorNodeIDs.filter { availableNodeIDSet.contains($0) }
        if !preferred.isEmpty {
            return Array(preferred.prefix(2))
        }

        let degreeSorted = availableNodeIDs.sorted { lhs, rhs in
            let lhsDegree = adjacency[lhs]?.count ?? 0
            let rhsDegree = adjacency[rhs]?.count ?? 0
            if lhsDegree != rhsDegree {
                return lhsDegree > rhsDegree
            }
            let lhsTitle = nodes.first(where: { $0.id == lhs })?.title ?? ""
            let rhsTitle = nodes.first(where: { $0.id == rhs })?.title ?? ""
            return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
        }
        return Array(degreeSorted.prefix(1))
    }

    private func minimumDistances(
        from anchorNodeIDs: [UUID],
        adjacency: [UUID: Set<UUID>]
    ) -> [UUID: Int] {
        guard !anchorNodeIDs.isEmpty else { return [:] }

        var distances: [UUID: Int] = [:]
        var queue: [UUID] = anchorNodeIDs
        for nodeID in anchorNodeIDs {
            distances[nodeID] = 0
        }

        var cursor = 0
        while cursor < queue.count {
            let nodeID = queue[cursor]
            cursor += 1
            let nextDistance = (distances[nodeID] ?? 0) + 1
            for neighbor in adjacency[nodeID] ?? [] where distances[neighbor] == nil {
                distances[neighbor] = nextDistance
                queue.append(neighbor)
            }
        }

        return distances
    }

    private func nodeBubble(_ node: NodeModel) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: nodeKindSymbol(node.kind))
                    .font(.caption)
                Text(node.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            Text(node.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(node.status.rawValue.capitalized)
                    .font(.caption2)
                if node.isLinkedToCompendium {
                    Image(systemName: "book.closed")
                        .font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 122)
        .background(nodeFillColor(node).opacity(selectedNodeID == node.id ? 0.28 : 0.18))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selectionRingColor(node), lineWidth: selectedNodeID == node.id ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func nodeKindSymbol(_ kind: StoryKnowledgeNodeKind) -> String {
        switch kind {
        case .character:
            return "person.fill"
        case .location:
            return "map.fill"
        case .object:
            return "shippingbox.fill"
        case .concept:
            return "lightbulb.fill"
        case .group:
            return "person.3.fill"
        case .event:
            return "sparkles"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    private func nodeFillColor(_ node: NodeModel) -> Color {
        nodeFillColor(kind: node.kind)
    }

    private func nodeFillColor(kind: StoryKnowledgeNodeKind) -> Color {
        switch kind {
        case .character:
            return .orange
        case .location:
            return .blue
        case .object:
            return .teal
        case .concept:
            return Color(red: 0.25, green: 0.42, blue: 0.74)
        case .group:
            return .green
        case .event:
            return .red
        case .unknown:
            return .gray
        }
    }

    private func selectionRingColor(_ node: NodeModel) -> Color {
        if selectedNodeID == node.id {
            return .accentColor
        }
        if node.status == .canonical {
            return nodeFillColor(node)
        }
        return Color(nsColor: .separatorColor)
    }

    private func edgeColor(_ edge: EdgeModel) -> Color {
        if selectedEdgeID == edge.id {
            return .accentColor
        }
        return edge.status == .canonical ? Color.accentColor : Color.secondary
    }

    private func edgeOpacity(_ edge: EdgeModel) -> Double {
        if let selectedEdgeID {
            return edge.id == selectedEdgeID ? 1 : 0.22
        }
        guard let selectedNodeID else { return 0.9 }
        return edge.sourceNodeID == selectedNodeID || edge.targetNodeID == selectedNodeID ? 1 : 0.22
    }

    private func nodeOpacity(_ nodeID: UUID) -> Double {
        if let selectedEdgeID,
           let edge = edges.first(where: { $0.id == selectedEdgeID }) {
            return edge.sourceNodeID == nodeID || edge.targetNodeID == nodeID ? 1 : 0.3
        }
        guard let selectedNodeID else { return 1 }
        if nodeID == selectedNodeID {
            return 1
        }
        let isAdjacent = edges.contains { edge in
            (edge.sourceNodeID == selectedNodeID && edge.targetNodeID == nodeID)
                || (edge.targetNodeID == selectedNodeID && edge.sourceNodeID == nodeID)
        }
        return isAdjacent ? 1 : 0.3
    }

    private func edgeSelectionOpacity(_ edge: EdgeModel) -> Double {
        if let selectedEdgeID {
            return edge.id == selectedEdgeID ? 1 : 0.5
        }
        if let selectedNodeID {
            return edge.sourceNodeID == selectedNodeID || edge.targetNodeID == selectedNodeID ? 0.95 : 0.35
        }
        return 0.75
    }

    private func edgeSelectionBadge(_ edge: EdgeModel) -> some View {
        Group {
            if edges.count <= 16 || selectedEdgeID == edge.id {
                Text(edge.relation.replacingOccurrences(of: "_", with: " "))
                    .font(.caption2)
                    .foregroundStyle(selectedEdgeID == edge.id ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(selectedEdgeID == edge.id ? 0.98 : 0.92))
                    .overlay(
                        Capsule()
                            .stroke(selectedEdgeID == edge.id ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .clipShape(Capsule())
            } else {
                Circle()
                    .fill(edgeColor(edge).opacity(0.9))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
                    )
            }
        }
    }

    private func hoverCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(width: 170, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.97))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
        .allowsHitTesting(false)
    }

    private func clusterLabelBadge(_ clusterLabel: ClusterLabel) -> some View {
        Text(clusterLabel.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(clusterLabel.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.94))
            .overlay(
                Capsule()
                    .stroke(clusterLabel.color.opacity(0.45), lineWidth: 1)
            )
            .clipShape(Capsule())
            .allowsHitTesting(false)
    }

    private func legendNodeStatusSample(
        title: String,
        status: StoryKnowledgeRecordStatus
    ) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 5)
                .fill(nodeFillColor(kind: .character).opacity(0.2))
                .frame(width: 18, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            status == .canonical ? nodeFillColor(kind: .character) : Color(nsColor: .separatorColor),
                            lineWidth: 1.5
                        )
                )

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func legendNodeKindSample(
        title: String,
        kind: StoryKnowledgeNodeKind
    ) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(nodeFillColor(kind: kind))
                .frame(width: 10, height: 10)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func legendEdgeSample(
        title: String,
        status: StoryKnowledgeRecordStatus
    ) -> some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 6))
                path.addLine(to: CGPoint(x: 18, y: 6))
            }
            .stroke(
                status == .canonical ? Color.accentColor : Color.secondary,
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    dash: status == .inferred ? [4, 3] : []
                )
            )
            .frame(width: 18, height: 12)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
