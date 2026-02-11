import SwiftUI

struct BinderSidebarView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(store.chapters) { chapter in
                        chapterBlock(chapter)
                    }
                }
                .padding(10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
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

    @ViewBuilder
    private func chapterBlock(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    store.selectChapter(chapter.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text(chapter.title)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(store.selectedChapterID == chapter.id ? Color.accentColor.opacity(0.18) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button {
                    store.addScene(to: chapter.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderless)
                .help("Add scene")

                Button {
                    store.moveChapterUp(chapter.id)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(!store.canMoveChapterUp(chapter.id))
                .help("Move chapter up")

                Button {
                    store.moveChapterDown(chapter.id)
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(!store.canMoveChapterDown(chapter.id))
                .help("Move chapter down")

                Button(role: .destructive) {
                    store.deleteChapter(chapter.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Delete chapter")
            }

            ForEach(chapter.scenes) { scene in
                HStack(spacing: 4) {
                    Button {
                        store.selectScene(scene.id, chapterID: chapter.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            Text(scene.title)
                                .lineLimit(1)
                        }
                        .padding(.leading, 18)
                        .padding(.trailing, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(store.selectedSceneID == scene.id ? Color.accentColor.opacity(0.22) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.moveSceneUp(scene.id)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!store.canMoveSceneUp(scene.id))
                    .help("Move scene up")

                    Button {
                        store.moveSceneDown(scene.id)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!store.canMoveSceneDown(scene.id))
                    .help("Move scene down")
                }
                .contextMenu {
                    Button {
                        store.moveSceneUp(scene.id)
                    } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    .disabled(!store.canMoveSceneUp(scene.id))

                    Button {
                        store.moveSceneDown(scene.id)
                    } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                    .disabled(!store.canMoveSceneDown(scene.id))

                    Button(role: .destructive) {
                        store.deleteScene(scene.id)
                    } label: {
                        Label("Delete Scene", systemImage: "trash")
                    }
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
