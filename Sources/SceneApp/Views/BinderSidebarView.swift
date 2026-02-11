import SwiftUI

struct BinderSidebarView: View {
    @EnvironmentObject private var store: AppStore

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
                        Section {
                            ForEach(chapter.scenes) { scene in
                                sceneRow(scene)
                                    .tag(Optional(scene.id))
                            }
                        } header: {
                            chapterHeader(chapter)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Binder")
                .font(.headline)
            Text(store.project.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func chapterHeader(_ chapter: Chapter) -> some View {
        HStack(spacing: 8) {
            Button {
                store.selectChapter(chapter.id)
            } label: {
                Label(chapterTitle(chapter), systemImage: "folder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                store.addScene(to: chapter.id)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Add scene")

            Menu {
                chapterActions(chapter)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .help("Chapter actions")
        }
        .textCase(nil)
    }

    private func sceneRow(_ scene: Scene) -> some View {
        Label(sceneTitle(scene), systemImage: "doc.text")
            .lineLimit(1)
            .padding(.leading, 16)
            .contextMenu {
                sceneActions(scene)
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
    private func sceneActions(_ scene: Scene) -> some View {
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
}
