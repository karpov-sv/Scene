import SwiftUI

struct SettingsSheetView: View {
    private enum SettingsTab: Hashable {
        case general
        case provider
        case prompts
    }

    private struct PromptVariableItem: Identifiable {
        let token: String
        let meaning: String
        let id: String

        init(token: String, meaning: String) {
            self.token = token
            self.meaning = meaning
            self.id = "\(token)|\(meaning)"
        }
    }

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .general
    @State private var selectedPromptID: UUID?
    @State private var dataExchangeStatus: String = ""

    private var projectTitleBinding: Binding<String> {
        Binding(
            get: { store.project.title },
            set: { store.updateProjectTitle($0) }
        )
    }

    private var providerBinding: Binding<AIProvider> {
        Binding(
            get: { store.project.settings.provider },
            set: { store.updateProvider($0) }
        )
    }

    private var autosaveEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.project.autosaveEnabled },
            set: { store.updateAutosaveEnabled($0) }
        )
    }

    private var endpointBinding: Binding<String> {
        Binding(
            get: { store.project.settings.endpoint },
            set: { store.updateEndpoint($0) }
        )
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { store.project.settings.apiKey },
            set: { store.updateAPIKey($0) }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { store.project.settings.model },
            set: { store.updateModel($0) }
        )
    }

    private var temperatureBinding: Binding<Double> {
        Binding(
            get: { store.project.settings.temperature },
            set: { store.updateTemperature($0) }
        )
    }

    private var maxTokensBinding: Binding<Int> {
        Binding(
            get: { store.project.settings.maxTokens },
            set: { store.updateMaxTokens($0) }
        )
    }

    private var enableStreamingBinding: Binding<Bool> {
        Binding(
            get: { store.project.settings.enableStreaming },
            set: { store.updateEnableStreaming($0) }
        )
    }

    private var requestTimeoutBinding: Binding<Double> {
        Binding(
            get: { store.project.settings.requestTimeoutSeconds },
            set: { store.updateRequestTimeoutSeconds($0) }
        )
    }

    private var defaultSystemPromptBinding: Binding<String> {
        Binding(
            get: { store.project.settings.defaultSystemPrompt },
            set: { store.updateDefaultSystemPrompt($0) }
        )
    }

    private var promptListSelectionBinding: Binding<UUID?> {
        Binding(
            get: { selectedPromptID },
            set: { selectedPromptID = $0 }
        )
    }

    private var promptCategoriesInEditor: [PromptCategory] {
        let withTemplates = PromptCategory.allCases.filter { !store.prompts(in: $0).isEmpty }
        return withTemplates.isEmpty ? PromptCategory.allCases : withTemplates
    }

    private var activePromptForEditor: PromptTemplate? {
        guard let selectedPromptID else { return nil }
        return store.project.prompts.first(where: { $0.id == selectedPromptID })
    }

    private var canDeleteSelectedPrompt: Bool {
        guard let prompt = activePromptForEditor else { return false }
        return store.prompts(in: prompt.category).count > 1
    }

    private var modelPickerOptions: [String] {
        let current = store.project.settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        var options = store.availableRemoteModels
        if !current.isEmpty && !options.contains(current) {
            options.insert(current, at: 0)
        }
        return options
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            TabView(selection: $selectedTab) {
                generalTab
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }
                    .tag(SettingsTab.general)

                providerTab
                    .tabItem {
                        Label("AI Provider", systemImage: "cpu")
                    }
                    .tag(SettingsTab.provider)

                promptTemplatesTab
                    .tabItem {
                        Label("Prompt Templates", systemImage: "text.badge.star")
                    }
                    .tag(SettingsTab.prompts)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, idealWidth: 940, minHeight: 640, idealHeight: 720)
    }

    private var header: some View {
        HStack {
            Text("Project Settings")
                .font(.title3.weight(.semibold))
            Spacer()
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project")
                        .font(.headline)

                    TextField("Project title", text: projectTitleBinding)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Autosave project changes", isOn: autosaveEnabledBinding)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Storage")
                        .font(.headline)

                    Text("Project file location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.currentProjectPathDisplay)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Data Exchange")
                        .font(.headline)

                    Text("Transfer prompt templates, compendium entries, and full projects as JSON files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text("Prompts")
                            .frame(width: 96, alignment: .leading)
                        Button("Export...") {
                            exportPrompts()
                        }
                        Button("Import...") {
                            importPrompts()
                        }
                    }

                    HStack(spacing: 8) {
                        Text("Compendium")
                            .frame(width: 96, alignment: .leading)
                        Button("Export...") {
                            exportCompendium()
                        }
                        Button("Import...") {
                            importCompendium()
                        }
                    }

                    HStack(spacing: 8) {
                        Text("Project")
                            .frame(width: 96, alignment: .leading)
                        Button("Export...") {
                            exportProjectExchange()
                        }
                        Button("Import...") {
                            importProjectExchange()
                        }
                    }

                    if !dataExchangeStatus.isEmpty {
                        Text(dataExchangeStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(20)
        }
    }

    private var providerTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connection")
                        .font(.headline)

                    Picker("Provider", selection: providerBinding) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }

                    TextField("Endpoint", text: endpointBinding)
                        .textFieldStyle(.roundedBorder)

                    Stepper(value: requestTimeoutBinding, in: 30 ... 3600, step: 15) {
                        HStack {
                            Text("Request Timeout")
                            Spacer(minLength: 0)
                            Text(timeoutLabel(store.project.settings.requestTimeoutSeconds))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    SecureField("API Key", text: apiKeyBinding)
                        .textFieldStyle(.roundedBorder)

                    TextField("Model", text: modelBinding)
                        .textFieldStyle(.roundedBorder)

                    if store.project.settings.provider.supportsModelDiscovery {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                if modelPickerOptions.isEmpty {
                                    Text("No discovered models yet.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Picker("Discovered Models", selection: modelBinding) {
                                        ForEach(modelPickerOptions, id: \.self) { modelID in
                                            Text(modelID).tag(modelID)
                                        }
                                    }
                                }

                                Spacer(minLength: 4)

                                Button {
                                    Task {
                                        await store.refreshAvailableModels(force: true, showErrors: true)
                                    }
                                } label: {
                                    if store.isDiscoveringModels {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Label("Refresh", systemImage: "arrow.clockwise")
                                    }
                                }
                                .disabled(store.isDiscoveringModels)
                            }

                            if !store.modelDiscoveryStatus.isEmpty {
                                Text(store.modelDiscoveryStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Toggle("Enable Streaming Responses", isOn: enableStreamingBinding)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Generation Parameters")
                        .font(.headline)

                    LabeledContent("Temperature") {
                        HStack(spacing: 8) {
                            Slider(value: temperatureBinding, in: 0.1 ... 1.5, step: 0.1)
                            Text(String(format: "%.1f", store.project.settings.temperature))
                                .frame(width: 34, alignment: .trailing)
                                .monospacedDigit()
                        }
                        .frame(minWidth: 260)
                    }

                    Stepper(value: maxTokensBinding, in: 100 ... 4000, step: 50) {
                        HStack {
                            Text("Max Tokens")
                            Spacer(minLength: 0)
                            Text("\(store.project.settings.maxTokens)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Default System Prompt")
                        .font(.headline)

                    TextEditor(text: defaultSystemPromptBinding)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .frame(minHeight: 160)
                }
            }
            .padding(20)
        }
        .task {
            if store.project.settings.provider.supportsModelDiscovery,
               store.availableRemoteModels.isEmpty,
               !store.isDiscoveringModels {
                await store.refreshAvailableModels(showErrors: false)
            }
        }
    }

    private var promptTemplatesTab: some View {
        HSplitView {
            VStack(spacing: 0) {
                if store.project.prompts.isEmpty {
                    ContentUnavailableView("No Prompt Templates", systemImage: "text.badge.star", description: Text("Add a template to start configuring prose generation."))
                } else {
                    List(selection: promptListSelectionBinding) {
                        ForEach(promptCategoriesInEditor, id: \.self) { category in
                            Section(promptSectionTitle(for: category)) {
                                ForEach(store.prompts(in: category)) { prompt in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(promptTitle(prompt))
                                            .lineLimit(1)
                                        Text(promptUsageLabel(for: category))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .tag(Optional(prompt.id))
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }

                Divider()

                HStack(spacing: 8) {
                    Menu {
                        ForEach(PromptCategory.allCases, id: \.self) { category in
                            Button("Add \(promptCategoryName(for: category)) Template") {
                                let newPromptID = store.addPrompt(category: category)
                                selectedPromptID = newPromptID
                                syncRuntimePromptSelection(from: newPromptID)
                            }
                        }
                    } label: {
                        Label("Add Template", systemImage: "plus")
                    }

                    Spacer(minLength: 0)

                    Button {
                        guard let selectedPromptID else { return }
                        let selectedCategory = activePromptForEditor?.category
                        guard store.deletePrompt(selectedPromptID) else { return }

                        if let selectedCategory,
                           let replacement = store.prompts(in: selectedCategory).first {
                            self.selectedPromptID = replacement.id
                        } else {
                            self.selectedPromptID = store.project.prompts.first?.id
                        }

                        syncRuntimePromptSelection(from: self.selectedPromptID)
                    } label: {
                        Label("Delete Template", systemImage: "trash")
                    }
                    .disabled(!canDeleteSelectedPrompt)
                }
                .padding(12)
            }
            .frame(minWidth: 250, idealWidth: 280, maxWidth: 320)

            promptEditorDetail
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selectedPromptID == nil {
                selectedPromptID = store.project.selectedProsePromptID
                    ?? store.project.selectedWorkshopPromptID
                    ?? store.project.prompts.first?.id
            }
            syncRuntimePromptSelection(from: selectedPromptID)
        }
        .onChange(of: selectedPromptID) { _, newValue in
            syncRuntimePromptSelection(from: newValue)
        }
    }

    @ViewBuilder
    private var promptEditorDetail: some View {
        if let prompt = activePromptForEditor {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Template Properties")
                            .font(.headline)

                        Text("\(promptCategoryName(for: prompt.category)) Template")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField(
                            "Prompt title",
                            text: promptTitleBinding(prompt.id)
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("User Template")
                            .font(.headline)

                        TextEditor(text: promptUserTemplateBinding(prompt.id))
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                            .frame(minHeight: 220)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("System Template")
                            .font(.headline)

                        TextEditor(text: promptSystemTemplateBinding(prompt.id))
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                            .frame(minHeight: 180)
                    }

                    promptVariableHelp(currentCategory: prompt.category)
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(
                "No Prompt Selected",
                systemImage: "text.badge.star",
                description: Text("Select a prompt template from the list.")
            )
        }
    }

    private func promptTitle(_ prompt: PromptTemplate) -> String {
        let trimmed = prompt.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Prompt" : trimmed
    }

    private func promptCategoryName(for category: PromptCategory) -> String {
        switch category {
        case .prose:
            return "Writing"
        case .workshop:
            return "Chat"
        case .rewrite:
            return "Rewrite"
        case .summary:
            return "Summary"
        }
    }

    private func promptSectionTitle(for category: PromptCategory) -> String {
        "\(promptCategoryName(for: category)) Templates"
    }

    private func promptUsageLabel(for category: PromptCategory) -> String {
        switch category {
        case .prose:
            return "Used for scene generation"
        case .workshop:
            return "Used for workshop chat"
        case .rewrite:
            return "Used for rewrite requests"
        case .summary:
            return "Used for summary requests"
        }
    }

    private func syncRuntimePromptSelection(from promptID: UUID?) {
        guard let promptID,
              let prompt = store.project.prompts.first(where: { $0.id == promptID }) else {
            return
        }

        switch prompt.category {
        case .prose:
            if store.project.selectedProsePromptID != prompt.id {
                store.setSelectedProsePrompt(prompt.id)
            }
        case .rewrite:
            if store.project.selectedRewritePromptID != prompt.id {
                store.setSelectedRewritePrompt(prompt.id)
            }
        case .summary:
            if store.project.selectedSummaryPromptID != prompt.id {
                store.setSelectedSummaryPrompt(prompt.id)
            }
        case .workshop:
            if store.project.selectedWorkshopPromptID != prompt.id {
                store.setSelectedWorkshopPrompt(prompt.id)
            }
        }
    }

    private func promptTitleBinding(_ promptID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.project.prompts.first(where: { $0.id == promptID })?.title ?? ""
            },
            set: { value in
                store.updatePromptTitle(promptID, value: value)
            }
        )
    }

    private func promptUserTemplateBinding(_ promptID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.project.prompts.first(where: { $0.id == promptID })?.userTemplate ?? ""
            },
            set: { value in
                store.updatePromptUserTemplate(promptID, value: value)
            }
        )
    }

    private func promptSystemTemplateBinding(_ promptID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.project.prompts.first(where: { $0.id == promptID })?.systemTemplate ?? ""
            },
            set: { value in
                store.updatePromptSystemTemplate(promptID, value: value)
            }
        )
    }

    @ViewBuilder
    private func promptVariableHelp(currentCategory: PromptCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Template Variable Help")
                .font(.headline)

            Text("Available placeholders by mode. If a value is unavailable in a mode, the placeholder resolves to an empty string.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(promptCategoryName(for: currentCategory)) mode")
                    .font(.subheadline)

                ForEach(variableHelpItems(for: currentCategory)) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.token)
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 120, alignment: .leading)
                            .foregroundStyle(.secondary)

                        Text(item.meaning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    private func variableHelpItems(for category: PromptCategory) -> [PromptVariableItem] {
        switch category {
        case .prose:
            return [
                .init(token: "{beat}", meaning: "Text from the \"Generate from beat\" input."),
                .init(token: "{scene}", meaning: "Current scene text (recent portion) for continuity."),
                .init(token: "{context}", meaning: "Selected/mentioned scene context from compendium and summaries."),
                .init(token: "{conversation}", meaning: "Empty in writing generation mode."),
            ]
        case .rewrite:
            return [
                .init(token: "{beat}", meaning: "Currently selected text in the editor (the text to rewrite/expand/shorten)."),
                .init(token: "{scene}", meaning: "Current scene text (recent portion) for continuity."),
                .init(token: "{context}", meaning: "Selected scene context from compendium and summaries."),
                .init(token: "{conversation}", meaning: "Empty in rewrite mode."),
            ]
        case .summary:
            return [
                .init(token: "{scene}", meaning: "Source material being summarized: scene text (scene scope) or scene summaries list (chapter scope)."),
                .init(token: "{context}", meaning: "Additional metadata/context: selected scene context (scene scope) or chapter metadata (chapter scope)."),
                .init(token: "{beat}", meaning: "Empty in summary mode."),
                .init(token: "{conversation}", meaning: "Empty in summary mode."),
            ]
        case .workshop:
            return [
                .init(token: "{scene}", meaning: "Current scene excerpt, if scene context is enabled."),
                .init(token: "{context}", meaning: "Selected/mentioned compendium and summary context, if enabled."),
                .init(token: "{conversation}", meaning: "Recent workshop chat transcript (user/assistant turns)."),
                .init(token: "{beat}", meaning: "Empty in workshop mode."),
            ]
        }
    }

    private func timeoutLabel(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded % 60 == 0 {
            return "\(rounded / 60) min"
        }
        return "\(rounded) sec"
    }

    private func exportPrompts() {
        guard let fileURL = ProjectDialogs.choosePromptExportURL(defaultProjectName: store.currentProjectName) else {
            return
        }

        do {
            let count = try store.exportPrompts(to: fileURL)
            dataExchangeStatus = "Exported \(count) prompt template(s)."
        } catch {
            store.lastError = "Prompt export failed: \(error.localizedDescription)"
        }
    }

    private func importPrompts() {
        guard let fileURL = ProjectDialogs.choosePromptImportURL() else {
            return
        }

        do {
            let report = try store.importPrompts(from: fileURL)
            dataExchangeStatus = importStatusMessage(
                prefix: "prompt template",
                importedCount: report.importedCount,
                skippedCount: report.skippedCount
            )

            let hasValidSelection = selectedPromptID.flatMap { selectedID in
                store.project.prompts.first(where: { $0.id == selectedID })
            } != nil
            if !hasValidSelection {
                selectedPromptID = store.project.selectedProsePromptID ?? store.project.prompts.first?.id
            }
        } catch {
            store.lastError = "Prompt import failed: \(error.localizedDescription)"
        }
    }

    private func exportCompendium() {
        guard let fileURL = ProjectDialogs.chooseCompendiumExportURL(defaultProjectName: store.currentProjectName) else {
            return
        }

        do {
            let count = try store.exportCompendium(to: fileURL)
            dataExchangeStatus = "Exported \(count) compendium entr\(count == 1 ? "y" : "ies")."
        } catch {
            store.lastError = "Compendium export failed: \(error.localizedDescription)"
        }
    }

    private func importCompendium() {
        guard let fileURL = ProjectDialogs.chooseCompendiumImportURL() else {
            return
        }

        do {
            let report = try store.importCompendium(from: fileURL)
            dataExchangeStatus = importStatusMessage(
                prefix: "compendium entry",
                importedCount: report.importedCount,
                skippedCount: report.skippedCount
            )
        } catch {
            store.lastError = "Compendium import failed: \(error.localizedDescription)"
        }
    }

    private func exportProjectExchange() {
        guard let fileURL = ProjectDialogs.chooseProjectExchangeExportURL(defaultProjectName: store.currentProjectName) else {
            return
        }

        do {
            try store.exportProjectExchange(to: fileURL)
            dataExchangeStatus = "Exported full project JSON."
        } catch {
            store.lastError = "Project export failed: \(error.localizedDescription)"
        }
    }

    private func importProjectExchange() {
        guard let fileURL = ProjectDialogs.chooseProjectExchangeImportURL() else {
            return
        }
        guard ProjectDialogs.confirmProjectImportReplacement() else {
            return
        }

        do {
            try store.importProjectExchange(from: fileURL)
            selectedPromptID = store.project.selectedProsePromptID
                ?? store.project.selectedWorkshopPromptID
                ?? store.project.prompts.first?.id
            dataExchangeStatus = "Imported full project JSON."
        } catch {
            store.lastError = "Project import failed: \(error.localizedDescription)"
        }
    }

    private func importStatusMessage(
        prefix: String,
        importedCount: Int,
        skippedCount: Int
    ) -> String {
        let importedLabel = "\(importedCount) \(prefix)\(importedCount == 1 ? "" : "s")"
        if skippedCount > 0 {
            return "Imported \(importedLabel), skipped \(skippedCount) invalid item(s)."
        }
        return "Imported \(importedLabel)."
    }
}
