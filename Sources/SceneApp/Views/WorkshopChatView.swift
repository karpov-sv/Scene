import SwiftUI
import AppKit

struct WorkshopChatView: View {
    enum Layout {
        case splitSidebar
        case embeddedTrailingSessions
    }

    let layout: Layout
    let showsConversationsSidebar: Bool

    init(layout: Layout, showsConversationsSidebar: Bool = true) {
        self.layout = layout
        self.showsConversationsSidebar = showsConversationsSidebar
    }

    @EnvironmentObject private var store: AppStore
    @State private var payloadPreview: AppStore.WorkshopPayloadPreview?
    @State private var shouldStickToBottom: Bool = true
    private let actionButtonWidth: CGFloat = 126
    private let actionButtonHeight: CGFloat = 30
    private let actionButtonSpacing: CGFloat = 8
    private let messagesMinimumHeight: CGFloat = 180
    private let messagesBottomAnchorID = "workshop-messages-bottom-anchor"
    private let autoScrollBottomTolerance: CGFloat = 20

    private var actionColumnContentHeight: CGFloat {
        (actionButtonHeight * 3) + (actionButtonSpacing * 2)
    }

    private var composerMinimumHeight: CGFloat {
        actionColumnContentHeight + 84
    }

    private var composerInitialHeight: CGFloat {
        composerMinimumHeight
    }

    private var sessionSelectionBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedWorkshopSessionID },
            set: { id in
                guard let id else { return }
                store.selectWorkshopSession(id)
            }
        )
    }

    private var selectedPromptBinding: Binding<UUID?> {
        Binding(
            get: { store.project.selectedWorkshopPromptID },
            set: { store.setSelectedWorkshopPrompt($0) }
        )
    }

    private var selectedSessionNameBinding: Binding<String> {
        Binding(
            get: { store.selectedWorkshopSession?.name ?? "" },
            set: { value in
                guard let id = store.selectedWorkshopSessionID else { return }
                store.renameWorkshopSession(id, to: value)
            }
        )
    }

    private var workshopHistory: [String] {
        store.workshopInputHistory
    }

    private var currentSceneTitle: String {
        guard let scene = store.selectedScene else {
            return "No scene selected"
        }
        let trimmed = scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Scene" : trimmed
    }

    private var selectedCompendiumCount: Int {
        store.selectedSceneContextTotalCount
    }

    var body: some View {
        rootLayout
            .sheet(item: $payloadPreview) { payloadPreview in
                WorkshopPayloadPreviewSheet(preview: payloadPreview)
            }
    }

    @ViewBuilder
    private var rootLayout: some View {
        switch layout {
        case .splitSidebar:
            splitLayout
        case .embeddedTrailingSessions:
            embeddedLayout
        }
    }

    @ViewBuilder
    private var splitLayout: some View {
        if showsConversationsSidebar {
            NavigationSplitView {
                sessionsSidebar
                    .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 330)
            } detail: {
                chatDetail
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            chatDetail
        }
    }

    private var embeddedLayout: some View {
        Group {
            if showsConversationsSidebar {
                HSplitView {
                    chatDetail
                        .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

                    sessionsSidebar
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chatDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var sessionsSidebar: some View {
        VStack(spacing: 0) {
            List(selection: sessionSelectionBinding) {
                Section("Conversations") {
                    ForEach(store.workshopSessions) { session in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sessionTitle(session))
                                .lineLimit(1)
                            Text("\(session.messages.count) messages")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(Optional(session.id))
                        .contextMenu {
                            Button {
                                store.clearWorkshopSessionMessages(session.id)
                            } label: {
                                Label("Clear Messages", systemImage: "trash.slash")
                            }

                            Button(role: .destructive) {
                                store.deleteWorkshopSession(session.id)
                            } label: {
                                Label("Delete Chat", systemImage: "trash")
                            }
                            .disabled(!store.canDeleteWorkshopSession(session.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 8) {
                Button {
                    store.createWorkshopSession()
                } label: {
                    Label("New Chat", systemImage: "plus")
                }

                Spacer(minLength: 0)

                Menu {
                    Button {
                        if let id = store.selectedWorkshopSessionID {
                            store.clearWorkshopSessionMessages(id)
                        }
                    } label: {
                        Label("Clear Messages", systemImage: "trash.slash")
                    }
                    .disabled(store.selectedWorkshopSessionID == nil)

                    Button(role: .destructive) {
                        if let id = store.selectedWorkshopSessionID {
                            store.deleteWorkshopSession(id)
                        }
                    } label: {
                        Label("Delete Chat", systemImage: "trash")
                    }
                    .disabled(store.selectedWorkshopSessionID == nil || !(store.selectedWorkshopSessionID.map { store.canDeleteWorkshopSession($0) } ?? false))
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
            }
            .padding(12)
        }
    }

    private var chatDetail: some View {
        VStack(spacing: 0) {
            if store.selectedWorkshopSession != nil {
                header
                Divider()
                chatSplit
            } else {
                ContentUnavailableView("No Chat Selected", systemImage: "bubble.left.and.bubble.right", description: Text("Create or select a chat session."))
            }
        }
    }

    private var chatSplit: some View {
        VSplitView {
            messagesList
                .frame(minHeight: messagesMinimumHeight, maxHeight: .infinity)
                .layoutPriority(1)

            composer
                .frame(minHeight: composerMinimumHeight, idealHeight: composerInitialHeight, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Session name", text: selectedSessionNameBinding)
                .textFieldStyle(.roundedBorder)
                .font(.title3.weight(.semibold))
        }
        .padding(12)
    }

    private var messagesList: some View {
        let messages = store.selectedWorkshopSession?.messages ?? []

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    WorkshopMessagesScrollObserverView(tolerance: autoScrollBottomTolerance) { shouldStick in
                        shouldStickToBottom = shouldStick
                    }
                    .frame(height: 0)

                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: message.role == .assistant ? "sparkles" : "person.fill")
                                    .foregroundStyle(.secondary)
                                Text(message.role == .assistant ? "Assistant" : "You")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            WorkshopMessageText(message: message)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if index == messages.count - 1 {
                                lastMessageControls
                                    .padding(.top, 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                        Divider()
                }

                    if store.workshopIsGenerating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(messagesBottomAnchorID)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear {
                shouldStickToBottom = true
                DispatchQueue.main.async {
                    scrollMessagesToBottom(using: proxy, animated: false)
                }
            }
            .onChange(of: store.selectedWorkshopSessionID) { _, _ in
                shouldStickToBottom = true
                DispatchQueue.main.async {
                    scrollMessagesToBottom(using: proxy, animated: false)
                }
            }
            .onChange(of: messagesAutoScrollToken(for: messages)) { _, _ in
                let shouldKeepBottom = shouldStickToBottom
                guard shouldKeepBottom else { return }
                DispatchQueue.main.async {
                    scrollMessagesToBottom(using: proxy, animated: false)
                }
            }
        }
    }

    private var lastMessageControls: some View {
        HStack(spacing: 8) {
            if let usage = store.inlineWorkshopUsage {
                usageMetricsView(usage)
            }

            Spacer(minLength: 0)

            Button {
                store.retryLastWorkshopTurn()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Regenerate the latest user turn.")
            .disabled(!store.canRetryLastWorkshopTurn)

            Button {
                store.deleteLastWorkshopAssistantMessage()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Delete the latest assistant message.")
            .disabled(!store.canDeleteLastWorkshopAssistantMessage)

            Button {
                store.deleteLastWorkshopUserTurn()
            } label: {
                Image(systemName: "trash.slash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Delete the latest user message and any replies after it.")
            .disabled(!store.canDeleteLastWorkshopUserTurn)
        }
        .foregroundStyle(.secondary)
    }

    private func usageMetricsView(_ usage: TokenUsage) -> some View {
        HStack(spacing: 8) {
            if let promptTokens = usage.promptTokens {
                usageMetric(
                    icon: "text.quote",
                    value: promptTokens,
                    help: "Prompt tokens sent to the model."
                )
            }

            if let completionTokens = usage.completionTokens {
                usageMetric(
                    icon: "sparkles",
                    value: completionTokens,
                    help: "Completion tokens generated by the model."
                )
            }

            if let totalTokens = usage.totalTokens {
                usageMetric(
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

    private func usageMetric(icon: String, value: Int, help: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(value)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private func messagesAutoScrollToken(for messages: [WorkshopMessage]) -> String {
        let sessionID = store.selectedWorkshopSessionID?.uuidString ?? "none"
        let lastID = messages.last?.id.uuidString ?? "none"
        let lastLength = messages.last?.content.count ?? 0
        let isGenerating = store.workshopIsGenerating ? 1 : 0
        return "\(sessionID)|\(messages.count)|\(lastID)|\(lastLength)|\(isGenerating)"
    }


    private func scrollMessagesToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(messagesBottomAnchorID, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.18), action)
        } else {
            action()
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scene: \(currentSceneTitle) | Context entries: \(selectedCompendiumCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)

            HStack(spacing: 12) {
                Picker("Prompt Template", selection: selectedPromptBinding) {
                    Text("Default")
                        .tag(Optional<UUID>.none)
                    ForEach(store.workshopPrompts) { prompt in
                        Text(prompt.title)
                            .tag(Optional(prompt.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 300)
                .padding(.leading, 8)

                Toggle("Scene Context", isOn: $store.workshopUseSceneContext)
                Toggle("Compendium Context", isOn: $store.workshopUseCompendiumContext)

                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 10) {
                WorkshopInputTextView(
                    text: $store.workshopInput,
                    onSend: { store.submitWorkshopMessage() }
                )
                .padding(.leading, 8)
                .frame(minHeight: actionColumnContentHeight, idealHeight: actionColumnContentHeight, maxHeight: .infinity)

                VStack(alignment: .trailing, spacing: actionButtonSpacing) {
                    Menu {
                        if workshopHistory.isEmpty {
                            Button("No previous prompts") {}
                                .disabled(true)
                        } else {
                            ForEach(workshopHistory, id: \.self) { entry in
                                Button(historyMenuTitle(entry)) {
                                    store.applyWorkshopInputFromHistory(entry)
                                }
                            }
                        }
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(height: actionButtonHeight)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(workshopHistory.isEmpty)
                    .frame(width: actionButtonWidth, alignment: .center)

                    Button {
                        do {
                            payloadPreview = try store.makeWorkshopPayloadPreview()
                        } catch {
                            store.lastError = error.localizedDescription
                        }
                    } label: {
                        Label("Preview", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(store.workshopIsGenerating)
                    .frame(width: actionButtonWidth, alignment: .center)

                    Button {
                        if store.workshopIsGenerating {
                            store.cancelWorkshopMessage()
                        } else {
                            store.submitWorkshopMessage()
                        }
                    } label: {
                        Group {
                            if store.workshopIsGenerating {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Stop")
                                }
                            } else {
                                Label("Send", systemImage: "paperplane.fill")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: actionButtonHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(store.workshopIsGenerating ? .red : .accentColor)
                    .disabled(!store.workshopIsGenerating && store.workshopInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .frame(width: actionButtonWidth, alignment: .center)
                }
                .fixedSize(horizontal: false, vertical: true)
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

    private func sessionTitle(_ session: WorkshopSession) -> String {
        let trimmed = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Chat" : trimmed
    }

    private func historyMenuTitle(_ value: String) -> String {
        let singleLine = value.replacingOccurrences(of: "\n", with: " ")
        return singleLine.count > 80 ? String(singleLine.prefix(80)) + "..." : singleLine
    }

}

private struct WorkshopMessagesScrollObserverView: NSViewRepresentable {
    let tolerance: CGFloat
    let onStickinessChanged: (Bool) -> Void

    @MainActor
    final class Coordinator: NSObject {
        var tolerance: CGFloat
        var onStickinessChanged: (Bool) -> Void
        private weak var observedScrollView: NSScrollView?
        private var lastOriginY: CGFloat?
        private var isDetachedFromBottom: Bool = false

        init(tolerance: CGFloat, onStickinessChanged: @escaping (Bool) -> Void) {
            self.tolerance = tolerance
            self.onStickinessChanged = onStickinessChanged
            super.init()
        }

        func attachIfNeeded(from view: NSView) {
            guard let scrollView = view.enclosingScrollView else {
                DispatchQueue.main.async { [weak view] in
                    guard let view else { return }
                    self.attachIfNeeded(from: view)
                }
                return
            }
            if observedScrollView === scrollView {
                publishStickiness(for: scrollView)
                return
            }

            detach()
            observedScrollView = scrollView
            lastOriginY = nil
            isDetachedFromBottom = false

            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )

            publishStickiness(for: scrollView)
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            observedScrollView = nil
            lastOriginY = nil
            isDetachedFromBottom = false
        }

        @objc
        private func handleBoundsDidChange(_ notification: Notification) {
            guard let scrollView = observedScrollView else { return }
            publishStickiness(for: scrollView)
        }

        private func publishStickiness(for scrollView: NSScrollView) {
            let clipView = scrollView.contentView
            let originY = clipView.bounds.origin.y

            if let lastOriginY, originY < lastOriginY - 0.5 {
                isDetachedFromBottom = true
            }
            lastOriginY = originY

            let visibleBottom = clipView.bounds.maxY
            let contentBottom = scrollView.documentView?.bounds.maxY ?? visibleBottom
            let isAtBottom = contentBottom - visibleBottom <= tolerance

            if isAtBottom {
                isDetachedFromBottom = false
            }

            onStickinessChanged(!isDetachedFromBottom)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tolerance: tolerance, onStickinessChanged: onStickinessChanged)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.tolerance = tolerance
        context.coordinator.onStickinessChanged = onStickinessChanged
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: nsView)
        }
    }
}

private struct WorkshopMessageText: View {
    let message: WorkshopMessage

    var body: some View {
        Group {
            if message.role == .assistant, let rendered = renderedAssistantMarkdown(message.content) {
                Text(rendered)
            } else {
                Text(message.content)
            }
        }
        .textSelection(.enabled)
    }

    private func renderedAssistantMarkdown(_ content: String) -> AttributedString? {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return try? AttributedString(markdown: content, options: options)
    }
}

private struct WorkshopPayloadPreviewSheet: View {
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
                        JSONSyntaxTextView(text: preview.bodyJSON)
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

private struct JSONSyntaxTextView: NSViewRepresentable {
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

private struct WorkshopInputTextView: NSViewRepresentable {
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
