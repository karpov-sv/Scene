import SwiftUI
import AppKit

struct WorkshopChatView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingPayloadPreview: Bool = false
    @State private var payloadPreview: AppStore.WorkshopPayloadPreview?
    private let actionButtonWidth: CGFloat = 126
    private let actionButtonHeight: CGFloat = 30

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

    var body: some View {
        NavigationSplitView {
            sessionsSidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 330)
        } detail: {
            chatDetail
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingPayloadPreview, onDismiss: {
            payloadPreview = nil
        }) {
            if let payloadPreview {
                WorkshopPayloadPreviewSheet(preview: payloadPreview)
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
                messagesList
                Divider()
                composer
            } else {
                ContentUnavailableView("No Chat Selected", systemImage: "bubble.left.and.bubble.right", description: Text("Create or select a chat session."))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Session name", text: selectedSessionNameBinding)
                .font(.headline)

            HStack(spacing: 12) {
                Picker("Prompt", selection: selectedPromptBinding) {
                    Text("Default")
                        .tag(Optional<UUID>.none)
                    ForEach(store.workshopPrompts) { prompt in
                        Text(prompt.title)
                            .tag(Optional(prompt.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300)

                Toggle("Scene Context", isOn: $store.workshopUseSceneContext)
                Toggle("Compendium Context", isOn: $store.workshopUseCompendiumContext)

                Spacer(minLength: 0)
            }

            if !store.workshopStatus.isEmpty {
                Text(store.workshopStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var messagesList: some View {
        List {
            ForEach(store.selectedWorkshopSession?.messages ?? []) { message in
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
                }
                .padding(.vertical, 2)
                .listRowSeparator(.visible)
            }

            if store.workshopIsGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Thinking...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                WorkshopInputTextView(
                    text: $store.workshopInput,
                    onSend: { store.submitWorkshopMessage() }
                )
                .frame(minHeight: 90, idealHeight: 110, maxHeight: 170)

                VStack(alignment: .trailing, spacing: 8) {
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
                            showingPayloadPreview = true
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
            }

            Text("Press Enter to send. Press Cmd+Enter for a newline.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
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
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
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
        textView.textContainerInset = NSSize(width: 8, height: 8)
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
