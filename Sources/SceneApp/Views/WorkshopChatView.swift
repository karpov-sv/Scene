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
    @State private var workshopMentionQuery: MentionAutocompleteQuery?
    @State private var workshopMentionSelectionIndex: Int = 0
    @State private var workshopMentionQueryIdentity: String = ""
    @State private var workshopMentionAnchor: CGPoint?
    @State private var isEditingChatTitle: Bool = false
    @FocusState private var isChatTitleFocused: Bool
    @State private var isRollingMemorySheetPresented: Bool = false
    @State private var rollingMemoryDraft: String = ""
    @State private var editingSessionID: UUID?
    @State private var editingSessionName: String = ""
    @FocusState private var isSessionRenameFocused: Bool
    @State private var confirmDeleteChat: Bool = false
    @State private var pendingClearMessagesSessionID: UUID?
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

    private var sceneContextToggleBinding: Binding<Bool> {
        Binding(
            get: { store.workshopUseSceneContext },
            set: { store.setWorkshopUseSceneContext($0) }
        )
    }

    private var compendiumContextToggleBinding: Binding<Bool> {
        Binding(
            get: { store.workshopUseCompendiumContext },
            set: { store.setWorkshopUseCompendiumContext($0) }
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

    private var workshopMentionSuggestions: [MentionSuggestion] {
        guard let workshopMentionQuery else { return [] }
        return store.mentionSuggestions(for: workshopMentionQuery.trigger, query: workshopMentionQuery.query)
    }

    var body: some View {
        rootLayout
            .sheet(item: $payloadPreview) { payloadPreview in
                WorkshopPayloadPreviewSheet(preview: payloadPreview)
            }
            .sheet(isPresented: $isRollingMemorySheetPresented) {
                WorkshopRollingMemorySheet(
                    sessionTitle: sessionTitleForMemorySheet,
                    updatedAt: store.selectedWorkshopRollingMemoryUpdatedAt,
                    draftSummary: $rollingMemoryDraft,
                    onSave: {
                        store.updateSelectedWorkshopRollingMemory(rollingMemoryDraft)
                    },
                    onClear: {
                        rollingMemoryDraft = ""
                        store.updateSelectedWorkshopRollingMemory("")
                    }
                )
            }
            .alert("Clear Messages", isPresented: clearMessagesAlertBinding) {
                Button("Clear", role: .destructive) {
                    confirmClearMessages()
                }
                Button("Cancel", role: .cancel) {
                    pendingClearMessagesSessionID = nil
                }
            } message: {
                Text("Are you sure you want to clear all messages in \"\(pendingClearMessagesSessionTitle)\"?")
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
                        Group {
                            if editingSessionID == session.id {
                                VStack(alignment: .leading, spacing: 3) {
                                    TextField("Session name", text: $editingSessionName)
                                        .textFieldStyle(.roundedBorder)
                                        .focused($isSessionRenameFocused)
                                        .onSubmit {
                                            commitSessionRename(session.id)
                                        }
                                        .onExitCommand {
                                            editingSessionID = nil
                                        }
                                    Text("\(session.messages.count) messages")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sessionTitle(session))
                                        .lineLimit(1)
                                    Text("\(session.messages.count) messages")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tag(Optional(session.id))
                        .contextMenu {
                            Button {
                                beginSessionRename(session)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button {
                                requestClearMessages(for: session.id)
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
            .onChange(of: isSessionRenameFocused) { _, focused in
                if !focused, let id = editingSessionID {
                    commitSessionRename(id)
                }
            }

            Divider()

            HStack(spacing: 4) {
                Button {
                    store.createWorkshopSession()
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Chat")

                Button {
                    confirmDeleteChat = true
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(store.selectedWorkshopSessionID == nil || !(store.selectedWorkshopSessionID.map { store.canDeleteWorkshopSession($0) } ?? false))
                .help("Delete Chat")

                Spacer(minLength: 0)

                Menu {
                    Button {
                        if let id = store.selectedWorkshopSessionID {
                            requestClearMessages(for: id)
                        }
                    } label: {
                        Label("Clear Messages", systemImage: "trash.slash")
                    }
                    .disabled(store.selectedWorkshopSessionID == nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .help("Chat Actions")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 14, weight: .medium))
            .padding(12)
        }
        .alert("Delete Chat", isPresented: $confirmDeleteChat) {
            Button("Delete", role: .destructive) {
                if let id = store.selectedWorkshopSessionID {
                    store.deleteWorkshopSession(id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(store.selectedWorkshopSession?.name ?? "")\"?")
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if isEditingChatTitle {
                    TextField("Session name", text: selectedSessionNameBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3.weight(.semibold))
                        .focused($isChatTitleFocused)
                        .onSubmit {
                            isEditingChatTitle = false
                        }
                        .onExitCommand {
                            isEditingChatTitle = false
                        }
                        .onChange(of: isChatTitleFocused) { _, focused in
                            if !focused {
                                isEditingChatTitle = false
                            }
                        }
                } else {
                    Text(store.selectedWorkshopSession?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? store.selectedWorkshopSession!.name : "Untitled Chat")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            isEditingChatTitle = true
                            DispatchQueue.main.async {
                                isChatTitleFocused = true
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                rollingMemoryDraft = store.selectedWorkshopRollingMemorySummary
                isRollingMemorySheetPresented = true
            } label: {
                Image(systemName: "text.book.closed")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit Rolling Memory")
            .help("Show and edit rolling memory for this chat.")

            Button {
                if let id = store.selectedWorkshopSession?.id {
                    requestClearMessages(for: id)
                }
            } label: {
                Image(systemName: "trash.slash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Clear Messages")
            .help("Clear all messages in this chat.")
        }
        .padding(12)
    }

    private var sessionTitleForMemorySheet: String {
        guard let session = store.selectedWorkshopSession else { return "Untitled Chat" }
        return sessionTitle(session)
    }

    private var messagesList: some View {
        let messages = store.selectedWorkshopSession?.messages ?? []
        let sessionScrollIdentity = store.selectedWorkshopSessionID?.uuidString ?? "none"

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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

                            WorkshopMessageText(
                                message: message,
                                isStreaming: store.workshopIsGenerating && index == messages.count - 1 && message.role == .assistant
                            )
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
            .id(sessionScrollIdentity)
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear {
                shouldStickToBottom = true
                scheduleScrollToBottom(using: proxy)
            }
            .onChange(of: messagesAutoScrollToken(for: messages)) { _, _ in
                let shouldKeepBottom = shouldStickToBottom
                guard shouldKeepBottom else { return }
                scheduleScrollToBottom(using: proxy)
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
            proxy.scrollTo(messagesBottomAnchorID)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.18), action)
        } else {
            action()
        }
    }

    private func scheduleScrollToBottom(using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            scrollMessagesToBottom(using: proxy, animated: false)
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

                Toggle("Scene Context", isOn: sceneContextToggleBinding)
                    .help("Include the current scene excerpt in workshop prompts. Disabling also blanks scene_tail(...) variables.")
                Toggle("Compendium Context", isOn: compendiumContextToggleBinding)
                    .help("Include selected scene context entries (compendium and linked summaries) in {{context}} variables. Explicit @/# mentions are included either way.")

                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 10) {
                WorkshopInputTextView(
                    text: $store.workshopInput,
                    onSend: { store.submitWorkshopMessage() },
                    onMentionQueryChange: handleWorkshopMentionQueryChange,
                    onMentionAnchorChange: handleWorkshopMentionAnchorChange,
                    isMentionMenuVisible: !workshopMentionSuggestions.isEmpty,
                    onMentionMove: moveWorkshopMentionSelection,
                    onMentionSelect: confirmWorkshopMentionSelection,
                    onMentionDismiss: dismissWorkshopMentionSuggestions,
                    focusRequestID: store.workshopInputFocusRequestID
                )
                .frame(minHeight: actionColumnContentHeight, idealHeight: actionColumnContentHeight, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    GeometryReader { proxy in
                        if !workshopMentionSuggestions.isEmpty, let anchor = workshopMentionAnchor {
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
                                suggestions: workshopMentionSuggestions,
                                selectedIndex: workshopMentionSelectionIndex,
                                availableHeight: availableHeight,
                                onHighlight: { workshopMentionSelectionIndex = $0 },
                                onSelect: applyWorkshopMentionSuggestion
                            )
                            .frame(width: menuWidth)
                            .offset(x: x, y: y)
                            .zIndex(10)
                        }
                    }
                }
                .padding(.leading, 8)
                .frame(minHeight: actionColumnContentHeight, idealHeight: actionColumnContentHeight, maxHeight: .infinity, alignment: .top)

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
                    .frame(width: actionButtonWidth, alignment: .center)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Text("Press Enter to send. Press Cmd+Enter for a newline. Use @ for compendium entries, # for scenes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func beginSessionRename(_ session: WorkshopSession) {
        editingSessionID = session.id
        editingSessionName = session.name
        DispatchQueue.main.async {
            isSessionRenameFocused = true
        }
    }

    private func commitSessionRename(_ sessionID: UUID) {
        let trimmed = editingSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.renameWorkshopSession(sessionID, to: trimmed)
        }
        editingSessionID = nil
    }

    private var clearMessagesAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingClearMessagesSessionID != nil },
            set: { isPresented in
                if !isPresented {
                    pendingClearMessagesSessionID = nil
                }
            }
        )
    }

    private var pendingClearMessagesSessionTitle: String {
        guard let sessionID = pendingClearMessagesSessionID,
              let session = store.workshopSessions.first(where: { $0.id == sessionID }) else {
            return "this chat"
        }
        return sessionTitle(session)
    }

    private func requestClearMessages(for sessionID: UUID) {
        pendingClearMessagesSessionID = sessionID
    }

    private func confirmClearMessages() {
        guard let sessionID = pendingClearMessagesSessionID else { return }
        pendingClearMessagesSessionID = nil
        store.clearWorkshopSessionMessages(sessionID)
    }

    private func sessionTitle(_ session: WorkshopSession) -> String {
        let trimmed = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Chat" : trimmed
    }

    private func historyMenuTitle(_ value: String) -> String {
        let singleLine = value.replacingOccurrences(of: "\n", with: " ")
        return singleLine.count > 80 ? String(singleLine.prefix(80)) + "..." : singleLine
    }

    private func applyWorkshopMentionSuggestion(_ suggestion: MentionSuggestion) {
        guard let workshopMentionQuery else { return }
        guard let updated = MentionParsing.replacingToken(
            in: store.workshopInput,
            range: workshopMentionQuery.tokenRange,
            with: suggestion.insertion
        ) else {
            return
        }
        store.workshopInput = updated
        self.workshopMentionQuery = nil
        self.workshopMentionAnchor = nil
    }

    private func moveWorkshopMentionSelection(_ delta: Int) {
        guard !workshopMentionSuggestions.isEmpty else { return }
        let maxIndex = workshopMentionSuggestions.count - 1
        let next = workshopMentionSelectionIndex + delta
        workshopMentionSelectionIndex = min(max(next, 0), maxIndex)
    }

    private func confirmWorkshopMentionSelection() -> Bool {
        guard !workshopMentionSuggestions.isEmpty else { return false }
        let index = min(max(workshopMentionSelectionIndex, 0), workshopMentionSuggestions.count - 1)
        applyWorkshopMentionSuggestion(workshopMentionSuggestions[index])
        return true
    }

    private func dismissWorkshopMentionSuggestions() {
        workshopMentionQuery = nil
        workshopMentionSelectionIndex = 0
        workshopMentionQueryIdentity = ""
        workshopMentionAnchor = nil
    }

    private func handleWorkshopMentionQueryChange(_ query: MentionAutocompleteQuery?) {
        workshopMentionQuery = query
        let identity = query.map { mention in
            "\(mention.trigger.rawValue)|\(mention.query)|\(mention.tokenRange.location)|\(mention.tokenRange.length)"
        } ?? ""

        if identity != workshopMentionQueryIdentity {
            workshopMentionSelectionIndex = 0
            workshopMentionQueryIdentity = identity
        }

        if query == nil {
            workshopMentionAnchor = nil
        }
    }

    private func handleWorkshopMentionAnchorChange(_ anchor: CGPoint?) {
        workshopMentionAnchor = anchor
    }

}

private struct WorkshopRollingMemorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSummaryEditorFocused: Bool

    let sessionTitle: String
    let updatedAt: Date?
    @Binding var draftSummary: String
    let onSave: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rolling Memory")
                        .font(.title3.weight(.semibold))
                    Text(sessionTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let updatedAt {
                    Text("Updated \(Self.timestampFormatter.string(from: updatedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)

            Divider()

            TextEditor(text: $draftSummary)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .focused($isSummaryEditorFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 8) {
                Button("Clear", role: .destructive) {
                    onClear()
                    dismiss()
                }

                Spacer(minLength: 0)

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    onSave()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 540, minHeight: 360)
        .onAppear {
            DispatchQueue.main.async {
                isSummaryEditorFocused = true
            }
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
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
        private var lastPublishedStickiness: Bool = true
        private var isAdjustingClamp: Bool = false

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
            lastPublishedStickiness = true

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
            guard !isAdjustingClamp else { return }
            guard let scrollView = observedScrollView else { return }
            publishStickiness(for: scrollView)
        }

        private func publishStickiness(for scrollView: NSScrollView) {
            let clipView = scrollView.contentView
            let originY = clampedOriginY(for: scrollView)

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

            let shouldStick = !isDetachedFromBottom
            if shouldStick != lastPublishedStickiness {
                lastPublishedStickiness = shouldStick
                onStickinessChanged(shouldStick)
            }
        }

        private func clampedOriginY(for scrollView: NSScrollView) -> CGFloat {
            let clipView = scrollView.contentView
            let currentOriginY = clipView.bounds.origin.y
            let contentHeight = scrollView.documentView?.bounds.height ?? clipView.bounds.height
            let visibleHeight = clipView.bounds.height
            let maxOriginY = max(contentHeight - visibleHeight, 0)
            let clampedOriginY = min(max(currentOriginY, 0), maxOriginY)

            if abs(clampedOriginY - currentOriginY) > 0.5 {
                isAdjustingClamp = true
                defer { isAdjustingClamp = false }
                var origin = clipView.bounds.origin
                origin.y = clampedOriginY
                clipView.scroll(to: origin)
                scrollView.reflectScrolledClipView(clipView)
            }

            return clampedOriginY
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
    var isStreaming: Bool = false

    var body: some View {
        Group {
            if !isStreaming, message.role == .assistant, let rendered = renderedAssistantMarkdown(message.content) {
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

    var body: some View {
        PayloadPreviewSheetContent(preview: preview)
    }
}

private struct WorkshopInputTextView: NSViewRepresentable {
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
        context.coordinator.requestFocusIfNeeded(
            requestID: focusRequestID,
            textView: textView
        )
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
        private var pendingFocusRequestID: UUID?

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
