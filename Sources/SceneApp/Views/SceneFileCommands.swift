import SwiftUI

struct SceneFileCommands: Commands {
    @FocusedValue(\.projectMenuActions) private var actions
    @FocusedValue(\.searchMenuActions) private var searchActions
    @FocusedValue(\.viewMenuActions) private var viewActions
    @FocusedValue(\.checkpointMenuActions) private var checkpointActions

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

        CommandGroup(after: .sidebar) {
            Divider()

            Button("Toggle Binder") {
                viewActions?.toggleBinder()
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(viewActions?.canUseViewActions != true)

            Button("Switch to Writing") {
                viewActions?.switchToWriting()
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(viewActions?.canUseViewActions != true)

            Button("Switch to Workshop") {
                viewActions?.switchToWorkshop()
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(viewActions?.canUseViewActions != true)

            Button("Switch to Text Generation") {
                searchActions?.focusBeatInput()
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(searchActions?.canFocusBeatInput != true)

            Divider()

            Button("Toggle Compendium") {
                viewActions?.toggleCompendium()
            }
            .keyboardShortcut("4", modifiers: .command)
            .disabled(viewActions?.canUseViewActions != true)

            Button("Toggle Summary") {
                viewActions?.toggleSummary()
            }
            .keyboardShortcut("5", modifiers: .command)
            .disabled(viewActions?.canUseViewActions != true)

            Button("Toggle Notes") {
                viewActions?.toggleNotes()
            }
            .keyboardShortcut("6", modifiers: .command)
            .disabled(viewActions?.canUseViewActions != true)

            Button("Toggle Conversations") {
                viewActions?.toggleConversations()
            }
            .keyboardShortcut("7", modifiers: .command)
            .disabled(viewActions?.canUseViewActions != true)

            Button("Toggle Text Generation") {
                viewActions?.toggleTextGeneration()
            }
            .keyboardShortcut("8", modifiers: .command)
            .disabled(viewActions?.canUseViewActions != true)
        }

        CommandMenu("Checkpoints") {
            Button("Create") {
                checkpointActions?.createCheckpoint()
            }
            .disabled(checkpointActions?.canCreateCheckpoint != true)

            Button("Restore...") {
                checkpointActions?.showRestoreDialog()
            }
            .disabled(checkpointActions?.canRestoreCheckpoint != true)

            Button("Scene History") {
                checkpointActions?.showSceneHistory()
            }
            .disabled(checkpointActions?.canShowSceneHistory != true)
        }
    }
}
