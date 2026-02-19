import SwiftUI

struct NotesPanelView: View {
    @EnvironmentObject private var store: AppStore
    @Binding private var scope: NotesScope
    @State private var notesRevealRequest: RevealableTextEditor.RevealRequest?

    init(scope: Binding<NotesScope>) {
        self._scope = scope
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: {
                switch scope {
                case .project:
                    return store.project.notes
                case .chapter:
                    return store.selectedChapter?.notes ?? ""
                case .scene:
                    return store.selectedScene?.notes ?? ""
                }
            },
            set: { value in
                switch scope {
                case .project:
                    store.updateProjectNotes(value)
                case .chapter:
                    store.updateSelectedChapterNotes(value)
                case .scene:
                    store.updateSelectedSceneNotes(value)
                }
            }
        )
    }

    private var isScopeAvailable: Bool {
        switch scope {
        case .project:
            return true
        case .chapter:
            return store.selectedChapter != nil
        case .scene:
            return store.selectedScene != nil
        }
    }

    private var scopeDescription: String {
        switch scope {
        case .project:
            return "Project: \(store.currentProjectName)"
        case .chapter:
            guard let chapter = store.selectedChapter else {
                return "Chapter: No chapter selected"
            }
            return "Chapter: \(displayChapterTitle(chapter))"
        case .scene:
            guard let scene = store.selectedScene else {
                return "Scene: No scene selected"
            }
            return "Scene: \(displaySceneTitle(scene))"
        }
    }

    private var unavailableScopeMessage: String {
        switch scope {
        case .project:
            return ""
        case .chapter:
            return "Select a chapter to edit chapter notes."
        case .scene:
            return "Select a scene to edit scene notes."
        }
    }

    private var notesDescription: String {
        switch scope {
        case .scene:
            return "Write persistent notes for the selected scene."
        case .chapter:
            return "Write persistent notes for the selected chapter."
        case .project:
            return "Write persistent notes for the whole project."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            notesEditor
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: store.pendingNotesTextReveal?.requestID) { _, _ in
            guard let reveal = store.pendingNotesTextReveal else { return }
            notesRevealRequest = .init(
                id: reveal.requestID,
                location: reveal.location,
                length: reveal.length
            )
            store.consumeNotesTextReveal()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.headline)
                Text(notesDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            
            Divider()
            
            Picker("", selection: $scope) {
                ForEach(NotesScope.allCases) { value in
                    Text(value.title)
                        .tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(6)
            
            Text(scopeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var notesEditor: some View {
        if isScopeAvailable {
            RevealableTextEditor(
                text: notesBinding,
                revealRequest: notesRevealRequest
            )
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                Rectangle()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Text(unavailableScopeMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        }
    }

    private func displayChapterTitle(_ chapter: Chapter) -> String {
        let trimmed = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Chapter" : trimmed
    }

    private func displaySceneTitle(_ scene: Scene) -> String {
        let trimmed = scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Scene" : trimmed
    }
}
