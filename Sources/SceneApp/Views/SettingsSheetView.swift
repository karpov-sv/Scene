import SwiftUI
import AppKit

private extension CodableRGBA {
    static let settingsColorComponentScale: Double = 255.0
    static let settingsColorTolerance: Double = 0.5 / settingsColorComponentScale

    static func settingsFrom(nsColor: NSColor) -> CodableRGBA? {
        guard let resolved = nsColor.usingColorSpace(.deviceRGB) else { return nil }
        return CodableRGBA(
            red: settingsQuantize(Double(resolved.redComponent)),
            green: settingsQuantize(Double(resolved.greenComponent)),
            blue: settingsQuantize(Double(resolved.blueComponent)),
            alpha: settingsQuantize(Double(resolved.alphaComponent))
        )
    }

    static func settingsAreClose(_ lhs: CodableRGBA?, _ rhs: CodableRGBA?) -> Bool {
        switch (lhs, rhs) {
        case let (left?, right?):
            return abs(left.red - right.red) <= settingsColorTolerance &&
            abs(left.green - right.green) <= settingsColorTolerance &&
            abs(left.blue - right.blue) <= settingsColorTolerance &&
            abs(left.alpha - right.alpha) <= settingsColorTolerance
        case (nil, nil):
            return true
        default:
            return false
        }
    }

    private static func settingsQuantize(_ component: Double) -> Double {
        let clamped = min(1.0, max(0.0, component))
        return (clamped * settingsColorComponentScale).rounded() / settingsColorComponentScale
    }
}

struct SettingsSheetView: View {
    private enum SettingsTab: String, Hashable {
        case general
        case textGeneration
        case editor
        case provider
        case prompts
    }

    private enum EditorSpacingField: Hashable {
        case lineHeight
        case horizontalMargin
        case verticalMargin
    }

    private enum MetadataField {
        case author
        case language
        case publisher
        case rights
        case description
    }

    private enum PromptField {
        case title
        case userTemplate
        case systemTemplate
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
    @AppStorage("SceneApp.ui.settingsTab")
    private var storedSettingsTabRawValue: String = SettingsTab.general.rawValue
    @AppStorage("SceneApp.ui.settingsPromptTemplateID")
    private var storedSettingsPromptTemplateID: String = ""
    @State private var selectedTab: SettingsTab = .general
    @State private var selectedPromptID: UUID?
    @State private var dataExchangeStatus: String = ""
    @State private var promptTemplateStatus: String = ""
    @State private var promptRenderPreview: AppStore.PromptTemplateRenderPreview?
    @State private var showBuiltInTemplateResetConfirmation: Bool = false
    @State private var confirmDeletePrompt: Bool = false
    @State private var confirmClearPrompts: Bool = false
    @State private var editorFontPanelOpenRequestID: UUID?
    @State private var lineHeightDraft: String = ""
    @State private var hPaddingDraft: String = ""
    @State private var vPaddingDraft: String = ""
    @FocusState private var focusedEditorSpacingField: EditorSpacingField?

    private func metadataBinding(_ field: MetadataField) -> Binding<String> {
        Binding(
            get: {
                switch field {
                case .author:
                    return store.project.metadata.author ?? ""
                case .language:
                    return store.project.metadata.language ?? ""
                case .publisher:
                    return store.project.metadata.publisher ?? ""
                case .rights:
                    return store.project.metadata.rights ?? ""
                case .description:
                    return store.project.metadata.description ?? ""
                }
            },
            set: { value in
                switch field {
                case .author:
                    store.updateProjectAuthor(value)
                case .language:
                    store.updateProjectLanguage(value)
                case .publisher:
                    store.updateProjectPublisher(value)
                case .rights:
                    store.updateProjectRights(value)
                case .description:
                    store.updateProjectDescription(value)
                }
            }
        )
    }

    private func promptBinding(_ promptID: UUID, field: PromptField) -> Binding<String> {
        Binding(
            get: {
                guard let prompt = store.project.prompts.first(where: { $0.id == promptID }) else { return "" }
                switch field {
                case .title:
                    return prompt.title
                case .userTemplate:
                    return prompt.userTemplate
                case .systemTemplate:
                    return prompt.systemTemplate
                }
            },
            set: { value in
                switch field {
                case .title:
                    store.updatePromptTitle(promptID, value: value)
                case .userTemplate:
                    store.updatePromptUserTemplate(promptID, value: value)
                case .systemTemplate:
                    store.updatePromptSystemTemplate(promptID, value: value)
                }
            }
        )
    }

    private var projectTitleBinding: Binding<String> {
        Binding(
            get: { store.project.title },
            set: { store.updateProjectTitle($0) }
        )
    }

    private var projectAuthorBinding: Binding<String> {
        metadataBinding(.author)
    }

    private var projectLanguageBinding: Binding<String> {
        metadataBinding(.language)
    }

    private var projectPublisherBinding: Binding<String> {
        metadataBinding(.publisher)
    }

    private var projectRightsBinding: Binding<String> {
        metadataBinding(.rights)
    }

    private var projectDescriptionBinding: Binding<String> {
        metadataBinding(.description)
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

    private var markRewrittenTextAsItalicsBinding: Binding<Bool> {
        Binding(
            get: { store.project.settings.markRewrittenTextAsItalics },
            set: { store.updateMarkRewrittenTextAsItalics($0) }
        )
    }

    private var incrementalRewriteBinding: Binding<Bool> {
        Binding(
            get: { store.project.settings.incrementalRewrite },
            set: { store.updateIncrementalRewrite($0) }
        )
    }

    private var inlineGenerationBinding: Binding<Bool> {
        Binding(
            get: { store.useInlineGeneration },
            set: { store.updateUseInlineGeneration($0) }
        )
    }

    private var preferCompactPromptTemplatesBinding: Binding<Bool> {
        Binding(
            get: { store.project.settings.preferCompactPromptTemplates },
            set: { store.updatePreferCompactPromptTemplates($0) }
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

    private var enableTaskNotificationsBinding: Binding<Bool> {
        Binding(
            get: { store.project.settings.enableTaskNotifications },
            set: { store.updateEnableTaskNotifications($0) }
        )
    }

    private var showTaskProgressNotificationsBinding: Binding<Bool> {
        Binding(
            get: { store.project.settings.showTaskProgressNotifications },
            set: { store.updateShowTaskProgressNotifications($0) }
        )
    }

    private var showTaskCancellationNotificationsBinding: Binding<Bool> {
        Binding(
            get: { store.project.settings.showTaskCancellationNotifications },
            set: { store.updateShowTaskCancellationNotifications($0) }
        )
    }

    private var taskNotificationDurationBinding: Binding<Double> {
        Binding(
            get: { store.project.settings.taskNotificationDurationSeconds },
            set: { store.updateTaskNotificationDurationSeconds($0) }
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
        let discovered = store.availableRemoteModels
        if !discovered.isEmpty {
            return discovered
        }

        let current = store.project.settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty ? [] : [current]
    }

    private func generationModelToggleBinding(for model: String) -> Binding<Bool> {
        Binding(
            get: { store.isGenerationModelSelected(model) },
            set: { isEnabled in
                let isCurrentlySelected = store.isGenerationModelSelected(model)
                guard isEnabled != isCurrentlySelected else { return }
                store.toggleGenerationModelSelection(model)
            }
        )
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

                textGenerationTab
                    .tabItem {
                        Label("Text Generation", systemImage: "sparkles")
                    }
                    .tag(SettingsTab.textGeneration)

                editorTab
                    .tabItem {
                        Label("Editor", systemImage: "textformat")
                    }
                    .tag(SettingsTab.editor)

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
        .sheet(item: $promptRenderPreview) { preview in
            PromptTemplateRenderPreviewSheet(preview: preview)
        }
        .onAppear {
            restoreSettingsTabFromStorage()
        }
        .onChange(of: selectedTab) { _, newValue in
            storedSettingsTabRawValue = newValue.rawValue
        }
        .onChange(of: selectedPromptID) { _, newValue in
            storedSettingsPromptTemplateID = newValue?.uuidString ?? ""
        }
        .confirmationDialog(
            "Update built-in templates to latest defaults?",
            isPresented: $showBuiltInTemplateResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Update Built-ins", role: .destructive) {
                refreshBuiltInTemplates()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This overwrites all built-in templates in this project with the newest defaults. Custom templates are not changed.")
        }
    }

    private func restoreSettingsTabFromStorage() {
        let restored = SettingsTab(rawValue: storedSettingsTabRawValue) ?? .general
        selectedTab = restored
        storedSettingsTabRawValue = restored.rawValue
    }

    private var header: some View {
        HStack {
            Text("Project Settings")
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Editor appearance helpers

    private var resolvedEditorFont: NSFont {
        let app = store.project.editorAppearance
        let normalizedFamily = SceneFontSelectorData.normalizedFamily(app.fontFamily)
        if normalizedFamily == SceneFontSelectorData.systemFamily {
            return app.fontSize > 0
                ? NSFont.systemFont(ofSize: app.fontSize)
                : NSFont.preferredFont(forTextStyle: .body)
        } else {
            let size = app.fontSize > 0 ? app.fontSize : NSFont.systemFontSize
            return NSFont(name: normalizedFamily, size: size) ?? NSFont.preferredFont(forTextStyle: .body)
        }
    }

    private var editorAppearanceFontFamily: String {
        SceneFontSelectorData.normalizedFamily(store.project.editorAppearance.fontFamily)
    }

    private var editorAppearanceFontSize: Double {
        let stored = store.project.editorAppearance.fontSize
        return stored > 0 ? stored : Double(resolvedEditorFont.pointSize)
    }

    private func updateEditorAppearanceFont(family: String, size: Double) {
        var appearance = store.project.editorAppearance
        appearance.fontFamily = SceneFontSelectorData.normalizedFamily(family)
        appearance.fontSize = max(1, size)
        store.updateEditorAppearance(appearance)
    }

    private var textAlignmentBinding: Binding<TextAlignmentOption> {
        Binding(
            get: { store.project.editorAppearance.textAlignment },
            set: {
                var a = store.project.editorAppearance
                a.textAlignment = $0
                store.updateEditorAppearance(a)
            }
        )
    }

    private static let lineHeightFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let marginFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let numberParser: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private func parsedEditorNumber(from draft: String) -> Double? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let parsed = Self.numberParser.number(from: trimmed) {
            return parsed.doubleValue
        }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func formattedLineHeight(_ value: Double) -> String {
        Self.lineHeightFormatter.string(from: NSNumber(value: value))
        ?? String(format: "%.2f", value)
    }

    private func formattedMargin(_ value: Double) -> String {
        let rounded = value.rounded()
        return Self.marginFormatter.string(from: NSNumber(value: rounded))
        ?? String(Int(rounded))
    }

    private func syncEditorSpacingDraftsFromAppearance(force: Bool = false) {
        let appearance = store.project.editorAppearance

        if force || focusedEditorSpacingField != .lineHeight {
            lineHeightDraft = formattedLineHeight(appearance.lineHeightMultiple)
        }
        if force || focusedEditorSpacingField != .horizontalMargin {
            hPaddingDraft = formattedMargin(appearance.horizontalPadding)
        }
        if force || focusedEditorSpacingField != .verticalMargin {
            vPaddingDraft = formattedMargin(appearance.verticalPadding)
        }
    }

    private func commitEditorSpacingField(_ field: EditorSpacingField) {
        var appearance = store.project.editorAppearance

        switch field {
        case .lineHeight:
            guard let parsed = parsedEditorNumber(from: lineHeightDraft) else {
                lineHeightDraft = formattedLineHeight(appearance.lineHeightMultiple)
                return
            }
            let clamped = min(max(parsed, 1.0), 2.5)
            appearance.lineHeightMultiple = clamped
            store.updateEditorAppearance(appearance)
            lineHeightDraft = formattedLineHeight(clamped)

        case .horizontalMargin:
            guard let parsed = parsedEditorNumber(from: hPaddingDraft) else {
                hPaddingDraft = formattedMargin(appearance.horizontalPadding)
                return
            }
            let clamped = min(max(parsed.rounded(), 0), 80)
            appearance.horizontalPadding = clamped
            store.updateEditorAppearance(appearance)
            hPaddingDraft = formattedMargin(clamped)

        case .verticalMargin:
            guard let parsed = parsedEditorNumber(from: vPaddingDraft) else {
                vPaddingDraft = formattedMargin(appearance.verticalPadding)
                return
            }
            let clamped = min(max(parsed.rounded(), 0), 80)
            appearance.verticalPadding = clamped
            store.updateEditorAppearance(appearance)
            vPaddingDraft = formattedMargin(clamped)
        }
    }

    private var textColorEnabled: Bool { store.project.editorAppearance.textColor != nil }
    private var bgColorEnabled: Bool { store.project.editorAppearance.backgroundColor != nil }

    private var textColorBinding: Binding<CodableRGBA> {
        Binding(
            get: {
                if let c = store.project.editorAppearance.textColor {
                    return c
                }
                return CodableRGBA.settingsFrom(nsColor: .textColor) ?? CodableRGBA(red: 0, green: 0, blue: 0, alpha: 1)
            },
            set: { rgba in
                var a = store.project.editorAppearance
                guard !CodableRGBA.settingsAreClose(a.textColor, rgba) else { return }
                a.textColor = rgba
                store.updateEditorAppearance(a)
            }
        )
    }

    private var bgColorBinding: Binding<CodableRGBA> {
        Binding(
            get: {
                if let c = store.project.editorAppearance.backgroundColor {
                    return c
                }
                return CodableRGBA.settingsFrom(nsColor: .textBackgroundColor) ?? CodableRGBA(red: 1, green: 1, blue: 1, alpha: 1)
            },
            set: { rgba in
                var a = store.project.editorAppearance
                guard !CodableRGBA.settingsAreClose(a.backgroundColor, rgba) else { return }
                a.backgroundColor = rgba
                store.updateEditorAppearance(a)
            }
        )
    }

    private var editorAppearancePreviewText: String {
        """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit. Praesent quis mi nec erat suscipit interdum. Integer ac semper velit, id tristique tortor.

        Cras facilisis, ligula at viverra iaculis, erat arcu maximus sapien, vitae aliquam nisi justo nec nisl. Sed pulvinar nunc ac urna facilisis, in consequat massa molestie.
        """
    }

    private var editorTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                GroupBox("Font") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Font")
                                .frame(width: 100, alignment: .leading)

                            FontFamilyDropdown(
                                selectedFamily: editorAppearanceFontFamily,
                                previewPointSize: CGFloat(editorAppearanceFontSize),
                                controlSize: .regular,
                                onSelectFamily: { family in
                                    updateEditorAppearanceFont(
                                        family: family,
                                        size: editorAppearanceFontSize
                                    )
                                },
                                onOpenSystemFontPanel: {
                                    editorFontPanelOpenRequestID = UUID()
                                }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)

                            FontSizeDropdown(
                                selectedSize: editorAppearanceFontSize,
                                controlSize: .regular,
                                onSelectSize: { size in
                                    updateEditorAppearanceFont(
                                        family: editorAppearanceFontFamily,
                                        size: size
                                    )
                                }
                            )
                            .frame(width: 84, alignment: .leading)

                            Button("Reset") {
                                var a = store.project.editorAppearance
                                a.fontFamily = "System"
                                a.fontSize = 0
                                store.updateEditorAppearance(a)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                EditorSettingsFontPanelBridge(
                    font: resolvedEditorFont,
                    openRequestID: editorFontPanelOpenRequestID,
                    onFontChange: { newFont in
                        updateEditorAppearanceFont(
                            family: newFont.familyName ?? newFont.fontName,
                            size: Double(newFont.pointSize)
                        )
                    }
                )
                .frame(width: 0, height: 0)

                GroupBox("Spacing") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Alignment")
                                .frame(width: 100, alignment: .leading)
                            Picker("Alignment", selection: textAlignmentBinding) {
                                Image(systemName: "text.alignleft").tag(TextAlignmentOption.left)
                                Image(systemName: "text.aligncenter").tag(TextAlignmentOption.center)
                                Image(systemName: "text.alignright").tag(TextAlignmentOption.right)
                                Image(systemName: "text.justify").tag(TextAlignmentOption.justified)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }

                        HStack(spacing: 8) {
                            Text("Line height")
                                .frame(width: 100, alignment: .leading)
                            Spacer(minLength: 0)
                            TextField("", text: $lineHeightDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 84, alignment: .leading)
                            .focused($focusedEditorSpacingField, equals: .lineHeight)
                            .onSubmit {
                                commitEditorSpacingField(.lineHeight)
                            }
                            Text("× ")
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Text("H margin")
                                .frame(width: 100, alignment: .leading)
                            Spacer(minLength: 0)
                            TextField("", text: $hPaddingDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 84, alignment: .leading)
                            .focused($focusedEditorSpacingField, equals: .horizontalMargin)
                            .onSubmit {
                                commitEditorSpacingField(.horizontalMargin)
                            }
                            Text("pt")
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Text("V margin")
                                .frame(width: 100, alignment: .leading)
                            Spacer(minLength: 0)
                            TextField("", text: $vPaddingDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 84, alignment: .leading)
                            .focused($focusedEditorSpacingField, equals: .verticalMargin)
                            .onSubmit {
                                commitEditorSpacingField(.verticalMargin)
                            }
                            Text("pt")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GroupBox("Colors") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Text color")
                                .frame(width: 100, alignment: .leading)
                            Spacer(minLength: 0)
                            if textColorEnabled {
                                AppKitColorWell(
                                    selection: Binding(
                                        get: { textColorBinding.wrappedValue },
                                        set: { if let value = $0 { textColorBinding.wrappedValue = value } }
                                    ),
                                    supportsOpacity: false
                                )
                                    .frame(width: 32, height: 18)
                                    .id("settings-text-color-well")
                            } else {
                                Text("System default")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }
                            Toggle("Custom", isOn: Binding(
                                get: { textColorEnabled },
                                set: { enabled in
                                    var a = store.project.editorAppearance
                                    let defaultTextColor = CodableRGBA.settingsFrom(nsColor: .textColor) ?? CodableRGBA(red: 0, green: 0, blue: 0)
                                    let next = enabled ? defaultTextColor : nil
                                    guard !CodableRGBA.settingsAreClose(a.textColor, next) else { return }
                                    a.textColor = next
                                    store.updateEditorAppearance(a)
                                }
                            ))
                            .toggleStyle(.switch)
                        }

                        HStack(spacing: 8) {
                            Text("Background")
                                .frame(width: 100, alignment: .leading)
                            Spacer(minLength: 0)
                            if bgColorEnabled {
                                AppKitColorWell(
                                    selection: Binding(
                                        get: { bgColorBinding.wrappedValue },
                                        set: { if let value = $0 { bgColorBinding.wrappedValue = value } }
                                    ),
                                    supportsOpacity: false
                                )
                                    .frame(width: 32, height: 18)
                                    .id("settings-background-color-well")
                            } else {
                                Text("System default")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }
                            Toggle("Custom", isOn: Binding(
                                get: { bgColorEnabled },
                                set: { enabled in
                                    var a = store.project.editorAppearance
                                    let defaultBackgroundColor = CodableRGBA.settingsFrom(nsColor: .textBackgroundColor) ?? CodableRGBA(red: 1, green: 1, blue: 1)
                                    let next = enabled ? defaultBackgroundColor : nil
                                    guard !CodableRGBA.settingsAreClose(a.backgroundColor, next) else { return }
                                    a.backgroundColor = next
                                    store.updateEditorAppearance(a)
                                }
                            ))
                            .toggleStyle(.switch)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GroupBox("Preview") {
                    EditorAppearancePreview(
                        appearance: store.project.editorAppearance,
                        previewText: editorAppearancePreviewText
                    )
                    .frame(maxWidth: .infinity, minHeight: 130, idealHeight: 150, maxHeight: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .padding(.top, 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button("Apply to All Existing Text") {
                        store.applyEditorAppearanceToExistingText()
                    }
                    .help("Apply current editor font, text color, line height, and alignment to all scene text.")

                    Spacer(minLength: 0)

                    Button("Reset All to Defaults") {
                        store.updateEditorAppearance(.default)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
            .onAppear {
                syncEditorSpacingDraftsFromAppearance(force: true)
            }
            .onChange(of: store.project.editorAppearance) { _, _ in
                syncEditorSpacingDraftsFromAppearance()
            }
            .onChange(of: focusedEditorSpacingField) { oldValue, newValue in
                guard let oldValue, oldValue != newValue else { return }
                commitEditorSpacingField(oldValue)
            }
        }
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Project") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Project title", text: projectTitleBinding)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 8) {
                            Text("Autosave project changes")
                            Spacer(minLength: 0)
                            Toggle("", isOn: autosaveEnabledBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel("Autosave project changes")
                                .help("Automatically save project changes to disk")
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GroupBox("Metadata") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Author")
                                .frame(width: 96, alignment: .leading)
                            TextField("Author name", text: projectAuthorBinding)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 8) {
                            Text("Language")
                                .frame(width: 96, alignment: .leading)
                            TextField("Language code (for EPUB, e.g. en)", text: projectLanguageBinding)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 8) {
                            Text("Publisher")
                                .frame(width: 96, alignment: .leading)
                            TextField("Publisher", text: projectPublisherBinding)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 8) {
                            Text("Rights")
                                .frame(width: 96, alignment: .leading)
                            TextField("Copyright / rights statement", text: projectRightsBinding)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Description")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextEditor(text: projectDescriptionBinding)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .frame(minHeight: 110, idealHeight: 130)
                        }

                        Text("Saved with the project and included in JSON/EPUB export-import when available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GroupBox("Storage") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project file location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(store.currentProjectPathDisplay)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GroupBox("Data Exchange") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Transfer prompt templates, compendium entries, and full projects as JSON, plus project text as EPUB.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Text("Prompts")
                                .frame(width: 96, alignment: .leading)
                            Spacer(minLength: 0)
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
                            Spacer(minLength: 0)
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
                            Spacer(minLength: 0)
                            Button("Export...") {
                                exportProjectExchange()
                            }
                            Button("Import...") {
                                importProjectExchange()
                            }
                        }

                        HStack(spacing: 8) {
                            Text("Project EPUB")
                                .frame(width: 96, alignment: .leading)
                            Spacer(minLength: 0)
                            Button("Export...") {
                                exportProjectEPUB()
                            }
                            Button("Import...") {
                                importProjectEPUB()
                            }
                        }

                        if !dataExchangeStatus.isEmpty {
                            Text(dataExchangeStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private var textGenerationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Model Selection") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 8) {
                            Text("Generation models")
                            Spacer(minLength: 0)

                            Menu {
                                if store.generationModelOptions.isEmpty {
                                    Button("No models available") {}
                                        .disabled(true)
                                } else {
                                    ForEach(store.generationModelOptions, id: \.self) { model in
                                        Toggle(model, isOn: generationModelToggleBinding(for: model))
                                    }
                                }

                                let currentModel = store.project.settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !currentModel.isEmpty {
                                    Divider()
                                    Button("Use Only \(currentModel)") {
                                        store.selectOnlyGenerationModel(currentModel)
                                    }
                                }
                            } label: {
                                Label(store.selectedGenerationModelsLabel, systemImage: "square.stack.3d.up")
                                    .lineLimit(1)
                                    .frame(maxWidth: 260, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }

                        Text("Multi-model generation runs one candidate per selected model and opens review so you can accept the best result.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Text("Inline generation")
                            Spacer(minLength: 0)
                            Toggle("", isOn: inlineGenerationBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel("Inline generation")
                                .help("Generate directly into scene text using the first selected model instead of opening multi-model review.")
                        }

                        Text("When inline generation is on, generation appends/streams directly into the scene and skips the multi-model candidate review.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GroupBox("Rewrite") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Mark rewritten text as italics")
                            Spacer(minLength: 0)
                            Toggle("", isOn: markRewrittenTextAsItalicsBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel("Mark rewritten text as italics")
                                .help("Italicize AI-rewritten text to distinguish it from original")
                        }

                        HStack(spacing: 8) {
                            Text("Incremental rewrite")
                            Spacer(minLength: 0)
                            Toggle("", isOn: incrementalRewriteBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel("Incremental rewrite")
                                .help("Update rewritten selection while streaming chunks arrive")
                        }

                        Text("These options affect only Rewrite actions when text selection is active in the editor.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GroupBox("Task Notifications") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Show notifications")
                            Spacer(minLength: 0)
                            Toggle("", isOn: enableTaskNotificationsBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel("Show task notifications")
                        }

                        HStack(spacing: 8) {
                            Text("Show progress")
                            Spacer(minLength: 0)
                            Toggle("", isOn: showTaskProgressNotificationsBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel("Show task progress notifications")
                        }
                        .disabled(!store.project.settings.enableTaskNotifications)

                        HStack(spacing: 8) {
                            Text("Show cancellation")
                            Spacer(minLength: 0)
                            Toggle("", isOn: showTaskCancellationNotificationsBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel("Show task cancellation notifications")
                        }
                        .disabled(!store.project.settings.enableTaskNotifications)

                        Stepper(value: taskNotificationDurationBinding, in: 1 ... 30, step: 1) {
                            HStack {
                                Text("Auto-hide delay")
                                Spacer(minLength: 0)
                                Text(taskNotificationDurationLabel(store.project.settings.taskNotificationDurationSeconds))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .disabled(!store.project.settings.enableTaskNotifications)

                        Text("Controls corner notifications for generation, summary, and memory background jobs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

                    HStack(spacing: 8) {
                        Text("Enable Streaming Responses")
                        Spacer(minLength: 0)
                        Toggle("", isOn: enableStreamingBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel("Enable Streaming Responses")
                            .help("Stream AI responses token by token as they are generated")
                    }

                    HStack(spacing: 8) {
                        Text("Prefer Compact Prompt Templates")
                        Spacer(minLength: 0)
                        Toggle("", isOn: preferCompactPromptTemplatesBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel("Prefer Compact Prompt Templates")
                            .help("Use alternate compact built-in templates optimized for instruct-style models. Only affects built-in defaults you have not modified; custom templates are unchanged.")
                    }
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
    }

    private var promptTemplatesTab: some View {
        HSplitView {
            VStack(spacing: 0) {
                if store.project.prompts.isEmpty {
                    ContentUnavailableView("No Prompt Templates", systemImage: "text.badge.star", description: Text("Add a template to start configuring prose generation."))
                } else {
                    List(selection: promptListSelectionBinding) {
                        ForEach(promptCategoriesInEditor, id: \.self) { category in
                            Section {
                                ForEach(store.prompts(in: category)) { prompt in
                                    Text(promptTitle(prompt))
                                        .lineLimit(1)
                                        .font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 1)
                                        .padding(.leading, 12)
                                    .tag(Optional(prompt.id))
                                }
                            } header: {
                                promptSectionHeader(for: category)
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }

                Divider()

                HStack(spacing: 4) {
                    Menu {
                        ForEach(PromptCategory.allCases, id: \.self) { category in
                            Button("Add \(promptCategoryName(for: category)) Template") {
                                let newPromptID = store.addPrompt(category: category)
                                selectedPromptID = newPromptID
                                syncRuntimePromptSelection(from: newPromptID)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuIndicator(.hidden)
                    .help("Add Template")

                    Button {
                        confirmDeletePrompt = true
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(!canDeleteSelectedPrompt)
                    .help("Delete Template")

                    Spacer(minLength: 0)

                    Menu {
                        Button("Export Prompts…") {
                            exportPrompts()
                        }
                        Button("Import Prompts…") {
                            importPrompts()
                        }
                        Divider()
                        Button("Update Built-in Templates…") {
                            showBuiltInTemplateResetConfirmation = true
                        }
                        Divider()
                        Button("Clear All Prompts…", role: .destructive) {
                            confirmClearPrompts = true
                        }
                        .disabled(store.project.prompts.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuIndicator(.hidden)
                    .help("Prompt Actions")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 14, weight: .medium))
                .padding(12)

                if !promptTemplateStatus.isEmpty {
                    Text(promptTemplateStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }
            .frame(minWidth: 250, idealWidth: 280, maxWidth: 320)

            promptEditorDetail
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selectedPromptID == nil {
                let storedPromptID = UUID(uuidString: storedSettingsPromptTemplateID)
                let hasStoredPrompt = storedPromptID.flatMap { id in
                    store.project.prompts.first(where: { $0.id == id })
                } != nil

                selectedPromptID = (hasStoredPrompt ? storedPromptID : nil)
                    ?? store.project.selectedProsePromptID
                    ?? store.project.selectedWorkshopPromptID
                    ?? store.project.prompts.first?.id
            }
            syncRuntimePromptSelection(from: selectedPromptID)
        }
        .onChange(of: selectedPromptID) { _, newValue in
            syncRuntimePromptSelection(from: newValue)
        }
        .alert("Delete Template", isPresented: $confirmDeletePrompt) {
            Button("Delete", role: .destructive) {
                deleteSelectedPrompt()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(activePromptForEditor?.title ?? "")\"?")
        }
        .alert("Clear All Prompts", isPresented: $confirmClearPrompts) {
            Button("Clear All", role: .destructive) {
                store.clearPrompts()
                selectedPromptID = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete all \(store.project.prompts.count) prompt templates? This cannot be undone.")
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

                    HStack(spacing: 10) {
                        Button {
                            testRenderSelectedPrompt()
                        } label: {
                            Label("Test Render", systemImage: "play.rectangle")
                        }
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

    @ViewBuilder
    private func promptSectionHeader(for category: PromptCategory) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(promptSectionTitle(for: category))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
            Text(promptUsageLabel(for: category))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
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
        promptBinding(promptID, field: .title)
    }

    private func promptUserTemplateBinding(_ promptID: UUID) -> Binding<String> {
        promptBinding(promptID, field: .userTemplate)
    }

    private func promptSystemTemplateBinding(_ promptID: UUID) -> Binding<String> {
        promptBinding(promptID, field: .systemTemplate)
    }

    @ViewBuilder
    private func promptVariableHelp(currentCategory: PromptCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Template Variable Help")
                .font(.headline)

            Text("Use `{{variable}}` or `{{function(...)}}`. Legacy `{variable}` placeholders are still supported.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(promptCategoryName(for: currentCategory)) mode")
                    .font(.subheadline)

                ForEach(variableHelpItems(for: currentCategory)) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.token)
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 240, alignment: .leading)
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
                .init(token: "{{beat}}", meaning: "Text from the \"Generate from beat\" input."),
                .init(token: "{{scene_summary}}", meaning: "Current scene summary text (user-written or generated)."),
                .init(token: "{{scene}}", meaning: "Current scene excerpt for continuity."),
                .init(token: "{{scene_tail(chars=2400)}}", meaning: "Tail of full scene text; `chars` is configurable (recommended range: ~1200-3000)."),
                .init(token: "{{state}}", meaning: "Structured scene-local narrative state block with only filled values."),
                .init(token: "{{state_pov}} / {{state_tense}} / {{state_location}}", meaning: "Scene-local narrative state fields."),
                .init(token: "{{state_time}} / {{state_goal}} / {{state_emotion}}", meaning: "Scene-local narrative state fields."),
                .init(token: "{{context}}", meaning: "Selected/mentioned scene context (compendium + summaries)."),
                .init(token: "{{context_rolling}} / {{rolling_summary}}", meaning: "Rolling memory block (scene/workshop memory when available)."),
                .init(token: "{{context_compendium}}", meaning: "Only selected/mentioned compendium entries."),
                .init(token: "{{context_scene_summaries}}", meaning: "Only selected/mentioned scene summaries."),
                .init(token: "{{context_chapter_summaries}}", meaning: "Only selected chapter summaries."),
                .init(token: "{{scene_title}} / {{chapter_title}}", meaning: "Current scene/chapter names."),
                .init(token: "{{project_title}}", meaning: "Current project title."),
            ]
        case .rewrite:
            return [
                .init(token: "{{selection}}", meaning: "Currently selected text in the editor (text to rewrite/expand/shorten)."),
                .init(token: "{{beat}}", meaning: "Text from the standard generation input field (separate rewrite guidance)."),
                .init(token: "{{selection_context}}", meaning: "Local scene context around the selected text (before/selection/after)."),
                .init(token: "{{scene}} / {{scene_tail(chars=2200)}}", meaning: "Current scene excerpt or configurable tail from full scene (optional)."),
                .init(token: "{{state}} / {{state_pov}} / {{state_tense}}", meaning: "Scene-local narrative state block and key fields."),
                .init(token: "{{state_location}} / {{state_time}} / {{state_goal}} / {{state_emotion}}", meaning: "Additional scene-local narrative state fields."),
                .init(token: "{{context(max_chars=2200)}}", meaning: "Selected scene context with optional truncation."),
                .init(token: "{{context_rolling(max_chars=2200)}}", meaning: "Rolling memory block with optional truncation."),
                .init(token: "{{context_compendium}}", meaning: "Only selected compendium entries."),
                .init(token: "{{context_scene_summaries}}", meaning: "Only selected scene summaries."),
                .init(token: "{{context_chapter_summaries}}", meaning: "Only selected chapter summaries."),
                .init(token: "{{scene_title}} / {{chapter_title}}", meaning: "Current scene/chapter names."),
            ]
        case .summary:
            return [
                .init(token: "{{source}}", meaning: "Summary source input: scene excerpt (scene scope) or scene summaries list (chapter scope)."),
                .init(token: "{{summary_scope}}", meaning: "Current summary scope (`scene` or `chapter`)."),
                .init(token: "{{context}}", meaning: "Scope metadata and supporting context."),
                .init(token: "{{context_rolling}}", meaning: "Rolling memory block (scene/workshop memory when available)."),
                .init(token: "{{scene}}", meaning: "Same source text currently assigned to summary input."),
                .init(token: "{{state}} / {{state_pov}} / {{state_tense}}", meaning: "Scene-local narrative state block and key fields."),
                .init(token: "{{state_location}} / {{state_time}} / {{state_goal}} / {{state_emotion}}", meaning: "Additional scene-local narrative state fields."),
                .init(token: "{{context_scene_summaries}}", meaning: "Selected scene summaries (scene scope support)."),
                .init(token: "{{context_chapter_summaries}}", meaning: "Selected chapter summaries (scene scope support)."),
                .init(token: "{{scene_title}} / {{chapter_title}}", meaning: "Current scene/chapter labels."),
            ]
        case .workshop:
            return [
                .init(token: "{{chat_name}}", meaning: "Current workshop chat name."),
                .init(token: "{{conversation}}", meaning: "Recent transcript string (last 14 messages)."),
                .init(token: "{{chat_history(turns=8)}}", meaning: "Conversation built from actual turns, configurable by `turns`."),
                .init(token: "{{last_user_message}} / {{last_assistant_message}}", meaning: "Most recent user or assistant turn."),
                .init(token: "{{scene}} / {{scene_tail(chars=1800)}}", meaning: "Scene excerpt when scene context is enabled."),
                .init(token: "{{state}} / {{state_pov}} / {{state_tense}}", meaning: "Scene-local narrative state block and key fields (when scene context is enabled)."),
                .init(token: "{{state_location}} / {{state_time}} / {{state_goal}} / {{state_emotion}}", meaning: "Additional scene-local narrative state fields."),
                .init(token: "{{context}}", meaning: "Selected/mentioned compendium and summary context."),
                .init(token: "{{context_rolling(max_chars=2200)}}", meaning: "Rolling memory block with optional truncation."),
                .init(token: "{{rolling_workshop_summary}} / {{rolling_chapter_summary}} / {{rolling_scene_summary}}", meaning: "Raw rolling memory variables for workshop/session, chapter, and scene."),
                .init(token: "{{context_compendium(max_chars=4000)}}", meaning: "Compendium-only context with optional truncation."),
                .init(token: "{{context_scene_summaries(max_chars=4000)}}", meaning: "Scene-summary context with optional truncation."),
                .init(token: "{{context_chapter_summaries(max_chars=4000)}}", meaning: "Chapter-summary context with optional truncation."),
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

    private func taskNotificationDurationLabel(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        return rounded == 1 ? "1 sec" : "\(rounded) sec"
    }

    private func deleteSelectedPrompt() {
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

    private func exportProjectEPUB() {
        guard let fileURL = ProjectDialogs.chooseProjectEPUBExportURL(defaultProjectName: store.currentProjectName) else {
            return
        }

        do {
            try store.exportProjectAsEPUB(to: fileURL)
            dataExchangeStatus = "Exported project EPUB."
        } catch {
            store.lastError = "Project EPUB export failed: \(error.localizedDescription)"
        }
    }

    private func importProjectEPUB() {
        guard let fileURL = ProjectDialogs.chooseProjectEPUBImportURL() else {
            return
        }
        guard ProjectDialogs.confirmProjectEPUBImportReplacement() else {
            return
        }

        do {
            try store.importProjectFromEPUB(from: fileURL)
            selectedPromptID = store.project.selectedProsePromptID
                ?? store.project.selectedWorkshopPromptID
                ?? store.project.prompts.first?.id
            dataExchangeStatus = "Imported project EPUB."
        } catch {
            store.lastError = "Project EPUB import failed: \(error.localizedDescription)"
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

    private func testRenderSelectedPrompt() {
        guard let selectedPromptID else { return }
        do {
            promptRenderPreview = try store.makePromptTemplateRenderPreview(promptID: selectedPromptID)
        } catch {
            store.lastError = "Prompt preview failed: \(error.localizedDescription)"
        }
    }

    private func refreshBuiltInTemplates() {
        let result = store.refreshBuiltInPromptTemplatesToLatest()
        let styleLabel = store.project.settings.preferCompactPromptTemplates ? "compact" : "standard"
        if result.updatedCount == 0, result.addedCount == 0 {
            promptTemplateStatus = "Built-in templates are already up to date for \(styleLabel) style."
            return
        }

        promptTemplateStatus = "Built-in templates updated (\(styleLabel) style): \(result.updatedCount) replaced, \(result.addedCount) added."
    }
}

private struct EditorAppearancePreview: NSViewRepresentable {
    let appearance: EditorAppearanceSettings
    let previewText: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.isEditable = false
        textView.isSelectable = false
        textView.isRichText = true
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(
            width: appearance.horizontalPadding,
            height: appearance.verticalPadding
        )

        scrollView.documentView = textView
        applyAppearance(to: textView, in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        applyAppearance(to: textView, in: scrollView)
    }

    private func applyAppearance(to textView: NSTextView, in scrollView: NSScrollView) {
        let baseFont = resolvedBaseFont(from: appearance)
        let textColor = resolvedTextColor(from: appearance)
        let backgroundColor = resolvedBackgroundColor(from: appearance)
        let paragraphStyle = resolvedParagraphStyle(from: appearance)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        textView.textStorage?.setAttributedString(
            NSAttributedString(string: previewText, attributes: attributes)
        )
        textView.textContainerInset = NSSize(
            width: appearance.horizontalPadding,
            height: appearance.verticalPadding
        )
        scrollView.backgroundColor = backgroundColor
    }

    private func resolvedBaseFont(from settings: EditorAppearanceSettings) -> NSFont {
        let normalizedFamily = SceneFontSelectorData.normalizedFamily(settings.fontFamily)
        if normalizedFamily == SceneFontSelectorData.systemFamily {
            if settings.fontSize > 0 {
                return NSFont.systemFont(ofSize: settings.fontSize)
            }
            return NSFont.preferredFont(forTextStyle: .body)
        }

        let size = settings.fontSize > 0 ? settings.fontSize : NSFont.systemFontSize
        return NSFont(name: normalizedFamily, size: size)
            ?? NSFont.preferredFont(forTextStyle: .body)
    }

    private func resolvedTextColor(from settings: EditorAppearanceSettings) -> NSColor {
        settings.textColor.map {
            NSColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
        } ?? .textColor
    }

    private func resolvedBackgroundColor(from settings: EditorAppearanceSettings) -> NSColor {
        settings.backgroundColor.map {
            NSColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
        } ?? .textBackgroundColor
    }

    private func resolvedParagraphStyle(from settings: EditorAppearanceSettings) -> NSMutableParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = max(1.0, settings.lineHeightMultiple)
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = {
            switch settings.textAlignment {
            case .left:
                return .left
            case .center:
                return .center
            case .right:
                return .right
            case .justified:
                return .justified
            }
        }()
        return paragraphStyle
    }
}

private struct PromptTemplateRenderPreviewSheet: View {
    let preview: AppStore.PromptTemplateRenderPreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Template Test Render")
                        .font(.title3.weight(.semibold))
                    Text(preview.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("Mode") {
                        Text(modeLabel(preview.category))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !preview.notes.isEmpty {
                        GroupBox("Render Notes") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(preview.notes.enumerated()), id: \.offset) { _, note in
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !preview.warnings.isEmpty {
                        GroupBox("Template Warnings") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, warning in
                                    Text(warning)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GroupBox("Resolved System Prompt") {
                        Text(preview.resolvedSystemPrompt)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }

                    GroupBox("Rendered User Prompt") {
                        Text(preview.renderedUserPrompt)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 860, minHeight: 660)
    }

    private func modeLabel(_ category: PromptCategory) -> String {
        switch category {
        case .prose:
            return "Writing"
        case .rewrite:
            return "Rewrite"
        case .summary:
            return "Summary"
        case .workshop:
            return "Workshop Chat"
        }
    }
}

// MARK: - Font panel integration

private struct EditorSettingsFontPanelBridge: NSViewRepresentable {
    let font: NSFont
    let openRequestID: UUID?
    let onFontChange: (NSFont) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.currentFont = font
        context.coordinator.onFontChange = onFontChange

        guard let openRequestID else { return }
        guard context.coordinator.lastOpenRequestID != openRequestID else { return }

        context.coordinator.lastOpenRequestID = openRequestID
        context.coordinator.openFontPanel()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(font: font, onFontChange: onFontChange)
    }

    @MainActor
    final class Coordinator: NSObject {
        var currentFont: NSFont
        var onFontChange: (NSFont) -> Void
        var lastOpenRequestID: UUID?

        init(font: NSFont, onFontChange: @escaping (NSFont) -> Void) {
            self.currentFont = font
            self.onFontChange = onFontChange
        }

        func openFontPanel() {
            let fontManager = NSFontManager.shared
            fontManager.target = self
            fontManager.action = #selector(changeFont(_:))
            let panel = NSFontPanel.shared
            panel.setPanelFont(currentFont, isMultiple: false)
            panel.orderFront(nil)
        }

        @objc func changeFont(_ sender: NSFontManager?) {
            guard let sender else { return }
            let newFont = sender.convert(currentFont)
            currentFont = newFont
            onFontChange(newFont)
        }
    }
}
