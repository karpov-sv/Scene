import SwiftUI

struct SettingsSheetView: View {
    private enum SettingsTab: Hashable {
        case general
        case provider
        case prompts
    }

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .general
    @State private var selectedPromptID: UUID?

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
                        .disabled(store.project.settings.provider != .openAICompatible)

                    if store.project.settings.provider == .openAICompatible {
                        HStack(spacing: 10) {
                            Button("Use LM Studio Default") {
                                store.applyLMStudioEndpointPreset()
                            }

                            Text("http://localhost:1234/v1")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    Stepper(value: requestTimeoutBinding, in: 30 ... 3600, step: 15) {
                        HStack {
                            Text("Request Timeout")
                            Spacer(minLength: 0)
                            Text(timeoutLabel(store.project.settings.requestTimeoutSeconds))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .disabled(store.project.settings.provider != .openAICompatible)

                    SecureField("API Key", text: apiKeyBinding)
                        .textFieldStyle(.roundedBorder)
                        .disabled(store.project.settings.provider != .openAICompatible)

                    TextField("Model", text: modelBinding)
                        .textFieldStyle(.roundedBorder)

                    if store.project.settings.provider == .openAICompatible {
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
                        .disabled(store.project.settings.provider != .openAICompatible)
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
            if store.project.settings.provider == .openAICompatible,
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

                    Text("Template placeholders: \(placeholderHint(for: prompt.category))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private func placeholderHint(for category: PromptCategory) -> String {
        switch category {
        case .workshop:
            return "{scene}, {context}, {conversation}"
        case .prose, .rewrite, .summary:
            return "{beat}, {scene}, {context}"
        }
    }

    private func timeoutLabel(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded % 60 == 0 {
            return "\(rounded / 60) min"
        }
        return "\(rounded) sec"
    }
}
