import SwiftUI
import AppKit

private struct SceneEditorRange: Equatable {
    let location: Int
    let length: Int

    init(range: NSRange) {
        self.location = range.location
        self.length = range.length
    }

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

private struct SceneEditorSelection: Equatable {
    var range: SceneEditorRange
    var text: String

    var hasSelection: Bool {
        range.length > 0 && !text.isEmpty
    }

    static let empty = SceneEditorSelection(range: SceneEditorRange(range: NSRange(location: 0, length: 0)), text: "")
}

private struct SceneEditorCommand: Equatable {
    enum FindDirection: Equatable {
        case forward
        case backward
    }

    enum Action: Equatable {
        case undo
        case redo
        case find(query: String, direction: FindDirection, caseSensitive: Bool)
        case selectRange(targetRange: SceneEditorRange)
        case toggleBoldface
        case toggleItalics
        case toggleUnderline
        case replaceSelection(rewrittenText: String, targetRange: SceneEditorRange, emphasizeWithItalics: Bool)
        case applyFont(family: String, size: Double)
        case applyTextColor(CodableRGBA?, targetRange: SceneEditorRange?)
        case applyTextBackgroundColor(CodableRGBA?, targetRange: SceneEditorRange?)
        case clearSelectionFormatting(targetRange: SceneEditorRange?)
        case applyAlignment(TextAlignmentOption)
        case openFontPanel
    }

    let id: UUID = UUID()
    let action: Action
}

private struct SceneHistorySheetRequest: Identifiable {
    let id: UUID
}

private struct SceneEditorFormatting: Equatable {
    var fontFamily: String
    var fontSize: Double
    var textColor: CodableRGBA?
    var textBackgroundColor: CodableRGBA?
    var hasMixedTextColor: Bool
    var hasMixedTextBackgroundColor: Bool
    var isBold: Bool
    var isItalic: Bool
    var isUnderline: Bool
    var textAlignment: TextAlignmentOption

    static let `default` = SceneEditorFormatting(
        fontFamily: "System",
        fontSize: 14,
        textColor: nil,
        textBackgroundColor: nil,
        hasMixedTextColor: false,
        hasMixedTextBackgroundColor: false,
        isBold: false,
        isItalic: false,
        isUnderline: false,
        textAlignment: .left
    )
}

private extension CodableRGBA {
    static let colorComponentScale: Double = 255.0
    static let colorComponentTolerance: Double = 0.5 / colorComponentScale
    static let defaultHighlight = CodableRGBA(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)

    static func from(nsColor: NSColor?) -> CodableRGBA? {
        guard let resolved = nsColor?.usingColorSpace(.deviceRGB) else { return nil }
        return CodableRGBA(
            red: quantize(Double(resolved.redComponent)),
            green: quantize(Double(resolved.greenComponent)),
            blue: quantize(Double(resolved.blueComponent)),
            alpha: quantize(Double(resolved.alphaComponent))
        )
    }

    static func from(color: Color) -> CodableRGBA? {
        from(nsColor: NSColor(color))
    }

    static func areClose(_ lhs: CodableRGBA?, _ rhs: CodableRGBA?) -> Bool {
        switch (lhs, rhs) {
        case let (left?, right?):
            return left.isClose(to: right)
        case (nil, nil):
            return true
        default:
            return false
        }
    }

    private static func quantize(_ component: Double) -> Double {
        let clamped = min(1.0, max(0.0, component))
        return (clamped * colorComponentScale).rounded() / colorComponentScale
    }

    func isClose(to other: CodableRGBA) -> Bool {
        abs(red - other.red) <= Self.colorComponentTolerance &&
        abs(green - other.green) <= Self.colorComponentTolerance &&
        abs(blue - other.blue) <= Self.colorComponentTolerance &&
        abs(alpha - other.alpha) <= Self.colorComponentTolerance
    }

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

private extension SceneEditorFormatting {
    func isEquivalent(to other: SceneEditorFormatting) -> Bool {
        fontFamily == other.fontFamily &&
        abs(fontSize - other.fontSize) <= 0.01 &&
        CodableRGBA.areClose(textColor, other.textColor) &&
        CodableRGBA.areClose(textBackgroundColor, other.textBackgroundColor) &&
        hasMixedTextColor == other.hasMixedTextColor &&
        hasMixedTextBackgroundColor == other.hasMixedTextBackgroundColor &&
        isBold == other.isBold &&
        isItalic == other.isItalic &&
        isUnderline == other.isUnderline &&
        textAlignment == other.textAlignment
    }
}

struct EditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingSceneContextSheet: Bool = false
    @State private var sceneHistorySheetRequest: SceneHistorySheetRequest?
    @State private var generationPayloadPreview: AppStore.WorkshopPayloadPreview?
    @State private var sceneEditorCommand: SceneEditorCommand?
    @State private var editorSelection: SceneEditorSelection = .empty
    @State private var editorFormatting: SceneEditorFormatting = .default
    @State private var isRewritingSelection: Bool = false
    @State private var rewriteTask: Task<Void, Never>?
    @State private var canUndoInSceneEditor: Bool = false
    @State private var canRedoInSceneEditor: Bool = false
    @State private var beatMentionQuery: MentionAutocompleteQuery?
    @State private var beatMentionSelectionIndex: Int = 0
    @State private var beatMentionQueryIdentity: String = ""
    @State private var beatMentionAnchor: CGPoint?
    @State private var isEditingSceneTitle: Bool = false
    @FocusState private var isSceneTitleFocused: Bool

    private let generationButtonWidth: CGFloat = 150
    private let generationButtonHeight: CGFloat = 30
    private let generationButtonSpacing: CGFloat = 8
    private let sceneEditorMinimumHeight: CGFloat = 220

    private var generationActionColumnContentHeight: CGFloat {
        (generationButtonHeight * 3) + (generationButtonSpacing * 2)
    }

    private var generationInputMinimumHeight: CGFloat {
        generationActionColumnContentHeight
    }

    private var generationPanelMinimumHeight: CGFloat {
        generationActionColumnContentHeight + 84
    }

    private var generationPanelInitialHeight: CGFloat {
        generationPanelMinimumHeight
    }

    private var beatHistory: [String] {
        store.beatInputHistory
    }

    private var selectedSceneContextCount: Int {
        store.selectedSceneContextTotalCount
    }

    private var beatMentionSuggestions: [MentionSuggestion] {
        guard let beatMentionQuery else { return [] }
        return store.mentionSuggestions(for: beatMentionQuery.trigger, query: beatMentionQuery.query)
    }

    private var sceneStats: String {
        let content = store.selectedScene?.content ?? ""
        let totalChars = content.count
        let totalWords = wordCount(content)
        if editorSelection.hasSelection {
            let selChars = editorSelection.text.count
            let selWords = wordCount(editorSelection.text)
            return "\(selWords) / \(totalWords) words, \(selChars) / \(totalChars) chars"
        }
        return "\(totalWords) words, \(totalChars) chars"
    }

    private func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    private var sceneTitleBinding: Binding<String> {
        Binding(
            get: { store.selectedScene?.title ?? "" },
            set: { store.updateSelectedSceneTitle($0) }
        )
    }

    private var isRewriteMode: Bool {
        editorSelection.hasSelection || isRewritingSelection
    }

    private var activeGenerationPromptBinding: Binding<UUID?> {
        Binding(
            get: {
                if isRewriteMode {
                    return store.project.selectedRewritePromptID
                }
                return store.project.selectedProsePromptID
            },
            set: { id in
                if isRewriteMode {
                    store.setSelectedRewritePrompt(id)
                } else {
                    store.setSelectedProsePrompt(id)
                }
            }
        )
    }

    private var activeGenerationPrompts: [PromptTemplate] {
        isRewriteMode ? store.rewritePrompts : store.prosePrompts
    }

    private var isPrimaryGenerationRunning: Bool {
        if isRewriteMode {
            return isRewritingSelection
        }
        return store.isGenerating
    }

    private var canPreviewCurrentPayload: Bool {
        if isRewriteMode {
            return editorSelection.hasSelection && !isRewritingSelection && !store.isGenerating
        }
        return !store.isGenerating
    }

    private var canRunPrimaryAction: Bool {
        if isRewriteMode {
            if isRewritingSelection {
                return true
            }
            return editorSelection.hasSelection && store.activeRewritePrompt != nil && !store.isGenerating
        }
        return true
    }

    private var editorToolbarFontFamily: String {
        SceneFontSelectorData.normalizedFamily(editorFormatting.fontFamily)
    }

    private var editorToolbarFontSize: Double {
        let size = editorFormatting.fontSize
        return size > 0 ? size : 14
    }

    private var proseGenerationReviewPresented: Binding<Bool> {
        Binding(
            get: { store.proseGenerationReview != nil },
            set: { isPresented in
                if !isPresented {
                    store.dismissProseGenerationReview()
                }
            }
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
        .sheet(item: $sceneHistorySheetRequest) { request in
            SceneHistorySheet(sceneID: request.id)
                .environmentObject(store)
        }
        .sheet(isPresented: proseGenerationReviewPresented) {
            ProseGenerationReviewSheet()
                .environmentObject(store)
        }
        .onChange(of: store.pendingSceneSearchSelection?.requestID) { _, requestID in
            guard requestID != nil else { return }
            applyPendingSceneSearchSelectionIfNeeded()
        }
        .onChange(of: store.selectedSceneID) { _, _ in
            isEditingSceneTitle = false
            applyPendingSceneSearchSelectionIfNeeded()
        }
        .onChange(of: store.sceneHistorySheetRequestID) { _, _ in
            presentSceneHistoryIfRequested()
        }
        .onAppear {
            applyPendingSceneSearchSelectionIfNeeded()
            presentSceneHistoryIfRequested()
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
            HStack(alignment: .center, spacing: 8) {
                if isEditingSceneTitle {
                    TextField("Scene title", text: sceneTitleBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focused($isSceneTitleFocused)
                        .onSubmit { isEditingSceneTitle = false }
                        .onExitCommand { isEditingSceneTitle = false }
                        .onChange(of: isSceneTitleFocused) { _, focused in
                            if !focused { isEditingSceneTitle = false }
                        }
                } else {
                    Text(store.selectedScene?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                         ? store.selectedScene!.title : "Untitled Scene")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            isEditingSceneTitle = true
                            DispatchQueue.main.async { isSceneTitleFocused = true }
                        }
                }

                Button {
                    store.requestSceneHistory()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(4)
                .help("Scene History")
                .disabled(store.selectedScene == nil)
            }

            // Formatting toolbar
            HStack(spacing: 4) {
                Button { sceneEditorCommand = SceneEditorCommand(action: .undo) } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(4)
                .disabled(!canUndoInSceneEditor)
                .help("Undo (Cmd+Z)")

                Button { sceneEditorCommand = SceneEditorCommand(action: .redo) } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(4)
                .disabled(!canRedoInSceneEditor)
                .help("Redo (Shift+Cmd+Z)")

                FontFamilyDropdown(
                    selectedFamily: editorToolbarFontFamily,
                    previewPointSize: CGFloat(editorToolbarFontSize),
                    controlSize: .small,
                    onSelectFamily: { family in
                        applyEditorToolbarFont(
                            family: family,
                            size: editorToolbarFontSize
                        )
                    },
                    onOpenSystemFontPanel: {
                        sceneEditorCommand = SceneEditorCommand(action: .openFontPanel)
                    }
                )
                .frame(width: 140, alignment: .leading)
                .controlSize(.small)
                .help("Font family")

                FontSizeDropdown(
                    selectedSize: editorToolbarFontSize,
                    controlSize: .small,
                    onSelectSize: { size in
                        applyEditorToolbarFont(
                            family: editorToolbarFontFamily,
                            size: size
                        )
                    }
                )
                .frame(width: 58, alignment: .leading)
                .controlSize(.small)
                .help("Font size")

                Button { sceneEditorCommand = SceneEditorCommand(action: .toggleBoldface) } label: {
                    Image(systemName: "bold")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(editorFormatting.isBold ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .help("Bold (Cmd+B)")

                Button { sceneEditorCommand = SceneEditorCommand(action: .toggleItalics) } label: {
                    Image(systemName: "italic")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(editorFormatting.isItalic ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .help("Italic (Cmd+I)")

                Button { sceneEditorCommand = SceneEditorCommand(action: .toggleUnderline) } label: {
                    Image(systemName: "underline")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(editorFormatting.isUnderline ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .help("Underline (Cmd+U)")

                Button {
                    sceneEditorCommand = SceneEditorCommand(action: .clearSelectionFormatting(
                        targetRange: editorSelection.hasSelection ? editorSelection.range : nil
                    ))
                } label: {
                    Image(systemName: "eraser")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(4)
                .disabled(!editorSelection.hasSelection)
                .help("Clear explicit formatting from selected text")

                Picker("Alignment", selection: Binding(
                    get: { editorFormatting.textAlignment },
                    set: { alignment in
                        editorFormatting.textAlignment = alignment
                        sceneEditorCommand = SceneEditorCommand(action: .applyAlignment(alignment))
                    }
                )) {
                    Image(systemName: "text.alignleft").tag(TextAlignmentOption.left)
                    Image(systemName: "text.aligncenter").tag(TextAlignmentOption.center)
                    Image(systemName: "text.alignright").tag(TextAlignmentOption.right)
                    Image(systemName: "text.justify").tag(TextAlignmentOption.justified)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 48)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Text alignment")

                HStack(spacing: 4) {
                    Text("A")
                        .font(.system(size: 11, weight: .semibold))
                    AppKitColorWell(
                        selection: Binding(
                            get: {
                                if editorFormatting.hasMixedTextColor && editorSelection.hasSelection {
                                    return nil
                                }
                                if let color = editorFormatting.textColor {
                                    return color
                                }
                                return CodableRGBA.from(nsColor: .textColor)
                                    ?? CodableRGBA(red: 0, green: 0, blue: 0, alpha: 1)
                            },
                            set: { rgba in
                                guard let rgba else { return }
                                let shouldSkip = CodableRGBA.areClose(editorFormatting.textColor, rgba) && !editorSelection.hasSelection
                                guard !shouldSkip else { return }
                                editorFormatting.textColor = rgba
                                editorFormatting.hasMixedTextColor = false
                                sceneEditorCommand = SceneEditorCommand(action: .applyTextColor(
                                    rgba,
                                    targetRange: editorSelection.hasSelection ? editorSelection.range : nil
                                ))
                            }
                        ),
                        supportsOpacity: false,
                        autoDeactivateOnChange: true,
                        isMixedSelection: editorFormatting.hasMixedTextColor,
                        mixedPlaceholderColor: NSColor.secondaryLabelColor
                    )
                    .frame(width: 36, height: 16)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .id("editor-text-color-well")
                }
                .help("Text color")

                HStack(spacing: 4) {
                    Image(systemName: "highlighter")
                        .font(.system(size: 12))
                    AppKitColorWell(
                        selection: Binding(
                            get: {
                                if editorFormatting.hasMixedTextBackgroundColor && editorSelection.hasSelection {
                                    return nil
                                }
                                if let color = editorFormatting.textBackgroundColor {
                                    return color
                                }
                                return .defaultHighlight
                            },
                            set: { rgba in
                                guard let rgba else { return }
                                let shouldSkip = CodableRGBA.areClose(editorFormatting.textBackgroundColor, rgba) && !editorSelection.hasSelection
                                guard !shouldSkip else { return }
                                editorFormatting.textBackgroundColor = rgba
                                editorFormatting.hasMixedTextBackgroundColor = false
                                sceneEditorCommand = SceneEditorCommand(action: .applyTextBackgroundColor(
                                    rgba,
                                    targetRange: editorSelection.hasSelection ? editorSelection.range : nil
                                ))
                            }
                        ),
                        supportsOpacity: false,
                        autoDeactivateOnChange: true,
                        isMixedSelection: editorFormatting.hasMixedTextBackgroundColor,
                        mixedPlaceholderColor: NSColor.secondaryLabelColor
                    )
                    .frame(width: 36, height: 16)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .id("editor-highlight-color-well")
                }
                .help("Text highlight color")

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .padding(.bottom, -10)
    }

    private var writingSplit: some View {
        VSplitView {
            sceneEditor
                .frame(minHeight: sceneEditorMinimumHeight, maxHeight: .infinity)
                .layoutPriority(1)

            generationPanel
                .frame(minHeight: generationPanelMinimumHeight, idealHeight: generationPanelInitialHeight, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sceneEditor: some View {
        SceneRichTextEditorView(
            sceneID: store.selectedScene?.id,
            plainText: store.selectedScene?.content ?? "",
            richTextData: store.selectedScene?.contentRTFData,
            contentRefreshID: store.sceneRichTextRefreshID,
            focusRequestID: store.sceneEditorFocusRequestID,
            command: sceneEditorCommand,
            shouldAutoScrollExternalUpdates: store.isGenerating,
            incrementalRewriteSessionActive: isRewritingSelection && store.incrementalRewrite,
            editorAppearance: store.project.editorAppearance,
            onSelectionChange: { selection in
                editorSelection = selection
            },
            onFormattingChange: { formatting in
                guard !editorFormatting.isEquivalent(to: formatting) else { return }
                editorFormatting = formatting
            },
            onUndoRedoAvailabilityChange: { canUndo, canRedo in
                canUndoInSceneEditor = canUndo
                canRedoInSceneEditor = canRedo
            },
            onFindResult: { _ in }
        ) { plainText, richTextData in
            store.updateSelectedSceneContent(plainText, richTextData: richTextData)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var generationPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(sceneStats)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: 8) {
                    if !store.generationStatus.isEmpty {
                        Text(store.generationStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let usage = store.inlineProseUsage {
                        proseUsageMetricsView(usage)
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)

            HStack {
                Picker(isRewriteMode ? "Rewrite Prompt" : "Prompt Template", selection: activeGenerationPromptBinding) {
                    if !isRewriteMode {
                        Text("Default")
                            .tag(Optional<UUID>.none)
                    }
                    ForEach(activeGenerationPrompts) { prompt in
                        Text(prompt.title)
                            .tag(Optional(prompt.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 280)
                .padding(.leading, 8)

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
                .controlSize(.regular)
                .padding(.trailing, 8)
            }

            HStack(alignment: .top, spacing: 10) {
                BeatInputTextView(
                    text: $store.beatInput,
                    onSend: runPrimaryGenerationAction,
                    onMentionQueryChange: handleBeatMentionQueryChange,
                    onMentionAnchorChange: handleBeatMentionAnchorChange,
                    isMentionMenuVisible: !beatMentionSuggestions.isEmpty,
                    onMentionMove: moveBeatMentionSelection,
                    onMentionSelect: confirmBeatMentionSelection,
                    onMentionDismiss: dismissBeatMentionSuggestions,
                    focusRequestID: store.beatInputFocusRequestID
                )
                .frame(minHeight: generationInputMinimumHeight, idealHeight: generationInputMinimumHeight, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    GeometryReader { proxy in
                        if !beatMentionSuggestions.isEmpty, let anchor = beatMentionAnchor {
                            let menuWidth = min(420, max(220, proxy.size.width - 16))
                            let maxX = max(8, proxy.size.width - menuWidth - 8)
                            let x = min(max(8, anchor.x + 4), maxX)
                            let belowY = anchor.y + 8
                            let availableBelow = proxy.size.height - belowY - 8
                            let availableAbove = anchor.y - 8
                            let showBelow = availableBelow >= 80 || availableBelow >= availableAbove
                            let availableHeight = max(60, showBelow ? availableBelow : availableAbove)
                            let y = showBelow
                                ? max(8, belowY)
                                : max(8, anchor.y - availableHeight - 2)

                            MentionAutocompleteListView(
                                suggestions: beatMentionSuggestions,
                                selectedIndex: beatMentionSelectionIndex,
                                availableHeight: availableHeight,
                                onHighlight: { beatMentionSelectionIndex = $0 },
                                onSelect: applyBeatMentionSuggestion
                            )
                            .frame(width: menuWidth)
                            .offset(x: x, y: y)
                            .zIndex(10)
                        }
                    }
                }
                .padding(.leading, 8)
                .frame(minHeight: generationInputMinimumHeight, idealHeight: generationInputMinimumHeight, maxHeight: .infinity, alignment: .top)

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
                        previewCurrentGenerationPayload()
                    } label: {
                        Label("Preview", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(!canPreviewCurrentPayload)

                    Button {
                        runPrimaryGenerationAction()
                    } label: {
                        Group {
                            if isPrimaryGenerationRunning {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Stop")
                                }
                            } else if isRewriteMode {
                                Label("Rewrite", systemImage: "text.redaction")
                            } else {
                                Label("Generate Text", systemImage: "sparkles")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: generationButtonHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isPrimaryGenerationRunning ? .red : .accentColor)
                    .disabled(!canRunPrimaryAction)
                }
                .frame(width: generationButtonWidth, alignment: .center)
                .padding(8)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Text(
                isRewriteMode
                    ? "Selection is active: prompt, preview, and action buttons now target rewrite for the selected text."
                    : "Press Enter to send. Press Cmd+Enter for a newline. Use @ for compendium entries, # for scenes."
            )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func historyMenuTitle(_ value: String) -> String {
        let singleLine = value.replacingOccurrences(of: "\n", with: " ")
        return singleLine.count > 80 ? String(singleLine.prefix(80)) + "..." : singleLine
    }

    private func applyEditorToolbarFont(family: String, size: Double) {
        let normalizedFamily = SceneFontSelectorData.normalizedFamily(family)
        let normalizedSize = max(1, size)
        editorFormatting.fontFamily = normalizedFamily
        editorFormatting.fontSize = normalizedSize
        sceneEditorCommand = SceneEditorCommand(
            action: .applyFont(family: normalizedFamily, size: normalizedSize)
        )
    }

    private func runPrimaryGenerationAction() {
        if isRewriteMode {
            if isRewritingSelection {
                cancelRewriteSelection()
            } else {
                rewriteSelectedText()
            }
            return
        }

        if store.isGenerating {
            store.cancelBeatGeneration()
        } else {
            store.submitBeatGeneration()
        }
    }

    private func previewCurrentGenerationPayload() {
        do {
            if isRewriteMode {
                generationPayloadPreview = try store.makeRewritePayloadPreview(selectedText: editorSelection.text)
            } else {
                generationPayloadPreview = try store.makeProsePayloadPreview()
            }
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func proseUsageMetricsView(_ usage: TokenUsage) -> some View {
        HStack(spacing: 8) {
            if let promptTokens = usage.promptTokens {
                proseUsageMetric(
                    icon: "text.quote",
                    value: promptTokens,
                    help: "Prompt tokens sent to the model."
                )
            }

            if let completionTokens = usage.completionTokens {
                proseUsageMetric(
                    icon: "sparkles",
                    value: completionTokens,
                    help: "Completion tokens generated by the model."
                )
            }

            if let totalTokens = usage.totalTokens {
                proseUsageMetric(
                    icon: "sum",
                    value: totalTokens,
                    help: "Total prompt + completion tokens."
                )
            }

            if usage.isEstimated {
                Image(systemName: "questionmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Token counts are estimated because provider usage was unavailable.")
            }
        }
    }

    private func proseUsageMetric(icon: String, value: Int, help: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(value)")
                .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private func applyBeatMentionSuggestion(_ suggestion: MentionSuggestion) {
        guard let beatMentionQuery else { return }
        guard let updated = MentionParsing.replacingToken(
            in: store.beatInput,
            range: beatMentionQuery.tokenRange,
            with: suggestion.insertion
        ) else {
            return
        }
        store.beatInput = updated
        self.beatMentionQuery = nil
        self.beatMentionAnchor = nil
    }

    private func moveBeatMentionSelection(_ delta: Int) {
        guard !beatMentionSuggestions.isEmpty else { return }
        let maxIndex = beatMentionSuggestions.count - 1
        let next = beatMentionSelectionIndex + delta
        beatMentionSelectionIndex = min(max(next, 0), maxIndex)
    }

    private func confirmBeatMentionSelection() -> Bool {
        guard !beatMentionSuggestions.isEmpty else { return false }
        let index = min(max(beatMentionSelectionIndex, 0), beatMentionSuggestions.count - 1)
        applyBeatMentionSuggestion(beatMentionSuggestions[index])
        return true
    }

    private func dismissBeatMentionSuggestions() {
        beatMentionQuery = nil
        beatMentionSelectionIndex = 0
        beatMentionQueryIdentity = ""
        beatMentionAnchor = nil
    }

    private func handleBeatMentionQueryChange(_ query: MentionAutocompleteQuery?) {
        beatMentionQuery = query
        let identity = query.map { mention in
            "\(mention.trigger.rawValue)|\(mention.query)|\(mention.tokenRange.location)|\(mention.tokenRange.length)"
        } ?? ""

        if identity != beatMentionQueryIdentity {
            beatMentionSelectionIndex = 0
            beatMentionQueryIdentity = identity
        }

        if query == nil {
            beatMentionAnchor = nil
        }
    }

    private func handleBeatMentionAnchorChange(_ anchor: CGPoint?) {
        beatMentionAnchor = anchor
    }

    private func applyPendingSceneSearchSelectionIfNeeded() {
        guard let pending = store.pendingSceneSearchSelection else { return }
        guard store.selectedSceneID == pending.sceneID else { return }

        let targetRange = SceneEditorRange(
            range: NSRange(location: pending.location, length: pending.length)
        )
        sceneEditorCommand = SceneEditorCommand(action: .selectRange(targetRange: targetRange))
        store.consumeSceneSearchSelectionRequest(pending.requestID)
    }

    private func presentSceneHistoryIfRequested() {
        guard let sceneID = store.requestedSceneHistorySceneID else { return }
        sceneHistorySheetRequest = SceneHistorySheetRequest(id: sceneID)
        store.consumeSceneHistoryRequest()
    }

    private func rewriteSelectedText() {
        guard !isRewritingSelection else { return }
        let selectionSnapshot = editorSelection
        guard selectionSnapshot.hasSelection else { return }
        let emphasizeWithItalics = store.markRewrittenTextAsItalics
        let incrementalRewrite = store.incrementalRewrite
        var liveTargetRange = selectionSnapshot.range
        var lastAppliedPartial = ""

        isRewritingSelection = true
        rewriteTask = Task { @MainActor in
            defer {
                isRewritingSelection = false
                rewriteTask = nil
            }

            let partialHandler: (@MainActor (String) -> Void)?
            if incrementalRewrite {
                partialHandler = { partial in
                    let normalized = partial.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !normalized.isEmpty else { return }
                    guard normalized != lastAppliedPartial else { return }
                    lastAppliedPartial = normalized

                    sceneEditorCommand = SceneEditorCommand(
                        action: .replaceSelection(
                            rewrittenText: normalized,
                            targetRange: liveTargetRange,
                            emphasizeWithItalics: emphasizeWithItalics
                        )
                    )
                    liveTargetRange = SceneEditorRange(
                        range: NSRange(location: liveTargetRange.location, length: (normalized as NSString).length)
                    )
                }
            } else {
                partialHandler = nil
            }

            do {
                let rewritten = try await store.rewriteSelectedSceneText(
                    selectionSnapshot.text,
                    onPartial: partialHandler
                )
                sceneEditorCommand = SceneEditorCommand(
                    action: .replaceSelection(
                        rewrittenText: rewritten,
                        targetRange: incrementalRewrite ? liveTargetRange : selectionSnapshot.range,
                        emphasizeWithItalics: emphasizeWithItalics
                    )
                )
            } catch is CancellationError {
                return
            } catch {
                store.lastError = error.localizedDescription
            }
        }
    }

    private func cancelRewriteSelection() {
        rewriteTask?.cancel()
    }
}

private struct SceneRichTextEditorView: NSViewRepresentable {
    let sceneID: UUID?
    let plainText: String
    let richTextData: Data?
    let contentRefreshID: UUID
    let focusRequestID: UUID
    let command: SceneEditorCommand?
    let shouldAutoScrollExternalUpdates: Bool
    let incrementalRewriteSessionActive: Bool
    let editorAppearance: EditorAppearanceSettings
    let onSelectionChange: (SceneEditorSelection) -> Void
    let onFormattingChange: (SceneEditorFormatting) -> Void
    let onUndoRedoAvailabilityChange: (Bool, Bool) -> Void
    let onFindResult: (Bool) -> Void
    let onChange: (String, Data?) -> Void

    private final class SceneEditorTextView: NSTextView {
        var onFormattingShortcut: ((SceneEditorCommand.Action) -> Void)?
        var onFontPanelChange: (() -> Void)?

        // Ignore generic NSColorPanel responder-chain changes. Formatting
        // colors are applied explicitly through SceneEditorCommand actions.
        override func changeColor(_ sender: Any?) {}

        override func changeFont(_ sender: Any?) {
            super.changeFont(sender)
            onFontPanelChange?()
        }

        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.command],
               let shortcut = event.charactersIgnoringModifiers?.lowercased() {
                switch shortcut {
                case "b":
                    onFormattingShortcut?(.toggleBoldface)
                    return
                case "i":
                    onFormattingShortcut?(.toggleItalics)
                    return
                case "u":
                    onFormattingShortcut?(.toggleUnderline)
                    return
                default:
                    break
                }
            }
            super.keyDown(with: event)
        }

        /// Paste sanitized content: keeps bold/italic/underline traits from the
        /// source but discards all other formatting (font family, size, color, etc.),
        /// inheriting those from the editor's current typing attributes instead.
        override func paste(_ sender: Any?) {
            let pb = NSPasteboard.general
            let baseAttrs = typingAttributes
            let baseFont = baseAttrs[.font] as? NSFont ?? NSFont.preferredFont(forTextStyle: .body)

            // Try RTF so we can preserve bold/italic/underline traits.
            var sourceAttributed: NSAttributedString?
            if let data = pb.data(forType: .rtf) {
                sourceAttributed = try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
            } else if let data = pb.data(forType: NSPasteboard.PasteboardType("NeXT Rich Text Format v1.0 pasteboard type")) {
                sourceAttributed = try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
            }

            let plainText: String
            if let src = sourceAttributed {
                plainText = src.string
            } else if let str = pb.string(forType: .string) {
                plainText = str
            } else {
                super.paste(sender)
                return
            }

            let result = NSMutableAttributedString(string: plainText, attributes: baseAttrs)

            if let src = sourceAttributed {
                src.enumerateAttributes(in: NSRange(location: 0, length: src.length), options: []) { attrs, range, _ in
                    // Preserve underline.
                    if let underline = attrs[.underlineStyle] {
                        result.addAttribute(.underlineStyle, value: underline, range: range)
                    }
                    // Preserve bold/italic traits by re-deriving from the base editor font.
                    if let srcFont = attrs[.font] as? NSFont {
                        let traits = NSFontManager.shared.traits(of: srcFont)
                        var derivedFont = baseFont
                        if traits.contains(.boldFontMask) {
                            derivedFont = NSFontManager.shared.convert(derivedFont, toHaveTrait: .boldFontMask)
                        }
                        if traits.contains(.italicFontMask) {
                            derivedFont = NSFontManager.shared.convert(derivedFont, toHaveTrait: .italicFontMask)
                        }
                        if derivedFont !== baseFont {
                            result.addAttribute(.font, value: derivedFont, range: range)
                        }
                    }
                }
            }

            let selectedRange = self.selectedRange()
            if shouldChangeText(in: selectedRange, replacementString: result.string) {
                textStorage?.replaceCharacters(in: selectedRange, with: result)
                didChangeText()
                setSelectedRange(NSRange(location: selectedRange.location + result.length, length: 0))
            }
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.scrollerInsets = NSEdgeInsets()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        let textView = SceneEditorTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.allowsUndo = true
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.onFormattingShortcut = { action in
            context.coordinator.applyFormattingShortcut(action, to: textView)
        }
        textView.onFontPanelChange = {
            context.coordinator.handleFontPanelChange(in: textView)
        }

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.lineFragmentPadding = 0
        }

        context.coordinator.applyContent(
            to: textView,
            sceneID: sceneID,
            plainText: plainText,
            richTextData: richTextData,
            contentRefreshID: contentRefreshID,
            pendingCommand: command,
            shouldAutoScrollExternalUpdates: shouldAutoScrollExternalUpdates,
            incrementalRewriteSessionActive: incrementalRewriteSessionActive,
            force: true
        )
        context.coordinator.applyAppearanceIfNeeded(
            editorAppearance,
            sceneID: sceneID,
            to: textView,
            scrollView: scrollView
        )

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.applyContent(
            to: textView,
            sceneID: sceneID,
            plainText: plainText,
            richTextData: richTextData,
            contentRefreshID: contentRefreshID,
            pendingCommand: command,
            shouldAutoScrollExternalUpdates: shouldAutoScrollExternalUpdates,
            incrementalRewriteSessionActive: incrementalRewriteSessionActive,
            force: false
        )
        context.coordinator.applyCommand(command, to: textView)
        context.coordinator.applyAppearanceIfNeeded(
            editorAppearance,
            sceneID: sceneID,
            to: textView,
            scrollView: nsView
        )
        context.coordinator.requestFocusIfNeeded(
            requestID: focusRequestID,
            textView: textView
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSelectionChange: onSelectionChange,
            onFormattingChange: onFormattingChange,
            onUndoRedoAvailabilityChange: onUndoRedoAvailabilityChange,
            onFindResult: onFindResult,
            onChange: onChange
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let onSelectionChange: (SceneEditorSelection) -> Void
        private let onFormattingChange: (SceneEditorFormatting) -> Void
        private let onUndoRedoAvailabilityChange: (Bool, Bool) -> Void
        private let onFindResult: (Bool) -> Void
        private let onChange: (String, Data?) -> Void
        private var isApplyingProgrammaticChange: Bool = false
        private var lastSceneID: UUID?
        private var lastAppliedContentRefreshID: UUID?
        private var lastHandledCommandID: UUID?
        private var lastAppliedAppearance: EditorAppearanceSettings?
        private var lastAppliedAppearanceSceneID: UUID?
        private var appearanceEverApplied: Bool = false
        private var undoGroupingDepth: Int = 0
        private var generationUndoSessionActive: Bool = false
        private var rewriteUndoSessionActive: Bool = false
        private var lastGenerationStreamingState: Bool = false
        private var lastIncrementalRewriteState: Bool = false
        var lastFocusRequestID: UUID = UUID()
        private var pendingFocusRequestID: UUID?
        init(
            onSelectionChange: @escaping (SceneEditorSelection) -> Void,
            onFormattingChange: @escaping (SceneEditorFormatting) -> Void,
            onUndoRedoAvailabilityChange: @escaping (Bool, Bool) -> Void,
            onFindResult: @escaping (Bool) -> Void,
            onChange: @escaping (String, Data?) -> Void
        ) {
            self.onSelectionChange = onSelectionChange
            self.onFormattingChange = onFormattingChange
            self.onUndoRedoAvailabilityChange = onUndoRedoAvailabilityChange
            self.onFindResult = onFindResult
            self.onChange = onChange
        }

        func applyContent(
            to textView: NSTextView,
            sceneID: UUID?,
            plainText: String,
            richTextData: Data?,
            contentRefreshID: UUID,
            pendingCommand: SceneEditorCommand?,
            shouldAutoScrollExternalUpdates: Bool,
            incrementalRewriteSessionActive: Bool,
            force: Bool
        ) {
            if isApplyingProgrammaticChange {
                return
            }

            let sceneChanged = lastSceneID != sceneID
            let hasPendingRewriteReplaceCommand: Bool
            if let pendingCommand, lastHandledCommandID != pendingCommand.id {
                if case .replaceSelection = pendingCommand.action {
                    hasPendingRewriteReplaceCommand = true
                } else {
                    hasPendingRewriteReplaceCommand = false
                }
            } else {
                hasPendingRewriteReplaceCommand = false
            }
            updateUndoGroupingState(
                for: textView,
                sceneChanged: sceneChanged,
                generationStreamingActive: shouldAutoScrollExternalUpdates,
                incrementalRewriteActive: incrementalRewriteSessionActive,
                hasPendingRewriteReplaceCommand: hasPendingRewriteReplaceCommand
            )

            let textChanged = textView.string != plainText
            let refreshRequested = lastAppliedContentRefreshID != contentRefreshID
            guard force || sceneChanged || textChanged || refreshRequested else {
                return
            }

            isApplyingProgrammaticChange = true
            if force || sceneChanged || refreshRequested {
                let previousSelection = clampedRangeForStorage(textView.selectedRange(), textView: textView)
                let attributed = Self.makeAttributedContent(plainText: plainText, richTextData: richTextData)
                textView.textStorage?.setAttributedString(attributed)
                if force || sceneChanged {
                    textView.setSelectedRange(NSRange(location: attributed.length, length: 0))
                } else {
                    let restoredSelection = clampedRangeForStorage(previousSelection, textView: textView)
                    textView.setSelectedRange(restoredSelection)
                }
            } else if textChanged {
                let scrollView = textView.enclosingScrollView
                let previousOrigin = scrollView?.contentView.bounds.origin
                let wasAtBottom = scrollView.map(isAtBottom(_:)) ?? false
                let shouldScrollToBottom = shouldAutoScrollExternalUpdates && wasAtBottom

                applyExternalTextDelta(
                    to: textView,
                    newText: plainText,
                    moveCaretToEnd: shouldScrollToBottom
                )

                if let scrollView {
                    if shouldScrollToBottom {
                        scrollToBottom(scrollView)
                    } else if let previousOrigin {
                        restoreScrollOrigin(scrollView, previousOrigin)
                    }
                }
            }
            isApplyingProgrammaticChange = false
            lastSceneID = sceneID
            lastAppliedContentRefreshID = contentRefreshID
            publishSelection(from: textView)
            publishUndoRedoState(from: textView)
        }

        private func updateUndoGroupingState(
            for textView: NSTextView,
            sceneChanged: Bool,
            generationStreamingActive: Bool,
            incrementalRewriteActive: Bool,
            hasPendingRewriteReplaceCommand: Bool
        ) {
            if sceneChanged {
                if rewriteUndoSessionActive {
                    endUndoGrouping(in: textView)
                    rewriteUndoSessionActive = false
                }
                if generationUndoSessionActive {
                    endUndoGrouping(in: textView)
                    generationUndoSessionActive = false
                }
                lastGenerationStreamingState = false
                lastIncrementalRewriteState = false
            }

            if generationStreamingActive {
                if !lastGenerationStreamingState {
                    beginUndoGrouping(actionName: "Generate Text", in: textView)
                    generationUndoSessionActive = true
                }
                lastGenerationStreamingState = true
            } else if lastGenerationStreamingState {
                if generationUndoSessionActive {
                    endUndoGrouping(in: textView)
                    generationUndoSessionActive = false
                }
                lastGenerationStreamingState = false
            }

            if incrementalRewriteActive {
                if !lastIncrementalRewriteState {
                    beginUndoGrouping(actionName: "Rewrite Selection", in: textView)
                    rewriteUndoSessionActive = true
                }
                lastIncrementalRewriteState = true
            } else if lastIncrementalRewriteState {
                if rewriteUndoSessionActive && hasPendingRewriteReplaceCommand {
                    return
                }
                if rewriteUndoSessionActive {
                    endUndoGrouping(in: textView)
                    rewriteUndoSessionActive = false
                }
                lastIncrementalRewriteState = false
            }
        }

        private func beginUndoGrouping(actionName: String, in textView: NSTextView) {
            guard let undoManager = textView.undoManager else { return }
            undoManager.beginUndoGrouping()
            undoGroupingDepth += 1
            if !actionName.isEmpty {
                undoManager.setActionName(actionName)
            }
        }

        private func endUndoGrouping(in textView: NSTextView) {
            guard undoGroupingDepth > 0 else { return }
            defer { undoGroupingDepth -= 1 }
            guard let undoManager = textView.undoManager else { return }
            undoManager.endUndoGrouping()
        }

        func requestFocusIfNeeded(requestID: UUID, textView: NSTextView) {
            if lastFocusRequestID == requestID, pendingFocusRequestID == nil {
                return
            }
            pendingFocusRequestID = requestID
            attemptFocus(on: textView)
        }

        private func attemptFocus(on textView: NSTextView, remainingAttempts: Int = 6) {
            guard let pendingID = pendingFocusRequestID else { return }
            guard remainingAttempts > 0 else { return }
            guard let window = textView.window else {
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    self.attemptFocus(on: textView, remainingAttempts: remainingAttempts - 1)
                }
                return
            }

            window.makeFirstResponder(textView)
            if window.firstResponder as AnyObject? === textView {
                lastFocusRequestID = pendingID
                pendingFocusRequestID = nil
                return
            }

            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.attemptFocus(on: textView, remainingAttempts: remainingAttempts - 1)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticChange else { return }
            guard let textView = notification.object as? NSTextView else { return }
            publishChange(from: textView)
            publishSelection(from: textView)
            publishUndoRedoState(from: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingProgrammaticChange else { return }
            guard let textView = notification.object as? NSTextView else { return }
            publishSelection(from: textView)
            publishFormatting(from: textView)
        }

        func applyCommand(_ command: SceneEditorCommand?, to textView: NSTextView) {
            guard let command else { return }
            guard lastHandledCommandID != command.id else { return }

            lastHandledCommandID = command.id
            var didMutateText = false
            var isInlineFormatting = false
            var shouldFocusTextView = true
            var shouldResignTextViewForBackgroundColor = false

            // For inline formatting commands, suppress delegate callbacks
            // BEFORE making the text view first responder, because
            // makeFirstResponder triggers textViewDidChangeSelection which
            // would call publishFormatting with stale attribute values,
            // resetting editorFormatting and causing a feedback loop with
            // ColorPicker bindings.
            switch command.action {
            case .applyFont, .applyTextColor, .applyTextBackgroundColor, .applyAlignment, .clearSelectionFormatting:
                isInlineFormatting = true
                isApplyingProgrammaticChange = true
            default:
                break
            }

            // Color-well actions are command-driven and should not steal focus
            // from NSColorWell; doing so can cause the color to bounce through
            // responder-chain updates.
            switch command.action {
            case .applyTextColor, .applyTextBackgroundColor:
                shouldFocusTextView = false
            default:
                break
            }

            switch command.action {
            case .applyTextBackgroundColor:
                shouldResignTextViewForBackgroundColor = true
            default:
                break
            }

            if shouldFocusTextView {
                textView.window?.makeFirstResponder(textView)
            } else if shouldResignTextViewForBackgroundColor,
                      textView.window?.firstResponder as AnyObject? === textView {
                // Background color uses NSColorWell + shared NSColorPanel. If
                // NSTextView remains first responder, AppKit can push the
                // text foreground color back through the panel, producing a
                // second spurious background callback.
                textView.window?.makeFirstResponder(nil)
            }

            switch command.action {
            case .undo:
                textView.undoManager?.undo()
                didMutateText = true
            case .redo:
                textView.undoManager?.redo()
                didMutateText = true
            case let .find(query, direction, caseSensitive):
                let found = find(
                    query: query,
                    direction: direction,
                    caseSensitive: caseSensitive,
                    in: textView
                )
                onFindResult(found)
            case let .selectRange(targetRange):
                selectRange(targetRange, in: textView)
            case .toggleBoldface, .toggleItalics, .toggleUnderline:
                _ = applyFormatting(command.action, to: textView)
            case let .replaceSelection(rewrittenText, targetRange, emphasizeWithItalics):
                replaceSelection(
                    in: textView,
                    targetRange: targetRange,
                    with: rewrittenText,
                    emphasizeWithItalics: emphasizeWithItalics
                )
                didMutateText = true
            case let .applyFont(family, size):
                let currentFont = textView.typingAttributes[.font] as? NSFont ?? NSFont.preferredFont(forTextStyle: .body)
                let traits = NSFontManager.shared.traits(of: currentFont)
                let normalizedFamily = SceneFontSelectorData.normalizedFamily(family)
                let baseFont: NSFont = {
                    let s = max(1, size)
                    if normalizedFamily == SceneFontSelectorData.systemFamily {
                        return NSFont.systemFont(ofSize: s)
                    }
                    return NSFont(name: normalizedFamily, size: s) ?? NSFont.systemFont(ofSize: s)
                }()
                var newFont = baseFont
                if traits.contains(.boldFontMask) { newFont = NSFontManager.shared.convert(newFont, toHaveTrait: .boldFontMask) }
                if traits.contains(.italicFontMask) { newFont = NSFontManager.shared.convert(newFont, toHaveTrait: .italicFontMask) }
                let selectedRange = textView.selectedRange()
                if selectedRange.length > 0 {
                    didMutateText = applyAttributeMutation(
                        in: selectedRange,
                        textView: textView,
                        actionName: "Set Font"
                    ) { storage, effectiveRange in
                        storage.addAttribute(.font, value: newFont, range: effectiveRange)
                    }
                }
                var typingAttrs = textView.typingAttributes
                typingAttrs[.font] = newFont
                textView.typingAttributes = typingAttrs
            case let .applyTextColor(rgba, targetRange):
                let selectedRange = resolvedTargetRange(targetRange, in: textView)
                if let rgba {
                    let nsColor = NSColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
                    if selectedRange.length > 0 {
                        didMutateText = applyAttributeMutation(
                            in: selectedRange,
                            textView: textView,
                            actionName: "Set Text Color"
                        ) { storage, effectiveRange in
                            storage.addAttribute(.foregroundColor, value: nsColor, range: effectiveRange)
                        }
                    }
                    var typingAttrs = textView.typingAttributes
                    typingAttrs[.foregroundColor] = nsColor
                    textView.typingAttributes = typingAttrs
                } else {
                    if selectedRange.length > 0 {
                        didMutateText = applyAttributeMutation(
                            in: selectedRange,
                            textView: textView,
                            actionName: "Set Text Color"
                        ) { storage, effectiveRange in
                            storage.removeAttribute(.foregroundColor, range: effectiveRange)
                        }
                    }
                    var typingAttrs = textView.typingAttributes
                    typingAttrs.removeValue(forKey: .foregroundColor)
                    textView.typingAttributes = typingAttrs
                }
            case let .applyTextBackgroundColor(rgba, targetRange):
                let selectedRange = resolvedTargetRange(targetRange, in: textView)
                if let rgba {
                    let nsColor = NSColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
                    if selectedRange.length > 0 {
                        didMutateText = applyAttributeMutation(
                            in: selectedRange,
                            textView: textView,
                            actionName: "Set Highlight Color"
                        ) { storage, effectiveRange in
                            storage.addAttribute(.backgroundColor, value: nsColor, range: effectiveRange)
                        }
                    }
                    var typingAttrs = textView.typingAttributes
                    typingAttrs[.backgroundColor] = nsColor
                    textView.typingAttributes = typingAttrs
                } else {
                    if selectedRange.length > 0 {
                        didMutateText = applyAttributeMutation(
                            in: selectedRange,
                            textView: textView,
                            actionName: "Set Highlight Color"
                        ) { storage, effectiveRange in
                            storage.removeAttribute(.backgroundColor, range: effectiveRange)
                        }
                    }
                    var typingAttrs = textView.typingAttributes
                    typingAttrs.removeValue(forKey: .backgroundColor)
                    textView.typingAttributes = typingAttrs
                }
            case let .applyAlignment(option):
                let nsAlign: NSTextAlignment
                switch option {
                case .left:      nsAlign = .left
                case .center:    nsAlign = .center
                case .right:     nsAlign = .right
                case .justified: nsAlign = .justified
                }
                let selectedRange = textView.selectedRange()
                if let storage = textView.textStorage {
                    let paragraphRange = (storage.string as NSString).paragraphRange(for: selectedRange)
                    didMutateText = applyAttributeMutation(
                        in: paragraphRange,
                        textView: textView,
                        actionName: "Set Alignment"
                    ) { storage, effectiveRange in
                        storage.enumerateAttribute(.paragraphStyle, in: effectiveRange, options: []) { value, range, _ in
                            let ps = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                            ps.alignment = nsAlign
                            storage.addAttribute(.paragraphStyle, value: ps, range: range)
                        }
                    }
                }
                let existingPS = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
                let newPS = existingPS?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                newPS.alignment = nsAlign
                var typingAttrs = textView.typingAttributes
                typingAttrs[.paragraphStyle] = newPS
                textView.typingAttributes = typingAttrs
            case let .clearSelectionFormatting(targetRange):
                let selectedRange = resolvedTargetRange(targetRange, in: textView)
                didMutateText = applyAttributeMutation(
                    in: selectedRange,
                    textView: textView,
                    actionName: "Clear Formatting"
                ) { _, effectiveRange in
                    clearSelectionFormatting(in: effectiveRange, textView: textView)
                }
            case .openFontPanel:
                let currentFont = textView.typingAttributes[.font] as? NSFont ?? NSFont.preferredFont(forTextStyle: .body)
                NSFontManager.shared.setSelectedFont(currentFont, isMultiple: false)
                NSFontManager.shared.orderFrontFontPanel(nil)
            }
            if didMutateText {
                publishChange(from: textView)
            }
            publishSelection(from: textView)
            // Skip publishFormatting for inline formatting commands to avoid
            // feedback loops with ColorPicker bindings (color space conversion
            // can produce slightly different values, retriggering the setter).
            if !isInlineFormatting {
                publishFormatting(from: textView)
            }
            publishUndoRedoState(from: textView)
            isApplyingProgrammaticChange = false
        }

        func handleFontPanelChange(in textView: NSTextView) {
            publishChange(from: textView)
            publishFormatting(from: textView)
        }

        func applyFormattingShortcut(_ action: SceneEditorCommand.Action, to textView: NSTextView) {
            let didMutateText = applyFormatting(action, to: textView)
            if didMutateText {
                publishChange(from: textView)
            }
            publishSelection(from: textView)
            publishFormatting(from: textView)
            publishUndoRedoState(from: textView)
        }

        private func publishChange(from textView: NSTextView) {
            let plainText = textView.string
            let fullRange = NSRange(location: 0, length: textView.attributedString().length)
            let richTextData = try? textView.attributedString().data(
                from: fullRange,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            onChange(plainText, richTextData)
        }

        private func publishSelection(from textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            let clampedRange = clampedRangeForStorage(selectedRange, textView: textView)
            guard clampedRange.length > 0 else {
                onSelectionChange(.empty)
                return
            }

            let selectedText = (textView.string as NSString).substring(with: clampedRange)
            onSelectionChange(
                SceneEditorSelection(
                    range: SceneEditorRange(range: clampedRange),
                    text: selectedText
                )
            )
        }

        private func publishUndoRedoState(from textView: NSTextView) {
            let undoManager = textView.undoManager
            onUndoRedoAvailabilityChange(
                undoManager?.canUndo ?? false,
                undoManager?.canRedo ?? false
            )
        }

        private func publishFormatting(from textView: NSTextView) {
            let attrs = textView.typingAttributes
            let selectedRange = clampedRangeForStorage(textView.selectedRange(), textView: textView)

            let font = attrs[.font] as? NSFont ?? NSFont.preferredFont(forTextStyle: .body)
            let fontFamily = SceneFontSelectorData.normalizedFamily(font.familyName ?? font.fontName)
            let fontSize = font.pointSize

            let textColorInfo: (color: CodableRGBA?, mixed: Bool)
            let textBackgroundColorInfo: (color: CodableRGBA?, mixed: Bool)
            if selectedRange.length > 0, let storage = textView.textStorage {
                textColorInfo = uniformColorAttribute(.foregroundColor, in: selectedRange, storage: storage)
                textBackgroundColorInfo = uniformColorAttribute(.backgroundColor, in: selectedRange, storage: storage)
            } else {
                textColorInfo = (CodableRGBA.from(nsColor: attrs[.foregroundColor] as? NSColor), false)
                textBackgroundColorInfo = (CodableRGBA.from(nsColor: attrs[.backgroundColor] as? NSColor), false)
            }

            let alignment: TextAlignmentOption
            switch (attrs[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .left {
            case .center:    alignment = .center
            case .right:     alignment = .right
            case .justified: alignment = .justified
            default:         alignment = .left
            }

            let isBold = selectionHasFontTrait(.boldFontMask, in: textView)
            let isItalic = selectionHasFontTrait(.italicFontMask, in: textView)
            let isUnderline = selectionHasUnderline(in: textView)

            onFormattingChange(SceneEditorFormatting(
                fontFamily: fontFamily,
                fontSize: Double(fontSize),
                textColor: textColorInfo.color,
                textBackgroundColor: textBackgroundColorInfo.color,
                hasMixedTextColor: textColorInfo.mixed,
                hasMixedTextBackgroundColor: textBackgroundColorInfo.mixed,
                isBold: isBold,
                isItalic: isItalic,
                isUnderline: isUnderline,
                textAlignment: alignment
            ))
        }

        private func applyFormatting(_ action: SceneEditorCommand.Action, to textView: NSTextView) -> Bool {
            switch action {
            case .toggleBoldface:
                return toggleFontTrait(.boldFontMask, in: textView)
            case .toggleItalics:
                return toggleFontTrait(.italicFontMask, in: textView)
            case .toggleUnderline:
                return toggleUnderline(in: textView)
            case .undo, .redo:
                return false
            case .find(query: _, direction: _, caseSensitive: _):
                return false
            case .selectRange(targetRange: _):
                return false
            case .replaceSelection(rewrittenText: _, targetRange: _, emphasizeWithItalics: _):
                return false
            case .applyFont, .applyTextColor, .applyTextBackgroundColor, .clearSelectionFormatting, .applyAlignment, .openFontPanel:
                return false
            }
        }

        private func selectRange(_ targetRange: SceneEditorRange, in textView: NSTextView) {
            let clamped = clampedRangeForStorage(targetRange.nsRange, textView: textView)
            textView.setSelectedRange(clamped)
            textView.scrollRangeToVisible(clamped)
        }

        private func find(
            query: String,
            direction: SceneEditorCommand.FindDirection,
            caseSensitive: Bool,
            in textView: NSTextView
        ) -> Bool {
            let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedQuery.isEmpty else { return false }

            let text = textView.string as NSString
            guard text.length > 0 else { return false }

            let selectedRange = clampedRangeForStorage(textView.selectedRange(), textView: textView)
            let options: NSString.CompareOptions = caseSensitive
                ? []
                : [.caseInsensitive, .diacriticInsensitive]

            switch direction {
            case .forward:
                let forwardStart = min(text.length, selectedRange.location + max(selectedRange.length, 1))
                if let found = findForward(
                    text: text,
                    query: normalizedQuery,
                    from: forwardStart,
                    options: options
                ) {
                    textView.setSelectedRange(found)
                    textView.scrollRangeToVisible(found)
                    return true
                }
            case .backward:
                let backwardStart = max(0, selectedRange.location - 1)
                if let found = findBackward(
                    text: text,
                    query: normalizedQuery,
                    from: backwardStart,
                    options: options
                ) {
                    textView.setSelectedRange(found)
                    textView.scrollRangeToVisible(found)
                    return true
                }
            }

            return false
        }

        private func findForward(
            text: NSString,
            query: String,
            from location: Int,
            options: NSString.CompareOptions
        ) -> NSRange? {
            if location < text.length {
                let range = NSRange(location: location, length: text.length - location)
                let found = text.range(of: query, options: options, range: range)
                if found.location != NSNotFound {
                    return found
                }
            }

            let wrapLength = min(max(0, location), text.length)
            if wrapLength > 0 {
                let wrapRange = NSRange(location: 0, length: wrapLength)
                let wrapFound = text.range(of: query, options: options, range: wrapRange)
                if wrapFound.location != NSNotFound {
                    return wrapFound
                }
            }

            return nil
        }

        private func findBackward(
            text: NSString,
            query: String,
            from location: Int,
            options: NSString.CompareOptions
        ) -> NSRange? {
            if text.length == 0 { return nil }

            let searchLocation = max(0, min(location, text.length - 1))
            let headRange = NSRange(location: 0, length: searchLocation + 1)
            let backwardOptions = options.union(.backwards)

            let found = text.range(of: query, options: backwardOptions, range: headRange)
            if found.location != NSNotFound {
                return found
            }

            let tailStart = searchLocation + 1
            if tailStart < text.length {
                let tailRange = NSRange(location: tailStart, length: text.length - tailStart)
                let wrapFound = text.range(of: query, options: backwardOptions, range: tailRange)
                if wrapFound.location != NSNotFound {
                    return wrapFound
                }
            }

            return nil
        }

        private func replaceSelection(
            in textView: NSTextView,
            targetRange: SceneEditorRange,
            with rewrittenText: String,
            emphasizeWithItalics: Bool
        ) {
            guard let textStorage = textView.textStorage else { return }

            let normalizedText = rewrittenText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedText.isEmpty else { return }

            var effectiveRange = clampedRangeForStorage(targetRange.nsRange, textView: textView)
            if effectiveRange.length == 0 {
                effectiveRange = clampedRangeForStorage(textView.selectedRange(), textView: textView)
            }
            guard effectiveRange.length > 0 else { return }

            guard textView.shouldChangeText(in: effectiveRange, replacementString: normalizedText) else {
                return
            }

            let baseFont = baseFontForReplacement(in: effectiveRange, textView: textView)
            let replacementFont = emphasizeWithItalics
                ? NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
                : baseFont

            var replacementAttributes = textView.typingAttributes
            replacementAttributes[.font] = replacementFont

            let replacementAttributedText = NSAttributedString(
                string: normalizedText,
                attributes: replacementAttributes
            )

            textStorage.beginEditing()
            textStorage.replaceCharacters(in: effectiveRange, with: replacementAttributedText)
            textStorage.endEditing()

            let insertedRange = NSRange(location: effectiveRange.location, length: replacementAttributedText.length)
            textView.setSelectedRange(insertedRange)
            textView.didChangeText()
        }

        private func applyExternalTextDelta(
            to textView: NSTextView,
            newText: String,
            moveCaretToEnd: Bool
        ) {
            guard let textStorage = textView.textStorage else { return }
            let previousSelection = clampedRangeForStorage(textView.selectedRange(), textView: textView)

            let currentString = textView.string as NSString
            let targetString = newText as NSString
            let currentLength = currentString.length
            let targetLength = targetString.length

            var commonPrefix = 0
            while commonPrefix < currentLength,
                  commonPrefix < targetLength,
                  currentString.character(at: commonPrefix) == targetString.character(at: commonPrefix) {
                commonPrefix += 1
            }

            var commonSuffix = 0
            while commonSuffix < (currentLength - commonPrefix),
                  commonSuffix < (targetLength - commonPrefix),
                  currentString.character(at: currentLength - commonSuffix - 1) == targetString.character(at: targetLength - commonSuffix - 1) {
                commonSuffix += 1
            }

            let replacedRange = NSRange(
                location: commonPrefix,
                length: currentLength - commonPrefix - commonSuffix
            )
            let insertedRange = NSRange(
                location: commonPrefix,
                length: targetLength - commonPrefix - commonSuffix
            )
            let replacementText = targetString.substring(with: insertedRange)

            guard textView.shouldChangeText(in: replacedRange, replacementString: replacementText) else {
                return
            }

            let baseFont = baseFontForReplacement(in: replacedRange, textView: textView)
            var replacementAttributes = textView.typingAttributes
            replacementAttributes[.font] = baseFont

            let replacementAttributedText = NSAttributedString(
                string: replacementText,
                attributes: replacementAttributes
            )

            textStorage.beginEditing()
            textStorage.replaceCharacters(in: replacedRange, with: replacementAttributedText)
            textStorage.endEditing()

            if moveCaretToEnd {
                let selectionLocation = replacedRange.location + replacementAttributedText.length
                textView.setSelectedRange(NSRange(location: selectionLocation, length: 0))
            } else {
                let adjustedSelection = adjustedSelectionRange(
                    previousSelection,
                    replacedRange: replacedRange,
                    replacementLength: replacementAttributedText.length,
                    finalLength: textStorage.length
                )
                textView.setSelectedRange(adjustedSelection)
            }
            textView.didChangeText()
        }

        private func adjustedSelectionRange(
            _ originalSelection: NSRange,
            replacedRange: NSRange,
            replacementLength: Int,
            finalLength: Int
        ) -> NSRange {
            let originalStart = originalSelection.location
            let originalEnd = originalSelection.location + originalSelection.length
            let replacedStart = replacedRange.location
            let replacedEnd = replacedRange.location + replacedRange.length
            let delta = replacementLength - replacedRange.length

            func transformIndex(_ index: Int) -> Int {
                if index <= replacedStart {
                    return index
                }
                if index >= replacedEnd {
                    return index + delta
                }
                return replacedStart + replacementLength
            }

            let transformedStart = transformIndex(originalStart)
            let transformedEnd = transformIndex(originalEnd)

            let clampedStart = max(0, min(transformedStart, finalLength))
            let clampedEnd = max(clampedStart, min(transformedEnd, finalLength))
            return NSRange(location: clampedStart, length: clampedEnd - clampedStart)
        }

        private func isAtBottom(_ scrollView: NSScrollView) -> Bool {
            if let textView = scrollView.documentView as? NSTextView,
               let textContainer = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: textContainer)
            }

            let clipView = scrollView.contentView
            let visibleBottom = clipView.bounds.maxY
            let contentBottom = scrollView.documentView?.bounds.maxY ?? visibleBottom
            let tolerance: CGFloat = 20
            return contentBottom - visibleBottom <= tolerance
        }

        private func scrollToBottom(_ scrollView: NSScrollView) {
            if let textView = scrollView.documentView as? NSTextView,
               let textContainer = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: textContainer)
            }

            let clipView = scrollView.contentView
            let contentHeight = scrollView.documentView?.bounds.height ?? clipView.bounds.height
            let visibleHeight = clipView.bounds.height
            let maxOffsetY = max(0, contentHeight - visibleHeight)
            clipView.setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: maxOffsetY))
            scrollView.reflectScrolledClipView(clipView)
        }

        private func restoreScrollOrigin(_ scrollView: NSScrollView, _ previousOrigin: NSPoint) {
            if let textView = scrollView.documentView as? NSTextView,
               let textContainer = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: textContainer)
            }

            let clipView = scrollView.contentView
            let contentHeight = scrollView.documentView?.bounds.height ?? clipView.bounds.height
            let visibleHeight = clipView.bounds.height
            let maxOffsetY = max(0, contentHeight - visibleHeight)
            let clampedY = max(0, min(previousOrigin.y, maxOffsetY))
            clipView.setBoundsOrigin(NSPoint(x: previousOrigin.x, y: clampedY))
            scrollView.reflectScrolledClipView(clipView)
        }

        private func clampedRangeForStorage(_ range: NSRange, textView: NSTextView) -> NSRange {
            if range.location == NSNotFound {
                return NSRange(location: 0, length: 0)
            }
            let storageLength = textView.textStorage?.length ?? 0
            let location = max(0, min(range.location, storageLength))
            let maxLength = max(0, storageLength - location)
            let length = max(0, min(range.length, maxLength))
            return NSRange(location: location, length: length)
        }

        private func resolvedTargetRange(_ targetRange: SceneEditorRange?, in textView: NSTextView) -> NSRange {
            if let targetRange {
                return clampedRangeForStorage(targetRange.nsRange, textView: textView)
            }
            return clampedRangeForStorage(textView.selectedRange(), textView: textView)
        }

        @discardableResult
        private func applyAttributeMutation(
            in range: NSRange,
            textView: NSTextView,
            actionName: String,
            mutation: (NSTextStorage, NSRange) -> Void
        ) -> Bool {
            let effectiveRange = clampedRangeForStorage(range, textView: textView)
            guard effectiveRange.length > 0 else { return false }
            guard let storage = textView.textStorage else { return false }
            guard textView.shouldChangeText(in: effectiveRange, replacementString: nil) else { return false }
            mutation(storage, effectiveRange)
            textView.undoManager?.setActionName(actionName)
            textView.didChangeText()
            return true
        }

        private func clearSelectionFormatting(in range: NSRange, textView: NSTextView) {
            guard range.length > 0 else { return }
            guard let storage = textView.textStorage else { return }

            let appearance = lastAppliedAppearance ?? .default
            let baseFont = resolvedBaseFont(from: appearance)
            let paragraphStyle = resolvedParagraphStyle(from: appearance)
            let textColor = resolvedTextColor(from: appearance)
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: textColor
            ]

            storage.setAttributes(baseAttributes, range: range)

            var typingAttrs = textView.typingAttributes
            typingAttrs[.font] = baseFont
            typingAttrs[.paragraphStyle] = paragraphStyle
            typingAttrs[.foregroundColor] = textColor
            typingAttrs.removeValue(forKey: .backgroundColor)
            typingAttrs.removeValue(forKey: .underlineStyle)
            textView.typingAttributes = typingAttrs
        }

        private func uniformColorAttribute(
            _ key: NSAttributedString.Key,
            in range: NSRange,
            storage: NSTextStorage
        ) -> (color: CodableRGBA?, mixed: Bool) {
            var firstValue: CodableRGBA??
            var mixed = false

            storage.enumerateAttribute(key, in: range, options: []) { value, _, stop in
                let current = CodableRGBA.from(nsColor: value as? NSColor)
                if firstValue == nil {
                    firstValue = current
                    return
                }
                if !CodableRGBA.areClose(firstValue!, current) {
                    mixed = true
                    stop.pointee = true
                }
            }

            if mixed {
                return (nil, true)
            }
            return (firstValue ?? nil, false)
        }

        private func baseFontForReplacement(in range: NSRange, textView: NSTextView) -> NSFont {
            let fallback = NSFont.preferredFont(forTextStyle: .body)

            if range.length > 0,
               let font = textView.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
                return font
            }

            if let font = textView.typingAttributes[.font] as? NSFont {
                return font
            }

            return textView.font ?? fallback
        }

        private func toggleFontTrait(_ trait: NSFontTraitMask, in textView: NSTextView) -> Bool {
            let selectedRange = textView.selectedRange()
            let fallbackFont = NSFont.preferredFont(forTextStyle: .body)
            let currentTypingFont = (textView.typingAttributes[.font] as? NSFont) ?? textView.font ?? fallbackFont
            let shouldEnableTrait = !selectionHasFontTrait(trait, in: textView)

            if selectedRange.length == 0 {
                let updatedFont = convertedFont(currentTypingFont, toggling: trait, enable: shouldEnableTrait) ?? currentTypingFont
                var typingAttributes = textView.typingAttributes
                typingAttributes[.font] = updatedFont
                textView.typingAttributes = typingAttributes
                return false
            }

            let actionName = trait == .boldFontMask ? "Toggle Bold" : "Toggle Italic"
            return applyAttributeMutation(in: selectedRange, textView: textView, actionName: actionName) { textStorage, effectiveRange in
                textStorage.beginEditing()
                textStorage.enumerateAttribute(.font, in: effectiveRange, options: []) { value, range, _ in
                    let currentFont = (value as? NSFont) ?? currentTypingFont
                    let updatedFont = convertedFont(currentFont, toggling: trait, enable: shouldEnableTrait) ?? currentFont
                    textStorage.addAttribute(.font, value: updatedFont, range: range)
                }
                textStorage.endEditing()
            }
        }

        private func selectionHasFontTrait(_ trait: NSFontTraitMask, in textView: NSTextView) -> Bool {
            let selectedRange = textView.selectedRange()
            let fallbackFont = NSFont.preferredFont(forTextStyle: .body)
            let typingFont = (textView.typingAttributes[.font] as? NSFont) ?? textView.font ?? fallbackFont

            if selectedRange.length == 0 {
                return NSFontManager.shared.traits(of: typingFont).contains(trait)
            }

            guard let textStorage = textView.textStorage else { return false }
            var allHaveTrait = true
            textStorage.enumerateAttribute(.font, in: selectedRange, options: []) { value, _, stop in
                let font = (value as? NSFont) ?? typingFont
                if !NSFontManager.shared.traits(of: font).contains(trait) {
                    allHaveTrait = false
                    stop.pointee = true
                }
            }
            return allHaveTrait
        }

        private func convertedFont(_ font: NSFont, toggling trait: NSFontTraitMask, enable: Bool) -> NSFont? {
            if enable {
                return NSFontManager.shared.convert(font, toHaveTrait: trait)
            }
            return NSFontManager.shared.convert(font, toNotHaveTrait: trait)
        }

        private func toggleUnderline(in textView: NSTextView) -> Bool {
            let selectedRange = textView.selectedRange()
            let shouldEnableUnderline = !selectionHasUnderline(in: textView)
            let underlineValue = NSUnderlineStyle.single.rawValue

            if selectedRange.length == 0 {
                var typingAttributes = textView.typingAttributes
                if shouldEnableUnderline {
                    typingAttributes[.underlineStyle] = underlineValue
                } else {
                    typingAttributes.removeValue(forKey: .underlineStyle)
                }
                textView.typingAttributes = typingAttributes
                return false
            }

            return applyAttributeMutation(in: selectedRange, textView: textView, actionName: "Toggle Underline") { textStorage, effectiveRange in
                if shouldEnableUnderline {
                    textStorage.addAttribute(.underlineStyle, value: underlineValue, range: effectiveRange)
                } else {
                    textStorage.removeAttribute(.underlineStyle, range: effectiveRange)
                }
            }
        }

        private func selectionHasUnderline(in textView: NSTextView) -> Bool {
            let selectedRange = textView.selectedRange()
            let typingValue = textView.typingAttributes[.underlineStyle] as? Int ?? 0

            if selectedRange.length == 0 {
                return typingValue != 0
            }

            guard let textStorage = textView.textStorage else { return false }
            var allUnderlined = true
            textStorage.enumerateAttribute(.underlineStyle, in: selectedRange, options: []) { value, _, stop in
                let styleValue: Int
                if let intValue = value as? Int {
                    styleValue = intValue
                } else if let numberValue = value as? NSNumber {
                    styleValue = numberValue.intValue
                } else {
                    styleValue = 0
                }

                if styleValue == 0 {
                    allUnderlined = false
                    stop.pointee = true
                }
            }
            return allUnderlined
        }

        // MARK: - Editor Appearance

        func applyAppearanceIfNeeded(
            _ settings: EditorAppearanceSettings,
            sceneID: UUID?,
            to textView: NSTextView,
            scrollView: NSScrollView
        ) {
            let sceneChanged = !appearanceEverApplied || lastAppliedAppearanceSceneID != sceneID
            guard sceneChanged || settings != lastAppliedAppearance else { return }
            lastAppliedAppearance = settings
            lastAppliedAppearanceSceneID = sceneID
            appearanceEverApplied = true
            applyAppearance(settings, to: textView, scrollView: scrollView)
        }

        private func applyAppearance(
            _ settings: EditorAppearanceSettings,
            to textView: NSTextView,
            scrollView: NSScrollView
        ) {
            let baseFont = resolvedBaseFont(from: settings)
            let paragraphStyle = resolvedParagraphStyle(from: settings)
            let textColor = resolvedTextColor(from: settings)

            let bgColor: NSColor = settings.backgroundColor.map {
                NSColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
            } ?? NSColor.textBackgroundColor

            // Visual properties (don't affect stored data).
            textView.textColor = textColor
            textView.backgroundColor = bgColor
            textView.textContainerInset = NSSize(
                width: settings.horizontalPadding,
                height: settings.verticalPadding
            )
            scrollView.backgroundColor = bgColor

            // Typing attributes for newly typed text.
            // Preserve any existing .backgroundColor (text highlight) so that
            // appearance re-application doesn't wipe out the toolbar highlight
            // color, which is set independently via .applyTextBackgroundColor.
            var newTypingAttrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: textColor
            ]
            if let existingBg = textView.typingAttributes[.backgroundColor] {
                newTypingAttrs[.backgroundColor] = existingBg
            }
            textView.typingAttributes = newTypingAttrs
        }

        private func resolvedBaseFont(from settings: EditorAppearanceSettings) -> NSFont {
            let normalizedFamily = SceneFontSelectorData.normalizedFamily(settings.fontFamily)
            if normalizedFamily == SceneFontSelectorData.systemFamily {
                let size = settings.fontSize > 0 ? settings.fontSize : 0
                return size > 0
                    ? NSFont.systemFont(ofSize: size)
                    : NSFont.preferredFont(forTextStyle: .body)
            }

            let size = settings.fontSize > 0 ? settings.fontSize : NSFont.systemFontSize
            return NSFont(name: normalizedFamily, size: size)
                ?? NSFont.preferredFont(forTextStyle: .body)
        }

        private func resolvedParagraphStyle(from settings: EditorAppearanceSettings) -> NSMutableParagraphStyle {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineHeightMultiple = max(1.0, settings.lineHeightMultiple)
            paragraphStyle.alignment = {
                switch settings.textAlignment {
                case .left:      return .left
                case .center:    return .center
                case .right:     return .right
                case .justified: return .justified
                }
            }()
            paragraphStyle.lineBreakMode = .byWordWrapping
            return paragraphStyle
        }

        private func resolvedTextColor(from settings: EditorAppearanceSettings) -> NSColor {
            settings.textColor.map {
                NSColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
            } ?? NSColor.textColor
        }

        private static func makeAttributedContent(plainText: String, richTextData: Data?) -> NSAttributedString {
            if let richTextData,
               let attributed = try? NSAttributedString(
                data: richTextData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
               ) {
                return attributed
            }

            return NSAttributedString(
                string: plainText,
                attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]
            )
        }
    }
}

private struct SceneHistorySheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let sceneID: UUID

    @State private var snapshots: [AppStore.SceneCheckpointSnapshot] = []
    @State private var selectedSnapshotIndex: Int = 0
    @State private var restoreStatus: String?

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private enum DiffLineKind {
        case unchanged
        case removed
        case added
    }

    private struct DiffLine {
        let kind: DiffLineKind
        let text: String
    }

    private var currentScene: Scene? {
        for chapter in store.chapters {
            if let scene = chapter.scenes.first(where: { $0.id == sceneID }) {
                return scene
            }
        }
        return nil
    }

    private var sceneTitle: String {
        guard let currentScene else { return "Unknown Scene" }
        let trimmed = currentScene.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Scene" : trimmed
    }

    private var selectedSnapshot: AppStore.SceneCheckpointSnapshot? {
        guard snapshots.indices.contains(selectedSnapshotIndex) else {
            return nil
        }
        return snapshots[selectedSnapshotIndex]
    }

    private var canSelectOlderSnapshot: Bool {
        selectedSnapshotIndex + 1 < snapshots.count
    }

    private var canSelectNewerSnapshot: Bool {
        selectedSnapshotIndex > 0
    }

    private var currentSceneContent: String {
        currentScene?.content ?? ""
    }

    private var diffLines: [DiffLine] {
        guard let selectedSnapshot else {
            return []
        }
        return Self.makeLineDiff(
            historicalText: selectedSnapshot.sceneContent,
            currentText: currentSceneContent
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scene History")
                        .font(.title3.weight(.semibold))
                    Text("Checkpoint history for \(sceneTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("Refresh") {
                    reloadSnapshots(refreshCheckpoints: true)
                }

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if currentScene == nil {
                ContentUnavailableView(
                    "Scene Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This scene no longer exists in the current project.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshots.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "clock.badge.xmark",
                    description: Text("Create checkpoints to browse scene history.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let lines = diffLines
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Button {
                            selectedSnapshotIndex += 1
                            restoreStatus = nil
                        } label: {
                            Label("Older", systemImage: "chevron.left")
                        }
                        .disabled(!canSelectOlderSnapshot)

                        Button {
                            selectedSnapshotIndex -= 1
                            restoreStatus = nil
                        } label: {
                            Label("Newer", systemImage: "chevron.right")
                        }
                        .disabled(!canSelectNewerSnapshot)

                        Spacer(minLength: 0)

                        if let selectedSnapshot {
                            Text(
                                "Checkpoint \(selectedSnapshotIndex + 1) of \(snapshots.count) · "
                                    + Self.timestampFormatter.string(from: selectedSnapshot.checkpointCreatedAt)
                            )
                            .font(.subheadline.weight(.medium))
                        }
                    }

                    if let selectedSnapshot {
                        Text(selectedSnapshot.checkpointFileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Difference vs current scene")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(Self.differenceSummary(from: lines))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    SceneHistoryDiffTextView(attributedText: Self.makeAttributedDiffText(from: lines))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()

                HStack {
                    Text(restoreStatus ?? "Restore applies only to the selected scene text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Restore Scene Text") {
                        restoreSelectedSnapshotText()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSnapshot == nil)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 920, minHeight: 620)
        .onAppear {
            reloadSnapshots(refreshCheckpoints: true)
        }
        .onChange(of: store.projectCheckpoints) { _, _ in
            reloadSnapshots(refreshCheckpoints: false)
        }
    }

    private func reloadSnapshots(refreshCheckpoints: Bool) {
        let previousCheckpointFileName = selectedSnapshot?.checkpointFileName
        if refreshCheckpoints {
            store.refreshProjectCheckpoints()
        }

        snapshots = store.sceneCheckpointSnapshots(for: sceneID)
        if snapshots.isEmpty {
            selectedSnapshotIndex = 0
            restoreStatus = nil
            return
        }

        if let previousCheckpointFileName,
           let preservedIndex = snapshots.firstIndex(where: { $0.checkpointFileName == previousCheckpointFileName }) {
            selectedSnapshotIndex = preservedIndex
            return
        }

        selectedSnapshotIndex = min(selectedSnapshotIndex, snapshots.count - 1)
    }

    private func restoreSelectedSnapshotText() {
        guard let selectedSnapshot else { return }

        do {
            try store.restoreSceneTextFromCheckpoint(
                checkpointFileName: selectedSnapshot.checkpointFileName,
                sceneID: sceneID
            )
            restoreStatus = "Restored scene text from \(Self.timestampFormatter.string(from: selectedSnapshot.checkpointCreatedAt))."
        } catch {
            store.lastError = "Scene restore failed: \(error.localizedDescription)"
        }
    }

    private static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        ).map(String.init)
    }

    private static func makeLineDiff(
        historicalText: String,
        currentText: String
    ) -> [DiffLine] {
        let historicalLines = splitLines(historicalText)
        let currentLines = splitLines(currentText)

        if historicalLines == currentLines {
            if historicalLines.isEmpty {
                return [DiffLine(kind: .unchanged, text: "(No content)")]
            }
            return historicalLines.map { DiffLine(kind: .unchanged, text: $0) }
        }

        let historicalCount = historicalLines.count
        let currentCount = currentLines.count
        let maxDetailedMatrixCells = 4_000_000
        let canBuildDetailedMatrix = historicalCount == 0
            || currentCount == 0
            || (historicalCount <= (maxDetailedMatrixCells / max(1, currentCount)))

        if !canBuildDetailedMatrix {
            var coarse: [DiffLine] = [
                DiffLine(
                    kind: .unchanged,
                    text: "(Diff too large for detailed comparison; showing full historical and current text.)"
                )
            ]
            coarse.append(contentsOf: historicalLines.map { DiffLine(kind: .removed, text: $0) })
            coarse.append(contentsOf: currentLines.map { DiffLine(kind: .added, text: $0) })
            return coarse
        }

        let matrixWidth = currentCount + 1
        var lcsMatrix = Array(repeating: 0, count: (historicalCount + 1) * matrixWidth)
        @inline(__always)
        func matrixIndex(_ i: Int, _ j: Int) -> Int {
            (i * matrixWidth) + j
        }

        for i in (0..<historicalCount).reversed() {
            for j in (0..<currentCount).reversed() {
                if historicalLines[i] == currentLines[j] {
                    lcsMatrix[matrixIndex(i, j)] = lcsMatrix[matrixIndex(i + 1, j + 1)] + 1
                } else {
                    lcsMatrix[matrixIndex(i, j)] = max(
                        lcsMatrix[matrixIndex(i + 1, j)],
                        lcsMatrix[matrixIndex(i, j + 1)]
                    )
                }
            }
        }

        var diff: [DiffLine] = []
        var i = 0
        var j = 0
        while i < historicalCount && j < currentCount {
            if historicalLines[i] == currentLines[j] {
                diff.append(DiffLine(kind: .unchanged, text: historicalLines[i]))
                i += 1
                j += 1
            } else if lcsMatrix[matrixIndex(i + 1, j)] >= lcsMatrix[matrixIndex(i, j + 1)] {
                diff.append(DiffLine(kind: .removed, text: historicalLines[i]))
                i += 1
            } else {
                diff.append(DiffLine(kind: .added, text: currentLines[j]))
                j += 1
            }
        }

        while i < historicalCount {
            diff.append(DiffLine(kind: .removed, text: historicalLines[i]))
            i += 1
        }

        while j < currentCount {
            diff.append(DiffLine(kind: .added, text: currentLines[j]))
            j += 1
        }

        return diff
    }

    private static func differenceSummary(from lines: [DiffLine]) -> String {
        let additions = lines.filter { $0.kind == .added }.count
        let removals = lines.filter { $0.kind == .removed }.count
        if additions == 0 && removals == 0 {
            return "No differences"
        }
        return "\(additions) additions, \(removals) removals"
    }

    private static func makeAttributedDiffText(from lines: [DiffLine]) -> NSAttributedString {
        let contentLines = lines.isEmpty ? [DiffLine(kind: .unchanged, text: "(No differences)")] : lines
        let rendered = NSMutableAttributedString()
        let monospacedFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        for (index, line) in contentLines.enumerated() {
            let prefix: String
            let textColor: NSColor
            let backgroundColor: NSColor?

            switch line.kind {
            case .unchanged:
                prefix = "  "
                textColor = NSColor.labelColor
                backgroundColor = nil
            case .removed:
                prefix = "- "
                textColor = NSColor.systemRed
                backgroundColor = NSColor.systemRed.withAlphaComponent(0.10)
            case .added:
                prefix = "+ "
                textColor = NSColor.systemGreen
                backgroundColor = NSColor.systemGreen.withAlphaComponent(0.10)
            }

            var attributes: [NSAttributedString.Key: Any] = [
                .font: monospacedFont,
                .foregroundColor: textColor
            ]
            if let backgroundColor {
                attributes[.backgroundColor] = backgroundColor
            }

            let lineText = prefix + line.text + (index + 1 < contentLines.count ? "\n" : "")
            rendered.append(NSAttributedString(string: lineText, attributes: attributes))
        }

        return rendered
    }
}

private struct SceneHistoryDiffTextView: NSViewRepresentable {
    let attributedText: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.lineFragmentPadding = 0
        }

        textView.textStorage?.setAttributedString(attributedText)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(attributedText)
    }
}

private struct SceneContextSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery: String = ""
    @State private var isNarrativeStateExpanded: Bool = false
    private static let narrativeUnspecified = "Unspecified"
    private static let narrativePOVValues = [
        "First Person",
        "Third Person Limited",
        "Third Person Omniscient"
    ]
    private static let narrativeTenseValues = [
        "Past",
        "Present",
        "Future"
    ]

    private var selectedCount: Int {
        store.selectedSceneContextTotalCount
    }

    private struct SceneSummaryOption: Identifiable {
        let id: UUID
        let chapterTitle: String
        let sceneTitle: String
        let summary: String
    }

    private struct ChapterSummaryOption: Identifiable {
        let id: UUID
        let chapterTitle: String
        let summary: String
    }

    private var sceneSummaryOptions: [SceneSummaryOption] {
        store.chapters.flatMap { chapter in
            let chapterTitle = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Untitled Chapter"
                : chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)

            return chapter.scenes.compactMap { scene -> SceneSummaryOption? in
                let summary = scene.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !summary.isEmpty else { return nil }
                let sceneTitle = scene.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Untitled Scene"
                    : scene.title.trimmingCharacters(in: .whitespacesAndNewlines)

                return SceneSummaryOption(
                    id: scene.id,
                    chapterTitle: chapterTitle,
                    sceneTitle: sceneTitle,
                    summary: summary
                )
            }
        }
    }

    private var chapterSummaryOptions: [ChapterSummaryOption] {
        store.chapters.compactMap { chapter -> ChapterSummaryOption? in
            let summary = chapter.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else { return nil }
            let chapterTitle = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Untitled Chapter"
                : chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)

            return ChapterSummaryOption(
                id: chapter.id,
                chapterTitle: chapterTitle,
                summary: summary
            )
        }
    }

    private var allCompendiumEntryIDs: [UUID] {
        CompendiumCategory.allCases
            .flatMap { store.entries(in: $0) }
            .map(\.id)
    }

    private var allSceneContextIDs: [UUID] {
        sceneSummaryOptions.map(\.id)
    }

    private var allChapterContextIDs: [UUID] {
        chapterSummaryOptions.map(\.id)
    }

    private var selectedCompendiumCount: Int {
        store.selectedSceneContextCompendiumIDs.count
    }

    private var selectedSceneCount: Int {
        store.selectedSceneContextSceneSummaryIDs.count + store.selectedSceneContextChapterSummaryIDs.count
    }

    private var totalSceneCount: Int {
        allSceneContextIDs.count + allChapterContextIDs.count
    }

    private var selectedNarrativeState: SceneNarrativeState {
        store.selectedSceneNarrativeState
    }

    private var hasNarrativeStateValues: Bool {
        [
            selectedNarrativeState.pov,
            selectedNarrativeState.tense,
            selectedNarrativeState.location,
            selectedNarrativeState.time,
            selectedNarrativeState.goal,
            selectedNarrativeState.emotion
        ].contains(where: isNarrativeValueDefined)
    }

    private var narrativePOVOptions: [String] {
        narrativePickerOptions(
            baseOptions: Self.narrativePOVValues,
            selectedValue: selectedNarrativeState.pov
        )
    }

    private var narrativeTenseOptions: [String] {
        narrativePickerOptions(
            baseOptions: Self.narrativeTenseValues,
            selectedValue: selectedNarrativeState.tense
        )
    }

    private var narrativePOVBinding: Binding<String> {
        Binding(
            get: {
                normalizedNarrativeValue(selectedNarrativeState.pov) ?? Self.narrativeUnspecified
            },
            set: { value in
                store.updateSelectedSceneNarrativePOV(
                    value == Self.narrativeUnspecified ? nil : value
                )
            }
        )
    }

    private var narrativeTenseBinding: Binding<String> {
        Binding(
            get: {
                normalizedNarrativeValue(selectedNarrativeState.tense) ?? Self.narrativeUnspecified
            },
            set: { value in
                store.updateSelectedSceneNarrativeTense(
                    value == Self.narrativeUnspecified ? nil : value
                )
            }
        )
    }

    private var narrativeLocationBinding: Binding<String> {
        Binding(
            get: { selectedNarrativeState.location ?? "" },
            set: { store.updateSelectedSceneNarrativeLocation($0) }
        )
    }

    private var narrativeTimeBinding: Binding<String> {
        Binding(
            get: { selectedNarrativeState.time ?? "" },
            set: { store.updateSelectedSceneNarrativeTime($0) }
        )
    }

    private var narrativeGoalBinding: Binding<String> {
        Binding(
            get: { selectedNarrativeState.goal ?? "" },
            set: { store.updateSelectedSceneNarrativeGoal($0) }
        )
    }

    private var narrativeEmotionBinding: Binding<String> {
        Binding(
            get: { selectedNarrativeState.emotion ?? "" },
            set: { store.updateSelectedSceneNarrativeEmotion($0) }
        )
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
                        store.clearCurrentSceneContextSelection()
                    }
                }

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                TextField("Search context entries", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)

                Text("\(selectedCount) entr\(selectedCount == 1 ? "y" : "ies") selected for this scene")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)

            Divider()

            narrativeStateSection
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            HSplitView {
                compendiumColumn
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)

                scenesColumn
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 560)
    }

    private var sceneSubtitle: String {
        if let scene = store.selectedScene {
            let trimmed = scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmed.isEmpty ? "Untitled Scene" : trimmed
            return "Select context entries for \(title)"
        }
        return "Select context entries for the current scene"
    }

    private var hasVisibleCompendiumEntries: Bool {
        CompendiumCategory.allCases.contains { !filteredEntries(for: $0).isEmpty }
    }

    private var hasVisibleSceneEntries: Bool {
        !filteredSceneSummaryOptions().isEmpty || !filteredChapterSummaryOptions().isEmpty
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

    private func filteredSceneSummaryOptions() -> [SceneSummaryOption] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sceneSummaryOptions }

        return sceneSummaryOptions.filter { option in
            option.chapterTitle.lowercased().contains(query)
                || option.sceneTitle.lowercased().contains(query)
                || option.summary.lowercased().contains(query)
        }
    }

    private func filteredChapterSummaryOptions() -> [ChapterSummaryOption] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return chapterSummaryOptions }

        return chapterSummaryOptions.filter { option in
            option.chapterTitle.lowercased().contains(query)
                || option.summary.lowercased().contains(query)
        }
    }

    private var narrativeStateSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isNarrativeStateExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isNarrativeStateExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Narrative State")
                    if hasNarrativeStateValues {
                        Text("configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isNarrativeStateExpanded {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("Scene-local metadata for `{{state}}` and `{{state_*}}` template variables. Empty values are omitted from `<STATE>`.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button("Clear State") {
                                store.clearSelectedSceneNarrativeState()
                            }
                            .disabled(!hasNarrativeStateValues)
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("POV")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("POV", selection: narrativePOVBinding) {
                                    ForEach(narrativePOVOptions, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tense")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Tense", selection: narrativeTenseBinding) {
                                    ForEach(narrativeTenseOptions, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Location")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("e.g. North Platform", text: narrativeLocationBinding)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Time")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("e.g. Dawn, week 2", text: narrativeTimeBinding)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Goal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("e.g. Convince the guard", text: narrativeGoalBinding)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Emotion")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("e.g. Suspicious but hopeful", text: narrativeEmotionBinding)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 4)
            }
        }
    }

    private func narrativePickerOptions(baseOptions: [String], selectedValue: String?) -> [String] {
        var options: [String] = [Self.narrativeUnspecified]
        options.append(contentsOf: baseOptions)

        if let selected = normalizedNarrativeValue(selectedValue),
           !options.contains(selected) {
            options.append(selected)
        }

        return options
    }

    private func isNarrativeValueDefined(_ value: String?) -> Bool {
        normalizedNarrativeValue(value) != nil
    }

    private func normalizedNarrativeValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private var compendiumColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compendium")
                        .font(.headline)
                    Text("\(selectedCompendiumCount) of \(allCompendiumEntryIDs.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Select All") {
                    store.setCompendiumContextIDsForCurrentScene(allCompendiumEntryIDs)
                }
                .disabled(allCompendiumEntryIDs.isEmpty)

                Button("Unselect All") {
                    store.setCompendiumContextIDsForCurrentScene([])
                }
                .disabled(selectedCompendiumCount == 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

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

                    if !hasVisibleCompendiumEntries {
                        ContentUnavailableView(
                            "No Matching Compendium Entries",
                            systemImage: "books.vertical",
                            description: Text("No compendium entries match the current filter.")
                        )
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var scenesColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scenes")
                        .font(.headline)
                    Text("\(selectedSceneCount) of \(totalSceneCount) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Select All") {
                    store.setSceneSummaryContextIDsForCurrentScene(allSceneContextIDs)
                    store.setChapterSummaryContextIDsForCurrentScene(allChapterContextIDs)
                }
                .disabled(totalSceneCount == 0)

                Button("Unselect All") {
                    store.setSceneSummaryContextIDsForCurrentScene([])
                    store.setChapterSummaryContextIDsForCurrentScene([])
                }
                .disabled(selectedSceneCount == 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let visibleSceneSummaries = filteredSceneSummaryOptions()
                    if !visibleSceneSummaries.isEmpty {
                        GroupBox("Scene Summaries") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(visibleSceneSummaries) { option in
                                    Toggle(isOn: isSceneSummarySelectedBinding(sceneID: option.id)) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(option.chapterTitle) / \(option.sceneTitle)")
                                                .lineLimit(1)
                                            Text(option.summary)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    let visibleChapterSummaries = filteredChapterSummaryOptions()
                    if !visibleChapterSummaries.isEmpty {
                        GroupBox("Chapter Summaries") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(visibleChapterSummaries) { option in
                                    Toggle(isOn: isChapterSummarySelectedBinding(chapterID: option.id)) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.chapterTitle)
                                                .lineLimit(1)
                                            Text(option.summary)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !hasVisibleSceneEntries {
                        ContentUnavailableView(
                            "No Matching Scene Entries",
                            systemImage: "text.book.closed",
                            description: Text("No scene or chapter summaries match the current filter.")
                        )
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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

    private func isSceneSummarySelectedBinding(sceneID: UUID) -> Binding<Bool> {
        Binding(
            get: { store.isSceneSummarySelectedForCurrentSceneContext(sceneID) },
            set: { isSelected in
                let current = store.selectedSceneContextSceneSummaryIDs
                if isSelected {
                    if !current.contains(sceneID) {
                        store.setSceneSummaryContextIDsForCurrentScene(current + [sceneID])
                    }
                } else {
                    store.setSceneSummaryContextIDsForCurrentScene(current.filter { $0 != sceneID })
                }
            }
        )
    }

    private func isChapterSummarySelectedBinding(chapterID: UUID) -> Binding<Bool> {
        Binding(
            get: { store.isChapterSummarySelectedForCurrentSceneContext(chapterID) },
            set: { isSelected in
                let current = store.selectedSceneContextChapterSummaryIDs
                if isSelected {
                    if !current.contains(chapterID) {
                        store.setChapterSummaryContextIDsForCurrentScene(current + [chapterID])
                    }
                } else {
                    store.setChapterSummaryContextIDsForCurrentScene(current.filter { $0 != chapterID })
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

    var body: some View {
        PayloadPreviewSheetContent(preview: preview)
    }
}

private struct ProseGenerationReviewSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let review = store.proseGenerationReview {
                VStack(spacing: 0) {
                    header(review: review)
                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if !review.renderWarnings.isEmpty {
                                GroupBox("Template Warnings") {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(Array(review.renderWarnings.enumerated()), id: \.offset) { _, warning in
                                            Text(warning)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            ForEach(review.candidates) { candidate in
                                candidateCard(candidate)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(minWidth: 960, minHeight: 680)
            } else {
                ContentUnavailableView(
                    "No Generation Candidates",
                    systemImage: "sparkles",
                    description: Text("Run generation to review and accept outputs.")
                )
                .frame(minWidth: 600, minHeight: 420)
            }
        }
    }

    private func header(review: AppStore.ProseGenerationReviewState) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Generation Candidates")
                    .font(.title3.weight(.semibold))
                Text("Scene: \(review.sceneTitle) • Prompt: \(review.promptTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Beat: \(singleLineSummary(review.beat, maxLength: 120))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if store.isGenerating {
                Button {
                    store.cancelBeatGeneration()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else if !review.candidates.isEmpty {
                Button {
                    store.retryAllProseGenerationCandidates()
                } label: {
                    Label("Retry All", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            Button("Close") {
                store.dismissProseGenerationReview()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func candidateCard(_ candidate: AppStore.ProseGenerationCandidate) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text(candidate.model)
                        .font(.headline)

                    statusBadge(candidate.status)

                    if let elapsedSeconds = candidate.elapsedSeconds {
                        Text(String(format: "%.1fs", elapsedSeconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    if let usage = candidate.usage {
                        candidateUsage(usage)
                    }
                }

                switch candidate.status {
                case .completed:
                    ScrollView {
                        Text(candidate.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(minHeight: 140, maxHeight: 280)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                case .failed:
                    Text(candidate.errorMessage ?? "Generation failed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                case .running:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Generating...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ScrollView {
                                Text(candidate.text)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(minHeight: 100, maxHeight: 220)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                        }
                    }
                case .queued:
                    Text("Queued...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                case .cancelled:
                    Text("Cancelled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }

                HStack(spacing: 8) {
                    Button {
                        store.acceptProseGenerationCandidate(candidate.id)
                        dismiss()
                    } label: {
                        Label("Accept", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(candidate.status != .completed || store.isGenerating)

                    Button {
                        store.retryProseGenerationCandidate(candidate.id)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isGenerating)

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            EmptyView()
        }
    }

    private func statusBadge(_ status: AppStore.ProseGenerationCandidate.Status) -> some View {
        Text(statusLabel(status))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(statusColor(status).opacity(0.15))
            )
    }

    private func statusLabel(_ status: AppStore.ProseGenerationCandidate.Status) -> String {
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

    private func statusColor(_ status: AppStore.ProseGenerationCandidate.Status) -> Color {
        switch status {
        case .queued, .running:
            return .secondary
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }

    private func candidateUsage(_ usage: TokenUsage) -> some View {
        HStack(spacing: 8) {
            if let promptTokens = usage.promptTokens {
                usageChip(icon: "text.quote", value: promptTokens, help: "Prompt tokens.")
            }
            if let completionTokens = usage.completionTokens {
                usageChip(icon: "sparkles", value: completionTokens, help: "Completion tokens.")
            }
            if let totalTokens = usage.totalTokens {
                usageChip(icon: "sum", value: totalTokens, help: "Total tokens.")
            }
            if usage.isEstimated {
                Image(systemName: "questionmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Token counts are estimated.")
            }
        }
    }

    private func usageChip(icon: String, value: Int, help: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(value)")
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private func singleLineSummary(_ value: String, maxLength: Int) -> String {
        let singleLine = value.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count <= maxLength {
            return singleLine
        }
        return String(singleLine.prefix(maxLength)) + "..."
    }
}

private struct BeatInputTextView: NSViewRepresentable {
    private final class MentionInputTextView: NSTextView {
        var onKeyEvent: ((NSEvent) -> Bool)?
        var onDidResignFirstResponder: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            if onKeyEvent?(event) == true {
                return
            }
            super.keyDown(with: event)
        }

        override func resignFirstResponder() -> Bool {
            let didResign = super.resignFirstResponder()
            if didResign {
                onDidResignFirstResponder?()
            }
            return didResign
        }
    }

    @Binding var text: String
    var onSend: () -> Void
    var onMentionQueryChange: (MentionAutocompleteQuery?) -> Void = { _ in }
    var onMentionAnchorChange: (CGPoint?) -> Void = { _ in }
    var isMentionMenuVisible: Bool = false
    var onMentionMove: (Int) -> Void = { _ in }
    var onMentionSelect: () -> Bool = { false }
    var onMentionDismiss: () -> Void = {}
    var focusRequestID: UUID = UUID()

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

        let textView = MentionInputTextView()
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
        textView.textContainerInset = NSSize(width: 6, height: 6)
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

        context.coordinator.attach(to: textView)

        textView.onKeyEvent = { [weak coordinator = context.coordinator] event in
            coordinator?.handleKeyEvent(event) ?? false
        }
        textView.onDidResignFirstResponder = { [weak coordinator = context.coordinator] in
            coordinator?.handleDidResignFirstResponder()
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        var changedTextProgrammatically = false
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: text.count, length: 0))
            changedTextProgrammatically = true
        }
        context.coordinator.isMentionMenuVisible = isMentionMenuVisible
        if changedTextProgrammatically {
            context.coordinator.publishMentionQuery(from: textView)
        }
        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            textView.window?.makeFirstResponder(textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onSend: onSend,
            onMentionQueryChange: onMentionQueryChange,
            onMentionAnchorChange: onMentionAnchorChange,
            onMentionMove: onMentionMove,
            onMentionSelect: onMentionSelect,
            onMentionDismiss: onMentionDismiss
        )
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        private let onSend: () -> Void
        private let onMentionQueryChange: (MentionAutocompleteQuery?) -> Void
        private let onMentionAnchorChange: (CGPoint?) -> Void
        private let onMentionMove: (Int) -> Void
        private let onMentionSelect: () -> Bool
        private let onMentionDismiss: () -> Void
        private weak var trackedTextView: NSTextView?
        private var outsideClickMonitor: Any?
        var isMentionMenuVisible: Bool = false
        var lastFocusRequestID: UUID = UUID()

        init(
            text: Binding<String>,
            onSend: @escaping () -> Void,
            onMentionQueryChange: @escaping (MentionAutocompleteQuery?) -> Void,
            onMentionAnchorChange: @escaping (CGPoint?) -> Void,
            onMentionMove: @escaping (Int) -> Void,
            onMentionSelect: @escaping () -> Bool,
            onMentionDismiss: @escaping () -> Void
        ) {
            self._text = text
            self.onSend = onSend
            self.onMentionQueryChange = onMentionQueryChange
            self.onMentionAnchorChange = onMentionAnchorChange
            self.onMentionMove = onMentionMove
            self.onMentionSelect = onMentionSelect
            self.onMentionDismiss = onMentionDismiss
        }

        func attach(to textView: NSTextView) {
            trackedTextView = textView
            guard outsideClickMonitor == nil else { return }

            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.handleOutsideMouseDown(event)
                return event
            }
        }

        func detach() {
            if let outsideClickMonitor {
                NSEvent.removeMonitor(outsideClickMonitor)
                self.outsideClickMonitor = nil
            }
            trackedTextView = nil
        }

        func handleKeyEvent(_ event: NSEvent) -> Bool {
            // Cmd+Return inserts a newline regardless of mention menu state
            if (event.keyCode == 36 || event.keyCode == 76),
               event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
                trackedTextView?.insertNewlineIgnoringFieldEditor(nil)
                return true
            }

            guard isMentionMenuVisible else { return false }

            switch event.keyCode {
            case 125: // down arrow
                onMentionMove(1)
                return true
            case 126: // up arrow
                onMentionMove(-1)
                return true
            case 53: // escape
                onMentionDismiss()
                return true
            case 48: // tab
                return onMentionSelect()
            case 36, 76: // return / enter
                return onMentionSelect()
            default:
                return false
            }
        }

        func handleDidResignFirstResponder() {
            if isMentionMenuVisible {
                onMentionDismiss()
            }
        }

        private func handleOutsideMouseDown(_ event: NSEvent) {
            guard isMentionMenuVisible else { return }
            guard let textView = trackedTextView else { return }
            guard event.window === textView.window else {
                onMentionDismiss()
                return
            }

            let locationInTextView = textView.convert(event.locationInWindow, from: nil)
            if textView.bounds.contains(locationInTextView) {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.isMentionMenuVisible else { return }
                self.onMentionDismiss()
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            publishMentionQuery(from: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            publishMentionQuery(from: textView)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if isMentionMenuVisible {
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    onMentionMove(1)
                    return true
                }
                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    onMentionMove(-1)
                    return true
                }
                if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    onMentionDismiss()
                    return true
                }
                if commandSelector == #selector(NSResponder.insertTab(_:)) {
                    return onMentionSelect()
                }
                if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                    let flags = NSApp.currentEvent?.modifierFlags ?? []
                    if !flags.contains(.command), onMentionSelect() {
                        return true
                    }
                }
            }

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

        func publishMentionQuery(from textView: NSTextView) {
            let mention = MentionParsing.activeQuery(
                in: textView.string,
                caretLocation: textView.selectedRange().location
            )
            onMentionQueryChange(mention)
            if mention != nil {
                onMentionAnchorChange(caretAnchor(in: textView))
            } else {
                onMentionAnchorChange(nil)
            }
        }

        private func caretAnchor(in textView: NSTextView) -> CGPoint? {
            guard let window = textView.window else { return nil }
            let selection = textView.selectedRange()
            let screenRect = textView.firstRect(forCharacterRange: selection, actualRange: nil)
            let windowPoint = window.convertPoint(fromScreen: screenRect.origin)
            let localPoint = textView.convert(windowPoint, from: nil)
            let yFromTop = textView.isFlipped ? localPoint.y : (textView.bounds.height - localPoint.y)
            return CGPoint(
                x: max(0, localPoint.x),
                y: max(0, yFromTop)
            )
        }
    }
}
