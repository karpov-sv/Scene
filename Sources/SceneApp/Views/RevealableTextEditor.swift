import SwiftUI
import AppKit

/// A plain-text editor backed by a real NSTextView, with reliable
/// programmatic `showFindIndicator(for:)` support.
///
/// Drop-in replacement for `TextEditor(text:)` in panels where the
/// native macOS "yellow bounce" find indicator is needed.
struct RevealableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var revealRequest: RevealRequest?

    struct RevealRequest: Equatable {
        var id: UUID
        var location: Int
        var length: Int
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .textColor
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 4)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Sync text from binding to NSTextView (avoid loop via isUpdating flag)
        if textView.string != text, !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            let sel = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = sel
            context.coordinator.isUpdating = false
        }

        // Handle reveal / find-indicator request
        if let request = revealRequest,
           request.id != context.coordinator.lastRevealID {
            context.coordinator.lastRevealID = request.id
            let count = textView.string.count
            let loc = min(request.location, count)
            let len = min(request.length, max(0, count - loc))
            let range = NSRange(location: loc, length: len)
            // Brief delay so layout settles after a possible text swap
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                textView.scrollRangeToVisible(range)
                textView.showFindIndicator(for: range)
            }
        }
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RevealableTextEditor
        weak var textView: NSTextView?
        var lastRevealID: UUID?
        var isUpdating = false

        init(_ parent: RevealableTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.text = textView.string
            isUpdating = false
        }
    }
}
