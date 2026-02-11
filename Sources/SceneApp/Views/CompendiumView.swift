import SwiftUI

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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Picker("Category", selection: $selectedCategory) {
                ForEach(CompendiumCategory.allCases) { category in
                    Text(category.label).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], 12)

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
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider()

            if store.selectedCompendiumEntry != nil {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Entry title", text: entryTitleBinding)

                    TextField("Tags (comma separated)", text: entryTagsBinding)

                    Text("Entry Text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: entryBodyBinding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(12)
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
        .onAppear {
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
}
