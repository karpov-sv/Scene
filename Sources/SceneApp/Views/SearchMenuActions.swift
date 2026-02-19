import SwiftUI

struct SearchMenuActions {
    let findInScene: () -> Void
    let findInProject: () -> Void
    let findAndReplace: () -> Void
    let findNext: () -> Void
    let findPrevious: () -> Void
    let focusBeatInput: () -> Void
    let canFindInScene: Bool
    let canFindInProject: Bool
    let canFindAndReplace: Bool
    let canFindNext: Bool
    let canFindPrevious: Bool
    let canFocusBeatInput: Bool
}

private struct SearchMenuActionsKey: FocusedValueKey {
    typealias Value = SearchMenuActions
}

extension FocusedValues {
    var searchMenuActions: SearchMenuActions? {
        get { self[SearchMenuActionsKey.self] }
        set { self[SearchMenuActionsKey.self] = newValue }
    }
}
