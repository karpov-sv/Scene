import SwiftUI

struct BinderSidebarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var collapsedChapterIDs: Set<UUID> = []
    let onOpenSceneSummary: ((UUID, UUID) -> Void)?
    let onOpenChapterSummary: ((UUID) -> Void)?

    init(
        onOpenSceneSummary: ((UUID, UUID) -> Void)? = nil,
        onOpenChapterSummary: ((UUID) -> Void)? = nil
    ) {
        self.onOpenSceneSummary = onOpenSceneSummary
        self.onOpenChapterSummary = onOpenChapterSummary
    }

    private var selectedSceneBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedSceneID },
            set: { sceneID in
                guard let sceneID else { return }
                guard let chapter = store.chapters.first(where: { chapter in
                    chapter.scenes.contains(where: { $0.id == sceneID })
                }) else {
                    return
                }
                store.selectScene(sceneID, chapterID: chapter.id)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.chapters.isEmpty {
                ContentUnavailableView("No Chapters", systemImage: "folder", description: Text("Create a chapter to start building your binder."))
            } else {
                List(selection: selectedSceneBinding) {
                    ForEach(store.chapters) { chapter in
                        Section(isExpanded: chapterExpandedBinding(chapter.id)) {
                            ForEach(chapter.scenes) { scene in
                                sceneRow(scene, chapterID: chapter.id)
                                    .tag(Optional(scene.id))
                                    .listRowInsets(EdgeInsets(top: 2, leading: 28, bottom: 2, trailing: 8))
                            }
                        } header: {
                            chapterRow(chapter)
                                .contextMenu {
                                    chapterActions(chapter)
                                }
                        }
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()
            footerActions
        }
    }

    private var header: some View {
        Text(projectTitle)
            .font(.headline)
            .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var footerActions: some View {
        HStack(spacing: 14) {
            Button {
                store.addChapter()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("New Chapter")

            Button {
                store.addScene(to: store.selectedChapterID)
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .buttonStyle(.borderless)
            .disabled(store.selectedChapterID == nil)
            .help("New Scene")

            Button {
                store.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Preferences")

            Spacer(minLength: 0)
        }
        .font(.system(size: 14, weight: .medium))
        .padding(12)
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        HStack(spacing: 8) {
            Label(chapterTitle(chapter), systemImage: "folder")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
                .onTapGesture {
                    store.selectChapter(chapter.id)
                }

            Spacer(minLength: 0)
        }
        .textCase(nil)
    }

    private func sceneRow(_ scene: Scene, chapterID: UUID) -> some View {
        Label(sceneTitle(scene), systemImage: "doc.text")
            .lineLimit(1)
            .contextMenu {
                sceneActions(scene, chapterID: chapterID)
            }
    }

    @ViewBuilder
    private func chapterActions(_ chapter: Chapter) -> some View {
        Button {
            store.addScene(to: chapter.id)
        } label: {
            Label("Add Scene", systemImage: "plus")
        }

        Button {
            onOpenChapterSummary?(chapter.id)
        } label: {
            Label("Open Chapter Summary", systemImage: "text.alignleft")
        }

        Button {
            store.moveChapterUp(chapter.id)
        } label: {
            Label("Move Chapter Up", systemImage: "arrow.up")
        }
        .disabled(!store.canMoveChapterUp(chapter.id))

        Button {
            store.moveChapterDown(chapter.id)
        } label: {
            Label("Move Chapter Down", systemImage: "arrow.down")
        }
        .disabled(!store.canMoveChapterDown(chapter.id))

        Button(role: .destructive) {
            store.deleteChapter(chapter.id)
        } label: {
            Label("Delete Chapter", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func sceneActions(_ scene: Scene, chapterID: UUID) -> some View {
        Button {
            onOpenSceneSummary?(scene.id, chapterID)
        } label: {
            Label("Open Scene Summary", systemImage: "text.alignleft")
        }

        Button {
            store.moveSceneUp(scene.id)
        } label: {
            Label("Move Scene Up", systemImage: "arrow.up")
        }
        .disabled(!store.canMoveSceneUp(scene.id))

        Button {
            store.moveSceneDown(scene.id)
        } label: {
            Label("Move Scene Down", systemImage: "arrow.down")
        }
        .disabled(!store.canMoveSceneDown(scene.id))

        Button(role: .destructive) {
            store.deleteScene(scene.id)
        } label: {
            Label("Delete Scene", systemImage: "trash")
        }
    }

    private func chapterTitle(_ chapter: Chapter) -> String {
        let trimmed = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Chapter" : trimmed
    }

    private func sceneTitle(_ scene: Scene) -> String {
        let trimmed = scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Scene" : trimmed
    }

    private var projectTitle: String {
        let trimmed = store.project.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Project" : trimmed
    }

    private func chapterExpandedBinding(_ chapterID: UUID) -> Binding<Bool> {
        Binding(
            get: { !collapsedChapterIDs.contains(chapterID) },
            set: { isExpanded in
                if isExpanded {
                    collapsedChapterIDs.remove(chapterID)
                } else {
                    collapsedChapterIDs.insert(chapterID)
                }
            }
        )
    }
}
