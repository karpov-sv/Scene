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
        NavigationSplitView {
            sessionsSidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 330)
        } detail: {
            chatDetail
        }
        .navigationSplitViewStyle(.balanced)
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

                    Text(message.content)
                        .textSelection(.enabled)
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
                TextField("Message workshop assistant", text: $store.workshopInput, axis: .vertical)
                    .lineLimit(3 ... 8)

                Button {
                    Task {
                        await store.sendWorkshopMessage()
                    }
                } label: {
                    if store.workshopIsGenerating {
                        Label("Sending...", systemImage: "paperplane")
                    } else {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.workshopInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.workshopIsGenerating)
            }

            Text("Use this chat for brainstorming, revisions, and scene analysis.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private func sessionTitle(_ session: WorkshopSession) -> String {
        let trimmed = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Chat" : trimmed
    }
}
