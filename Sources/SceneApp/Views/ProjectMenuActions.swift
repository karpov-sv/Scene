import SwiftUI

struct ProjectMenuActions {
    let importProjectJSON: () -> Void
    let importProjectEPUB: () -> Void
    let exportProjectJSON: () -> Void
    let exportProjectPlainText: () -> Void
    let exportProjectHTML: () -> Void
    let exportProjectEPUB: () -> Void
    let openProjectSettings: () -> Void
    let canExportProject: Bool
    let canOpenProjectSettings: Bool
}

private struct ProjectMenuActionsKey: FocusedValueKey {
    typealias Value = ProjectMenuActions
}

extension FocusedValues {
    var projectMenuActions: ProjectMenuActions? {
        get { self[ProjectMenuActionsKey.self] }
        set { self[ProjectMenuActionsKey.self] = newValue }
    }
}
