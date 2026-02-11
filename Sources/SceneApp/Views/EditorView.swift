import SwiftUI
import AppKit

struct EditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingSceneContextSheet: Bool = false
    @State private var generationPayloadPreview: AppStore.WorkshopPayloadPreview?
    @State private var generationPanelHeight: CGFloat = 0
    @State private var dragStartGenerationHeight: CGFloat?
    @State private var dragStartPointerY: CGFloat?

    private let generationButtonWidth: CGFloat = 150
    private let generationButtonHeight: CGFloat = 30
    private let generationButtonSpacing: CGFloat = 8
    private let generationResizeHandleHeight: CGFloat = 10
    private let sceneEditorMinimumHeight: CGFloat = 220

    private var generationActionColumnHeight: CGFloat {
        (generationButtonHeight * 3) + (generationButtonSpacing * 2) + 16
    }

    private var generationInputMinimumHeight: CGFloat {
        generationActionColumnHeight
    }

    private var generationPanelMinimumHeight: CGFloat {
        generationActionColumnHeight + 84
    }

    private var generationPanelInitialHeight: CGFloat {
        generationPanelMinimumHeight
    }

    private var beatHistory: [String] {
        store.beatInputHistory
    }

    private var selectedSceneContextCount: Int {
        store.selectedSceneContextCompendiumIDs.count
    }

    private var sceneTitleBinding: Binding<String> {
        Binding(
            get: { store.selectedScene?.title ?? "" },
            set: { store.updateSelectedSceneTitle($0) }
        )
    }

    private var sceneContentBinding: Binding<String> {
        Binding(
            get: { store.selectedScene?.content ?? "" },
            set: { store.updateSelectedSceneContent($0) }
        )
    }

    private var selectedPromptBinding: Binding<UUID?> {
        Binding(
            get: { store.project.selectedProsePromptID },
            set: { store.setSelectedProsePrompt($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.selectedScene != nil {
                writingWorkspace
            } else {
                ContentUnavailableView("No Scene Selected", systemImage: "text.document", description: Text("Select or create a scene to start writing."))
            }
        }
        .sheet(item: $generationPayloadPreview) { generationPayloadPreview in
            GenerationPayloadPreviewSheet(preview: generationPayloadPreview)
        }
        .sheet(isPresented: $showingSceneContextSheet) {
            SceneContextSheet()
                .environmentObject(store)
        }
    }

    private var writingWorkspace: some View {
        VStack(spacing: 0) {
            sceneHeader
            Divider()
            writingSplit
        }
    }

    private var sceneHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Scene title", text: sceneTitleBinding)
                .textFieldStyle(.roundedBorder)
                .font(.title3.weight(.semibold))
        }
        .padding(16)
    }

    private var writingSplit: some View {
        GeometryReader { proxy in
            let maxGenerationHeight = maximumGenerationHeight(in: proxy.size.height)
            let activeGenerationHeight = resolvedGenerationHeight(maximum: maxGenerationHeight)

            VStack(spacing: 0) {
                sceneEditor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                generationResizeHandle(
                    currentHeight: activeGenerationHeight,
                    maximumHeight: maxGenerationHeight
                )

                generationPanel
                    .frame(height: activeGenerationHeight)
            }
        }
    }

    private var sceneEditor: some View {
        TextEditor(text: sceneContentBinding)
            .font(.body)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    private var generationPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generate From Beat")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                Text("Prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Prompt", selection: selectedPromptBinding) {
                    Text("Default")
                        .tag(Optional<UUID>.none)
                    ForEach(store.prosePrompts) { prompt in
                        Text(prompt.title)
                            .tag(Optional(prompt.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280)

                Spacer(minLength: 0)

                Button {
                    showingSceneContextSheet = true
                } label: {
                    Label(
                        selectedSceneContextCount > 0
                            ? "Scene Context (\(selectedSceneContextCount))"
                            : "Scene Context",
                        systemImage: "books.vertical"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(alignment: .top, spacing: 10) {
                BeatInputTextView(
                    text: $store.beatInput,
                    onSend: { store.submitBeatGeneration() }
                )
                    .frame(minHeight: generationInputMinimumHeight, idealHeight: generationInputMinimumHeight, maxHeight: .infinity)

                VStack(alignment: .trailing, spacing: generationButtonSpacing) {
                    Menu {
                        if beatHistory.isEmpty {
                            Button("No previous beats") {}
                                .disabled(true)
                        } else {
                            ForEach(beatHistory, id: \.self) { entry in
                                Button(historyMenuTitle(entry)) {
                                    store.applyBeatInputFromHistory(entry)
                                }
                            }
                        }
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(height: generationButtonHeight)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(beatHistory.isEmpty)

                    Button {
                        do {
                            generationPayloadPreview = try store.makeProsePayloadPreview()
                        } catch {
                            store.lastError = error.localizedDescription
                        }
                    } label: {
                        Label("Preview", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(store.isGenerating)

                    Button {
                        if store.isGenerating {
                            store.cancelBeatGeneration()
                        } else {
                            store.submitBeatGeneration()
                        }
                    } label: {
                        Group {
                            if store.isGenerating {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Stop")
                                }
                            } else {
                                Label("Generate Text", systemImage: "sparkles")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: generationButtonHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(store.isGenerating ? .red : .accentColor)
                    .disabled(!store.isGenerating && store.beatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .frame(width: generationButtonWidth, alignment: .center)
                .padding(8)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            if !store.generationStatus.isEmpty {
                Text(store.generationStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

    private func maximumGenerationHeight(in totalHeight: CGFloat) -> CGFloat {
        max(generationPanelMinimumHeight, totalHeight - sceneEditorMinimumHeight - generationResizeHandleHeight)
    }

    private func resolvedGenerationHeight(maximum: CGFloat) -> CGFloat {
        let value = generationPanelHeight > 0 ? generationPanelHeight : generationPanelInitialHeight
        return clamp(value, min: generationPanelMinimumHeight, max: maximum)
    }

    private func generationResizeHandle(currentHeight: CGFloat, maximumHeight: CGFloat) -> some View {
        ZStack {
            Divider()

            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 44, height: 4)
        }
        .frame(height: generationResizeHandleHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartGenerationHeight == nil {
                        dragStartGenerationHeight = currentHeight
                        dragStartPointerY = value.startLocation.y
                    }

                    let baseHeight = dragStartGenerationHeight ?? currentHeight
                    let baseY = dragStartPointerY ?? value.startLocation.y
                    let delta = baseY - value.location.y
                    let proposed = baseHeight + delta
                    generationPanelHeight = clamp(proposed, min: generationPanelMinimumHeight, max: maximumHeight)
                }
                .onEnded { _ in
                    dragStartGenerationHeight = nil
                    dragStartPointerY = nil
                }
        )
    }

    private func clamp(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        guard upperBound >= lowerBound else { return lowerBound }
        return Swift.min(upperBound, Swift.max(lowerBound, value))
    }

    private func historyMenuTitle(_ value: String) -> String {
        let singleLine = value.replacingOccurrences(of: "\n", with: " ")
        return singleLine.count > 80 ? String(singleLine.prefix(80)) + "..." : singleLine
    }
}

private struct SceneContextSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery: String = ""

    private var selectedCount: Int {
        store.selectedSceneContextCompendiumIDs.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scene Context")
                        .font(.title3.weight(.semibold))
                    Text(sceneSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if selectedCount > 0 {
                    Button("Clear") {
                        store.clearCurrentSceneContextCompendiumSelection()
                    }
                }

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                TextField("Search compendium entries", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)

                Text("\(selectedCount) entr\(selectedCount == 1 ? "y" : "ies") selected for this scene")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(CompendiumCategory.allCases) { category in
                        let entries = filteredEntries(for: category)
                        if !entries.isEmpty {
                            GroupBox(category.label) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(entries) { entry in
                                        Toggle(isOn: isSelectedBinding(entryID: entry.id)) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(entryTitle(entry))
                                                    .lineLimit(1)
                                                if !entry.tags.isEmpty {
                                                    Text(entry.tags.joined(separator: ", "))
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }
                                        .toggleStyle(.checkbox)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    if hasNoVisibleEntries {
                        ContentUnavailableView(
                            "No Matching Entries",
                            systemImage: "books.vertical",
                            description: Text("No compendium entries match the current filter.")
                        )
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    private var sceneSubtitle: String {
        if let scene = store.selectedScene {
            let trimmed = scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmed.isEmpty ? "Untitled Scene" : trimmed
            return "Select context entries for \(title)"
        }
        return "Select context entries for the current scene"
    }

    private var hasNoVisibleEntries: Bool {
        CompendiumCategory.allCases.allSatisfy { filteredEntries(for: $0).isEmpty }
    }

    private func filteredEntries(for category: CompendiumCategory) -> [CompendiumEntry] {
        let entries = store.entries(in: category)
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }

        return entries.filter { entry in
            entry.title.lowercased().contains(query) ||
                entry.body.lowercased().contains(query) ||
                entry.tags.joined(separator: " ").lowercased().contains(query)
        }
    }

    private func isSelectedBinding(entryID: UUID) -> Binding<Bool> {
        Binding(
            get: { store.isCompendiumEntrySelectedForCurrentSceneContext(entryID) },
            set: { isSelected in
                let current = store.selectedSceneContextCompendiumIDs
                if isSelected {
                    if !current.contains(entryID) {
                        store.setCompendiumContextIDsForCurrentScene(current + [entryID])
                    }
                } else {
                    store.setCompendiumContextIDsForCurrentScene(current.filter { $0 != entryID })
                }
            }
        )
    }

    private func entryTitle(_ entry: CompendiumEntry) -> String {
        let trimmed = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Entry" : trimmed
    }
}

private struct GenerationPayloadPreviewSheet: View {
    let preview: AppStore.WorkshopPayloadPreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Payload Preview")
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 0)
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("Request") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Provider: \(preview.providerLabel)")
                            if let method = preview.method {
                                Text("Method: \(method)")
                            }
                            if let endpointURL = preview.endpointURL {
                                Text("Endpoint: \(endpointURL)")
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !preview.headers.isEmpty {
                        GroupBox("Headers") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(preview.headers.enumerated()), id: \.offset) { _, header in
                                    Text("\(header.name): \(header.value)")
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GroupBox("JSON Body") {
                        GenerationJSONSyntaxTextView(text: preview.bodyJSON)
                            .frame(minHeight: 360)
                    }

                    if !preview.notes.isEmpty {
                        GroupBox("Notes") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(preview.notes.enumerated()), id: \.offset) { _, note in
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 840, minHeight: 640)
    }
}

private struct GenerationJSONSyntaxTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textStorage?.setAttributedString(Self.highlightedJSON(text))

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(Self.highlightedJSON(text))
    }

    private static func highlightedJSON(_ json: String) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: (json as NSString).length)
        let attributed = NSMutableAttributedString(string: json)
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        attributed.addAttributes(
            [
                .foregroundColor: NSColor.labelColor,
                .font: font
            ],
            range: fullRange
        )

        applyRegex("\\\"(?:\\\\.|[^\\\"\\\\])*\\\"", color: NSColor.systemRed, to: attributed)
        applyRegex("\\\"(?:\\\\.|[^\\\"\\\\])*\\\"(?=\\s*:)", color: NSColor.systemBlue, to: attributed)
        applyRegex("\\b-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b", color: NSColor.systemOrange, to: attributed)
        applyRegex("\\b(?:true|false|null)\\b", color: NSColor.systemPurple, to: attributed)

        return attributed
    }

    private static func applyRegex(_ pattern: String, color: NSColor, to attributed: NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: attributed.length)
        regex.matches(in: attributed.string, options: [], range: range).forEach { match in
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

private struct BeatInputTextView: NSViewRepresentable {
    @Binding var text: String
    var onSend: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .lineBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.scrollerInsets = NSEdgeInsets()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textContainerInset = .zero
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.lineFragmentPadding = 0
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: text.count, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSend: onSend)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        private let onSend: () -> Void

        init(text: Binding<String>, onSend: @escaping () -> Void) {
            self._text = text
            self.onSend = onSend
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.command) {
                textView.insertText("\n", replacementRange: textView.selectedRange())
                return true
            }

            onSend()
            return true
        }
    }
}
