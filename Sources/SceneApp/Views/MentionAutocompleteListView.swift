import SwiftUI
import AppKit

struct MentionAutocompleteListView: View {
    let suggestions: [MentionSuggestion]
    let selectedIndex: Int
    var availableHeight: CGFloat? = nil
    let onHighlight: (Int) -> Void
    let onSelect: (MentionSuggestion) -> Void

    @State private var lastMouseScreenLocation: CGPoint = NSEvent.mouseLocation

    private let fallbackMaxMenuHeight: CGFloat = 260
    private let rowHeight: CGFloat = 28
    private let dividerHeight: CGFloat = 1
    private let minMenuHeight: CGFloat = 30

    private var effectiveMaxHeight: CGFloat {
        if let availableHeight {
            return max(minMenuHeight, availableHeight)
        }
        return fallbackMaxMenuHeight
    }

    private var menuHeight: CGFloat {
        guard !suggestions.isEmpty else { return minMenuHeight }
        let separators = CGFloat(max(0, suggestions.count - 1)) * dividerHeight
        let contentHeight = CGFloat(suggestions.count) * rowHeight + separators
        return min(effectiveMaxHeight, contentHeight)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        Button {
                            onSelect(suggestion)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(prefix(for: suggestion.trigger))\(suggestion.label)")
                                    .font(.body)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if let subtitle = suggestion.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            index == selectedIndex
                                ? Color.accentColor.opacity(0.15)
                                : Color(nsColor: .controlBackgroundColor)
                        )
                        .onContinuousHover { phase in
                            switch phase {
                            case .active:
                                let current = NSEvent.mouseLocation
                                let dx = current.x - lastMouseScreenLocation.x
                                let dy = current.y - lastMouseScreenLocation.y
                                let distance = (dx * dx + dy * dy).squareRoot()
                                lastMouseScreenLocation = current
                                if distance > 3.0 {
                                    onHighlight(index)
                                }
                            case .ended:
                                break
                            }
                        }
                        .id(suggestion.id)

                        if index < suggestions.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .onAppear {
                scrollToSelection(using: proxy, anchor: .center, animated: false)
            }
            .onChange(of: selectedIndex) { oldValue, newValue in
                let anchor: UnitPoint = newValue >= oldValue ? .bottom : .top
                scrollToSelection(using: proxy, anchor: anchor, animated: true)
            }
        }
        .frame(height: menuHeight)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
    }

    private func prefix(for trigger: MentionTrigger) -> String {
        switch trigger {
        case .tag:
            return "@"
        case .scene:
            return "#"
        }
    }

    private func scrollToSelection(
        using proxy: ScrollViewProxy,
        anchor: UnitPoint,
        animated: Bool
    ) {
        guard suggestions.indices.contains(selectedIndex) else { return }
        let targetID = suggestions[selectedIndex].id
        if animated {
            withAnimation(.easeOut(duration: 0.1)) {
                proxy.scrollTo(targetID, anchor: anchor)
            }
        } else {
            proxy.scrollTo(targetID, anchor: anchor)
        }
    }
}
