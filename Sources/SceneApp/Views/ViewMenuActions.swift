import SwiftUI

struct ViewMenuActions {
    let toggleBinder: () -> Void
    let switchToWriting: () -> Void
    let switchToWorkshop: () -> Void
    let toggleCompendium: () -> Void
    let toggleSummary: () -> Void
    let toggleNotes: () -> Void
    let toggleConversations: () -> Void
    let canUseViewActions: Bool
}

private struct ViewMenuActionsKey: FocusedValueKey {
    typealias Value = ViewMenuActions
}

extension FocusedValues {
    var viewMenuActions: ViewMenuActions? {
        get { self[ViewMenuActionsKey.self] }
        set { self[ViewMenuActionsKey.self] = newValue }
    }
}
