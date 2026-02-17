import SwiftUI

struct WorkshopConversationsSidebarView: View {
    @EnvironmentObject private var store: AppStore
    let onSelectSession: ((UUID) -> Void)?

    @State private var editingSessionID: UUID?
    @State private var editingSessionName: String = ""
    @FocusState private var isSessionRenameFocused: Bool
    @State private var confirmDeleteChat: Bool = false

    init(onSelectSession: ((UUID) -> Void)? = nil) {
        self.onSelectSession = onSelectSession
    }

    private var sessionSelectionBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedWorkshopSessionID },
            set: { id in
                guard let id else { return }
                store.selectWorkshopSession(id)
                onSelectSession?(id)
            }
        )
    }

    var body: some View {
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
            .onChange(of: isSessionRenameFocused) { _, focused in
                if !focused, let id = editingSessionID {
                    commitSessionRename(id)
                }
            }

            Divider()

            HStack(spacing: 4) {
                Button {
                    store.createWorkshopSession()
                    if let id = store.selectedWorkshopSessionID {
                        onSelectSession?(id)
                    }
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
                            store.clearWorkshopSessionMessages(id)
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

    private func sessionTitle(_ session: WorkshopSession) -> String {
        let trimmed = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Chat" : trimmed
    }
}
