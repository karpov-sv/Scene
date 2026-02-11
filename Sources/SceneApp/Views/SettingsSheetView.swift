import SwiftUI

struct SettingsSheetView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

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

    private var defaultSystemPromptBinding: Binding<String> {
        Binding(
            get: { store.project.settings.defaultSystemPrompt },
            set: { store.updateDefaultSystemPrompt($0) }
        )
    }

    private var selectedPromptBinding: Binding<UUID?> {
        Binding(
            get: { store.project.selectedProsePromptID },
            set: { store.setSelectedProsePrompt($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Project Settings")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)

            Divider()

            Form {
                Section("Project") {
                    TextField("Project title", text: projectTitleBinding)
                }

                Section("Generation Provider") {
                    Picker("Provider", selection: providerBinding) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }

                    TextField("Endpoint", text: endpointBinding)
                        .disabled(store.project.settings.provider != .openAICompatible)

                    SecureField("API Key", text: apiKeyBinding)
                        .disabled(store.project.settings.provider != .openAICompatible)

                    TextField("Model", text: modelBinding)

                    HStack {
                        Text("Temperature")
                        Slider(value: temperatureBinding, in: 0.1 ... 1.5, step: 0.1)
                        Text(String(format: "%.1f", store.project.settings.temperature))
                            .frame(width: 34)
                    }

                    Stepper(value: maxTokensBinding, in: 100 ... 4000, step: 50) {
                        Text("Max Tokens: \(store.project.settings.maxTokens)")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Default System Prompt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: defaultSystemPromptBinding)
                            .frame(minHeight: 90)
                    }
                }

                Section("Prose Prompt Templates") {
                    HStack {
                        Picker("Active Prompt", selection: selectedPromptBinding) {
                            Text("Default")
                                .tag(Optional<UUID>.none)
                            ForEach(store.prosePrompts) { prompt in
                                Text(prompt.title)
                                    .tag(Optional(prompt.id))
                            }
                        }
                        .frame(maxWidth: 280)

                        Button {
                            store.addProsePrompt()
                        } label: {
                            Label("Add", systemImage: "plus")
                        }

                        Button(role: .destructive) {
                            store.deleteSelectedProsePrompt()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(store.prosePrompts.count <= 1)
                    }

                    if let prompt = store.activeProsePrompt {
                        TextField(
                            "Prompt title",
                            text: Binding(
                                get: { prompt.title },
                                set: { store.updatePromptTitle(prompt.id, value: $0) }
                            )
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text("User Template")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(
                                text: Binding(
                                    get: { prompt.userTemplate },
                                    set: { store.updatePromptUserTemplate(prompt.id, value: $0) }
                                )
                            )
                            .frame(minHeight: 130)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("System Template")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(
                                text: Binding(
                                    get: { prompt.systemTemplate },
                                    set: { store.updatePromptSystemTemplate(prompt.id, value: $0) }
                                )
                            )
                            .frame(minHeight: 110)
                        }

                        Text("Template placeholders: {beat}, {scene}, {context}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 820, height: 700)
    }
}
