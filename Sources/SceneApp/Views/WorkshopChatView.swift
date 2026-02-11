import SwiftUI

struct WorkshopChatView: View {
    @EnvironmentObject private var store: AppStore

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

    var body: some View {
        HSplitView {
            sessionsPanel
                .frame(minWidth: 240, idealWidth: 270, maxWidth: 330)

            chatPanel
                .frame(minWidth: 620)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Conversations")
                    .font(.headline)
                Spacer()
                Button {
                    store.createWorkshopSession()
                } label: {
                    Label("New", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
            }
            .padding(12)

            Divider()

            List(selection: sessionSelectionBinding) {
                ForEach(store.workshopSessions) { session in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.name)
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
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 8) {
                Button {
                    if let id = store.selectedWorkshopSessionID {
                        store.clearWorkshopSessionMessages(id)
                    }
                } label: {
                    Label("Clear", systemImage: "trash.slash")
                }
                .disabled(store.selectedWorkshopSessionID == nil)

                Button(role: .destructive) {
                    if let id = store.selectedWorkshopSessionID {
                        store.deleteWorkshopSession(id)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(store.selectedWorkshopSessionID == nil || !(store.selectedWorkshopSessionID.map { store.canDeleteWorkshopSession($0) } ?? false))
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var chatPanel: some View {
        VStack(spacing: 0) {
            if store.selectedWorkshopSession != nil {
                headerPanel
                Divider()
                messagesPanel
                Divider()
                inputPanel
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Create or select a chat session")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Session name", text: selectedSessionNameBinding)
                .textFieldStyle(.roundedBorder)
                .font(.headline)

            HStack(spacing: 12) {
                Picker("Workshop Prompt", selection: selectedPromptBinding) {
                    Text("Default")
                        .tag(Optional<UUID>.none)
                    ForEach(store.workshopPrompts) { prompt in
                        Text(prompt.title)
                            .tag(Optional(prompt.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280)

                Toggle("Scene Context", isOn: $store.workshopUseSceneContext)
                    .toggleStyle(.switch)
                Toggle("Compendium Context", isOn: $store.workshopUseCompendiumContext)
                    .toggleStyle(.switch)

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

    private var messagesPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(store.selectedWorkshopSession?.messages ?? []) { message in
                        messageBubble(message)
                            .id(message.id)
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
                    }
                }
                .padding(12)
            }
            .onChange(of: store.selectedWorkshopSession?.messages.count ?? 0) { _, _ in
                if let lastID = store.selectedWorkshopSession?.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: WorkshopMessage) -> some View {
        HStack {
            if message.role == .assistant {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assistant")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(message.content)
                        .textSelection(.enabled)
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Spacer(minLength: 48)
            } else {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("You")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(message.content)
                        .textSelection(.enabled)
                        .padding(10)
                        .background(Color.accentColor.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $store.workshopInput)
                .font(.body)
                .frame(minHeight: 90)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text("Use this chat for brainstorming, revisions, and scene analysis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    Task {
                        await store.sendWorkshopMessage()
                    }
                } label: {
                    Label(store.workshopIsGenerating ? "Sending..." : "Send", systemImage: "paperplane.fill")
                }
                .disabled(store.workshopInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.workshopIsGenerating)
            }
        }
        .padding(12)
    }
}
