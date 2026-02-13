import SwiftUI

struct SceneFileCommands: Commands {
    @FocusedValue(\.projectMenuActions) private var actions

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Menu("Import") {
                Button("Project JSON...") {
                    actions?.importProjectJSON()
                }
                .disabled(actions == nil)
            }

            Menu("Export") {
                Button("Project JSON...") {
                    actions?.exportProjectJSON()
                }
                .disabled(actions?.canExportProject != true)

                Button("Project Plain Text...") {
                    actions?.exportProjectPlainText()
                }
                .disabled(actions?.canExportProject != true)

                Button("Project HTML...") {
                    actions?.exportProjectHTML()
                }
                .disabled(actions?.canExportProject != true)
            }
        }
    }
}
