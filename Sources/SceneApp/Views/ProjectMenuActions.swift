import SwiftUI

struct ProjectMenuActions {
    let importProjectJSON: () -> Void
    let exportProjectJSON: () -> Void
    let exportProjectPlainText: () -> Void
    let exportProjectHTML: () -> Void
    let canExportProject: Bool
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
