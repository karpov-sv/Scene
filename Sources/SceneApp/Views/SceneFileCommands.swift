import SwiftUI

struct SceneFileCommands: Commands {
    @FocusedValue(\.projectMenuActions) private var actions
    @FocusedValue(\.searchMenuActions) private var searchActions

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Menu("Import") {
                Button("JSON...") {
                    actions?.importProjectJSON()
                }
                .disabled(actions == nil)

                Button("EPUB...") {
                    actions?.importProjectEPUB()
                }
                .disabled(actions == nil)
            }

            Menu("Export") {
                Button("JSON...") {
                    actions?.exportProjectJSON()
                }
                .disabled(actions?.canExportProject != true)

                Button("Plain Text...") {
                    actions?.exportProjectPlainText()
                }
                .disabled(actions?.canExportProject != true)

                Button("HTML...") {
                    actions?.exportProjectHTML()
                }
                .disabled(actions?.canExportProject != true)

                Button("EPUB...") {
                    actions?.exportProjectEPUB()
                }
                .disabled(actions?.canExportProject != true)
            }

            Divider()

            Button("Project Settings...") {
                actions?.openProjectSettings()
            }
            .disabled(actions?.canOpenProjectSettings != true)
        }

        CommandGroup(after: .textEditing) {
            Button("Find in Scene...") {
                searchActions?.findInScene()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(searchActions?.canFindInScene != true)

            Button("Find in Project...") {
                searchActions?.findInProject()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(searchActions?.canFindInProject != true)

            Divider()

            Button("Find Next") {
                searchActions?.findNext()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(searchActions?.canFindNext != true)

            Button("Find Previous") {
                searchActions?.findPrevious()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(searchActions?.canFindPrevious != true)

            Divider()

            Button("Focus Story Beat") {
                searchActions?.focusBeatInput()
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(searchActions?.canFocusBeatInput != true)
        }
    }
}
