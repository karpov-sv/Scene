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
    enum Action: Equatable {
        case toggleBoldface
        case toggleItalics
        case toggleUnderline
        case replaceSelection(rewrittenText: String, targetRange: SceneEditorRange, emphasizeWithItalics: Bool)
    }

    let id: UUID = UUID()
    let action: Action
}

struct EditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingSceneContextSheet: Bool = false
    @State private var generationPayloadPreview: AppStore.WorkshopPayloadPreview?
    @State private var sceneEditorCommand: SceneEditorCommand?
    @State private var editorSelection: SceneEditorSelection = .empty
    @State private var isRewritingSelection: Bool = false

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

    private var selectedRewritePromptBinding: Binding<UUID?> {
        Binding(
            get: { store.project.selectedRewritePromptID },
            set: { store.setSelectedRewritePrompt($0) }
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

                if editorSelection.hasSelection {
                    Picker("Rewrite Prompt", selection: selectedRewritePromptBinding) {
                        ForEach(store.rewritePrompts) { prompt in
                            Text(prompt.title)
                                .tag(Optional(prompt.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 220)
                    .disabled(isRewritingSelection || store.rewritePrompts.isEmpty)

                    Button {
                        rewriteSelectedText()
                    } label: {
                        Group {
                            if isRewritingSelection {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Rewriting")
                                }
                            } else {
                                Label("Rewrite", systemImage: "text.redaction")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isRewritingSelection || !editorSelection.hasSelection || store.activeRewritePrompt == nil)
                    .help("Rewrite the selected text using the selected rewrite prompt.")
                }

                Spacer(minLength: 0)
            }
        }
        .padding(12)
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
            command: sceneEditorCommand,
            shouldAutoScrollExternalUpdates: store.isGenerating,
            onSelectionChange: { selection in
                editorSelection = selection
            }
        ) { plainText, richTextData in
            store.updateSelectedSceneContent(plainText, richTextData: richTextData)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var generationPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("Generate From Beat")
                    .font(.caption.weight(.semibold))
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

            Text("Press Enter to send. Press Cmd+Enter for a newline.")
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
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private func rewriteSelectedText() {
        guard !isRewritingSelection else { return }
        let selectionSnapshot = editorSelection
        guard selectionSnapshot.hasSelection else { return }

        isRewritingSelection = true

        Task { @MainActor in
            defer {
                isRewritingSelection = false
            }

            do {
                let rewritten = try await store.rewriteSelectedSceneText(selectionSnapshot.text)
                sceneEditorCommand = SceneEditorCommand(
                    action: .replaceSelection(
                        rewrittenText: rewritten,
                        targetRange: selectionSnapshot.range,
                        emphasizeWithItalics: true
                    )
                )
            } catch is CancellationError {
                return
            } catch {
                store.lastError = error.localizedDescription
            }
        }
    }
}

private struct SceneRichTextEditorView: NSViewRepresentable {
    let sceneID: UUID?
    let plainText: String
    let richTextData: Data?
    let command: SceneEditorCommand?
    let shouldAutoScrollExternalUpdates: Bool
    let onSelectionChange: (SceneEditorSelection) -> Void
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
            shouldAutoScrollExternalUpdates: shouldAutoScrollExternalUpdates,
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
            shouldAutoScrollExternalUpdates: shouldAutoScrollExternalUpdates,
            force: false
        )
        context.coordinator.applyCommand(command, to: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange, onChange: onChange)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let onSelectionChange: (SceneEditorSelection) -> Void
        private let onChange: (String, Data?) -> Void
        private var isApplyingProgrammaticChange: Bool = false
        private var lastSceneID: UUID?
        private var lastHandledCommandID: UUID?

        init(onSelectionChange: @escaping (SceneEditorSelection) -> Void, onChange: @escaping (String, Data?) -> Void) {
            self.onSelectionChange = onSelectionChange
            self.onChange = onChange
        }

        func applyContent(
            to textView: NSTextView,
            sceneID: UUID?,
            plainText: String,
            richTextData: Data?,
            shouldAutoScrollExternalUpdates: Bool,
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

            isApplyingProgrammaticChange = true
            if force || sceneChanged {
                let attributed = Self.makeAttributedContent(plainText: plainText, richTextData: richTextData)
                textView.textStorage?.setAttributedString(attributed)
                textView.setSelectedRange(NSRange(location: attributed.length, length: 0))
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
            publishSelection(from: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticChange else { return }
            guard let textView = notification.object as? NSTextView else { return }
            publishChange(from: textView)
            publishSelection(from: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingProgrammaticChange else { return }
            guard let textView = notification.object as? NSTextView else { return }
            publishSelection(from: textView)
        }

        func applyCommand(_ command: SceneEditorCommand?, to textView: NSTextView) {
            guard let command else { return }
            guard lastHandledCommandID != command.id else { return }

            lastHandledCommandID = command.id
            textView.window?.makeFirstResponder(textView)
            switch command.action {
            case .toggleBoldface, .toggleItalics, .toggleUnderline:
                applyFormatting(command.action, to: textView)
            case let .replaceSelection(rewrittenText, targetRange, emphasizeWithItalics):
                replaceSelection(
                    in: textView,
                    targetRange: targetRange,
                    with: rewrittenText,
                    emphasizeWithItalics: emphasizeWithItalics
                )
            }
            publishChange(from: textView)
            publishSelection(from: textView)
        }

        func applyFormattingShortcut(_ action: SceneEditorCommand.Action, to textView: NSTextView) {
            applyFormatting(action, to: textView)
            publishChange(from: textView)
            publishSelection(from: textView)
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

        private func applyFormatting(_ action: SceneEditorCommand.Action, to textView: NSTextView) {
            switch action {
            case .toggleBoldface:
                toggleFontTrait(.boldFontMask, in: textView)
            case .toggleItalics:
                toggleFontTrait(.italicFontMask, in: textView)
            case .toggleUnderline:
                toggleUnderline(in: textView)
            case .replaceSelection:
                break
            }
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                TextField("Search context entries", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)

                Text("\(selectedCount) entr\(selectedCount == 1 ? "y" : "ies") selected for this scene")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

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
            .padding(.vertical, 10)

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
            .padding(.vertical, 10)

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
