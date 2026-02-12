import SwiftUI
import AppKit

private struct SceneEditorCommand: Equatable {
    enum Action: Equatable {
        case toggleBoldface
        case toggleItalics
        case toggleUnderline
    }

    let id: UUID = UUID()
    let action: Action
}

struct EditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingSceneContextSheet: Bool = false
    @State private var generationPayloadPreview: AppStore.WorkshopPayloadPreview?
    @State private var generationPanelHeight: CGFloat = 0
    @State private var dragStartGenerationHeight: CGFloat?
    @State private var dragStartPointerY: CGFloat?
    @State private var sceneEditorCommand: SceneEditorCommand?

    private let generationButtonWidth: CGFloat = 150
    private let generationButtonHeight: CGFloat = 30
    private let generationButtonSpacing: CGFloat = 8
    private let generationResizeHandleHeight: CGFloat = 10
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
        store.selectedSceneContextCompendiumIDs.count
    }

    private var sceneTitleBinding: Binding<String> {
        Binding(
            get: { store.selectedScene?.title ?? "" },
            set: { store.updateSelectedSceneTitle($0) }
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

            HStack(spacing: 8) {
                Button {
                    sceneEditorCommand = SceneEditorCommand(action: .toggleBoldface)
                } label: {
                    Image(systemName: "bold")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Bold (Cmd+B)")

                Button {
                    sceneEditorCommand = SceneEditorCommand(action: .toggleItalics)
                } label: {
                    Image(systemName: "italic")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Italic (Cmd+I)")

                Button {
                    sceneEditorCommand = SceneEditorCommand(action: .toggleUnderline)
                } label: {
                    Image(systemName: "underline")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Underline (Cmd+U)")

                Spacer(minLength: 0)
            }
        }
        .padding(12)
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
        SceneRichTextEditorView(
            sceneID: store.selectedScene?.id,
            plainText: store.selectedScene?.content ?? "",
            richTextData: store.selectedScene?.contentRTFData,
            command: sceneEditorCommand
        ) { plainText, richTextData in
            store.updateSelectedSceneContent(plainText, richTextData: richTextData)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var generationPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generate From Beat")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)

            HStack {
                Picker("Prompt Template", selection: selectedPromptBinding) {
                    Text("Default")
                        .tag(Optional<UUID>.none)
                    ForEach(store.prosePrompts) { prompt in
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
                    onSend: { store.submitBeatGeneration() }
                )
                    .padding(.leading, 8)
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
            }

            Text("Press Enter to send. Press Cmd+Enter for a newline.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

private struct SceneRichTextEditorView: NSViewRepresentable {
    let sceneID: UUID?
    let plainText: String
    let richTextData: Data?
    let command: SceneEditorCommand?
    let onChange: (String, Data?) -> Void

    private final class SceneEditorTextView: NSTextView {
        var onFormattingShortcut: ((SceneEditorCommand.Action) -> Void)?

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
            force: true
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
            force: false
        )
        context.coordinator.applyCommand(command, to: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let onChange: (String, Data?) -> Void
        private var isApplyingProgrammaticChange: Bool = false
        private var lastSceneID: UUID?
        private var lastHandledCommandID: UUID?

        init(onChange: @escaping (String, Data?) -> Void) {
            self.onChange = onChange
        }

        func applyContent(
            to textView: NSTextView,
            sceneID: UUID?,
            plainText: String,
            richTextData: Data?,
            force: Bool
        ) {
            if isApplyingProgrammaticChange {
                return
            }

            let sceneChanged = lastSceneID != sceneID
            let textChanged = textView.string != plainText
            guard force || sceneChanged || textChanged else {
                return
            }

            let attributed = Self.makeAttributedContent(plainText: plainText, richTextData: richTextData)
            isApplyingProgrammaticChange = true
            textView.textStorage?.setAttributedString(attributed)
            textView.setSelectedRange(NSRange(location: attributed.length, length: 0))
            isApplyingProgrammaticChange = false
            lastSceneID = sceneID
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticChange else { return }
            guard let textView = notification.object as? NSTextView else { return }
            publishChange(from: textView)
        }

        func applyCommand(_ command: SceneEditorCommand?, to textView: NSTextView) {
            guard let command else { return }
            guard lastHandledCommandID != command.id else { return }

            lastHandledCommandID = command.id
            textView.window?.makeFirstResponder(textView)
            applyFormatting(command.action, to: textView)
            publishChange(from: textView)
        }

        func applyFormattingShortcut(_ action: SceneEditorCommand.Action, to textView: NSTextView) {
            applyFormatting(action, to: textView)
            publishChange(from: textView)
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

        private func applyFormatting(_ action: SceneEditorCommand.Action, to textView: NSTextView) {
            switch action {
            case .toggleBoldface:
                toggleFontTrait(.boldFontMask, in: textView)
            case .toggleItalics:
                toggleFontTrait(.italicFontMask, in: textView)
            case .toggleUnderline:
                toggleUnderline(in: textView)
            }
        }

        private func toggleFontTrait(_ trait: NSFontTraitMask, in textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            let fallbackFont = NSFont.preferredFont(forTextStyle: .body)
            let currentTypingFont = (textView.typingAttributes[.font] as? NSFont) ?? textView.font ?? fallbackFont
            let shouldEnableTrait = !selectionHasFontTrait(trait, in: textView)

            if selectedRange.length == 0 {
                let updatedFont = convertedFont(currentTypingFont, toggling: trait, enable: shouldEnableTrait) ?? currentTypingFont
                var typingAttributes = textView.typingAttributes
                typingAttributes[.font] = updatedFont
                textView.typingAttributes = typingAttributes
                return
            }

            guard let textStorage = textView.textStorage else { return }
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: selectedRange, options: []) { value, range, _ in
                let currentFont = (value as? NSFont) ?? currentTypingFont
                let updatedFont = convertedFont(currentFont, toggling: trait, enable: shouldEnableTrait) ?? currentFont
                textStorage.addAttribute(.font, value: updatedFont, range: range)
            }
            textStorage.endEditing()
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

        private func toggleUnderline(in textView: NSTextView) {
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
                return
            }

            guard let textStorage = textView.textStorage else { return }
            if shouldEnableUnderline {
                textStorage.addAttribute(.underlineStyle, value: underlineValue, range: selectedRange)
            } else {
                textStorage.removeAttribute(.underlineStyle, range: selectedRange)
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
