import SwiftUI
import AppKit

struct CompendiumView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedCategory: CompendiumCategory = .characters

    private var filteredEntries: [CompendiumEntry] {
        store.entries(in: selectedCategory)
    }

    private var entryTitleBinding: Binding<String> {
        Binding(
            get: { store.selectedCompendiumEntry?.title ?? "" },
            set: { store.updateSelectedCompendiumTitle($0) }
        )
    }

    private var entryBodyBinding: Binding<String> {
        Binding(
            get: { store.selectedCompendiumEntry?.body ?? "" },
            set: { store.updateSelectedCompendiumBody($0) }
        )
    }

    private var entryTagsBinding: Binding<String> {
        Binding(
            get: { store.selectedCompendiumEntry?.tags.joined(separator: ", ") ?? "" },
            set: { store.updateSelectedCompendiumTags(from: $0) }
        )
    }

    private var selectedEntryBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedCompendiumID },
            set: { store.selectCompendiumEntry($0) }
        )
    }

    private var selectedEntryCharacterCount: Int {
        store.selectedCompendiumEntry?.body.count ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Picker("", selection: $selectedCategory) {
                ForEach(CompendiumCategory.allCases) { category in
                    Text(category.label).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            List(selection: selectedEntryBinding) {
                ForEach(filteredEntries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entryTitle(entry))
                            .lineLimit(1)
                        if !entry.tags.isEmpty {
                            Text(entry.tags.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .tag(Optional(entry.id))
                }
            }
            .frame(minHeight: 180)

            Divider()

            HStack(spacing: 8) {
                Button {
                    store.addCompendiumEntry(category: selectedCategory)
                } label: {
                    Label("New Entry", systemImage: "plus")
                }

                Button(role: .destructive) {
                    store.deleteSelectedCompendiumEntry()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(store.selectedCompendiumEntry == nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            if store.selectedCompendiumEntry != nil {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Entry title", text: entryTitleBinding)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)

                        TextField("Tags (comma separated)", text: entryTagsBinding)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)

                        Text("Entry Text (\(selectedEntryCharacterCount) chars)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                    TextEditor(text: entryBodyBinding)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay(
                            Rectangle()
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.bottom, 0)
            } else {
                ContentUnavailableView("No Entry Selected", systemImage: "books.vertical", description: Text("Select or add a compendium entry."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            if let selected = store.selectedCompendiumEntry,
               selected.category != selectedCategory {
                store.selectCompendiumEntry(filteredEntries.first?.id)
            }
        }
        .onChange(of: store.selectedCompendiumID) { _, _ in
            syncCategoryWithSelectedEntry()
        }
        .onAppear {
            syncCategoryWithSelectedEntry()
            if store.selectedCompendiumEntry == nil {
                store.selectCompendiumEntry(filteredEntries.first?.id)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Compendium")
                .font(.headline)
            Text("Reference entries for generation context")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func entryTitle(_ entry: CompendiumEntry) -> String {
        let trimmed = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Entry" : trimmed
    }

    private func syncCategoryWithSelectedEntry() {
        guard let selected = store.selectedCompendiumEntry else { return }
        if selected.category != selectedCategory {
            selectedCategory = selected.category
        }
    }
}
