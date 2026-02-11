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
            get: { store.project.selectedProsePromptID ?? store.prosePrompts.first?.id },
            set: { store.setSelectedProsePrompt($0) }
        )
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
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 940, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("Project Settings")
                .font(.title3.weight(.semibold))
            Spacer()
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Project") {
                    TextField("Project title", text: projectTitleBinding)
                        .textFieldStyle(.roundedBorder)
                }

                GroupBox("Storage") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project file location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("~/Library/Application Support/SceneApp/project.json")
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(4)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var providerTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Connection") {
                    VStack(alignment: .leading, spacing: 10) {
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

                        SecureField("API Key", text: apiKeyBinding)
                            .textFieldStyle(.roundedBorder)
                            .disabled(store.project.settings.provider != .openAICompatible)

                        TextField("Model", text: modelBinding)
                            .textFieldStyle(.roundedBorder)

                        if store.project.settings.provider == .openAICompatible {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
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

                                    Spacer(minLength: 0)

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
                }

                GroupBox("Generation Parameters") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Temperature")
                            Slider(value: temperatureBinding, in: 0.1 ... 1.5, step: 0.1)
                            Text(String(format: "%.1f", store.project.settings.temperature))
                                .frame(width: 34)
                                .monospacedDigit()
                        }

                        Stepper(value: maxTokensBinding, in: 100 ... 4000, step: 50) {
                            Text("Max Tokens: \(store.project.settings.maxTokens)")
                        }
                    }
                }

                GroupBox("Default System Prompt") {
                    TextEditor(text: defaultSystemPromptBinding)
                        .frame(minHeight: 160)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(4)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
                if store.prosePrompts.isEmpty {
                    ContentUnavailableView("No Prompt Templates", systemImage: "text.badge.star", description: Text("Add a template to start configuring prose generation."))
                } else {
                    List(selection: promptListSelectionBinding) {
                        ForEach(store.prosePrompts) { prompt in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(promptTitle(prompt))
                                    .lineLimit(1)
                                Text("Prose template")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(Optional(prompt.id))
                        }
                    }
                    .listStyle(.sidebar)
                }

                Divider()

                HStack(spacing: 8) {
                    Button {
                        store.addProsePrompt()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }

                    Spacer(minLength: 0)

                    Button(role: .destructive) {
                        store.deleteSelectedProsePrompt()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(store.prosePrompts.count <= 1 || store.project.selectedProsePromptID == nil)
                }
                .padding(12)
            }
            .frame(minWidth: 250, idealWidth: 280, maxWidth: 320)

            promptEditorDetail
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if store.project.selectedProsePromptID == nil {
                store.setSelectedProsePrompt(store.prosePrompts.first?.id)
            }
        }
    }

    @ViewBuilder
    private var promptEditorDetail: some View {
        if let prompt = store.activeProsePrompt {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox("Template Properties") {
                        TextField(
                            "Prompt title",
                            text: Binding(
                                get: { prompt.title },
                                set: { store.updatePromptTitle(prompt.id, value: $0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    GroupBox("User Template") {
                        TextEditor(
                            text: Binding(
                                get: { prompt.userTemplate },
                                set: { store.updatePromptUserTemplate(prompt.id, value: $0) }
                            )
                        )
                        .frame(minHeight: 220)
                    }

                    GroupBox("System Template") {
                        TextEditor(
                            text: Binding(
                                get: { prompt.systemTemplate },
                                set: { store.updatePromptSystemTemplate(prompt.id, value: $0) }
                            )
                        )
                        .frame(minHeight: 180)
                    }

                    Text("Template placeholders: {beat}, {scene}, {context}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(4)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        } else {
            ContentUnavailableView("No Prompt Selected", systemImage: "text.badge.star", description: Text("Select a prompt template from the list."))
        }
    }

    private func promptTitle(_ prompt: PromptTemplate) -> String {
        let trimmed = prompt.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Prompt" : trimmed
    }

    private func timeoutLabel(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded % 60 == 0 {
            return "\(rounded / 60) min"
        }
        return "\(rounded) sec"
    }
}
