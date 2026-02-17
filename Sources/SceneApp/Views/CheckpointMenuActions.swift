import SwiftUI

struct CheckpointMenuActions {
    let createCheckpoint: () -> Void
    let showRestoreDialog: () -> Void
    let canCreateCheckpoint: Bool
    let canRestoreCheckpoint: Bool
}

private struct CheckpointMenuActionsKey: FocusedValueKey {
    typealias Value = CheckpointMenuActions
}

extension FocusedValues {
    var checkpointMenuActions: CheckpointMenuActions? {
        get { self[CheckpointMenuActionsKey.self] }
        set { self[CheckpointMenuActionsKey.self] = newValue }
    }
}
