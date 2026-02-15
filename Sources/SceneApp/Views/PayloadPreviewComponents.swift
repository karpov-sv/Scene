import SwiftUI
import AppKit

struct PayloadPreviewSheetContent: View {
    let preview: AppStore.WorkshopPayloadPreview
    @Environment(\.dismiss) private var dismiss
    @State private var showsHumanReadableBody: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Payload Preview")
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 0)
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("Request") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Provider: \(preview.providerLabel)")
                            if let method = preview.method {
                                Text("Method: \(method)")
                            }
                            if let endpointURL = preview.endpointURL {
                                Text("Endpoint: \(endpointURL)")
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !preview.headers.isEmpty {
                        GroupBox("Headers") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(preview.headers.enumerated()), id: \.offset) { _, header in
                                    Text("\(header.name): \(header.value)")
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GroupBox("Body") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text("Human-readable body")
                                Spacer(minLength: 0)
                                Toggle("", isOn: $showsHumanReadableBody)
                                    .toggleStyle(.switch)
                                    .accessibilityLabel("Human-readable body")
                                    .help("Preview message content in a human-readable way")
                            }

                            PayloadPreviewSyntaxTextView(
                                text: showsHumanReadableBody ? preview.bodyHumanReadable : preview.bodyJSON,
                                highlightsJSON: !showsHumanReadableBody
                            )
                            .frame(minHeight: 360)
                        }
                    }

                    if !preview.notes.isEmpty {
                        GroupBox("Notes") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(preview.notes.enumerated()), id: \.offset) { _, note in
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 840, minHeight: 640)
    }
}

struct PayloadPreviewSyntaxTextView: NSViewRepresentable {
    let text: String
    let highlightsJSON: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textStorage?.setAttributedString(Self.styledText(text, highlightsJSON: highlightsJSON))

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(Self.styledText(text, highlightsJSON: highlightsJSON))
    }

    private static func styledText(_ text: String, highlightsJSON: Bool) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let attributed = NSMutableAttributedString(string: text)
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        attributed.addAttributes(
            [
                .foregroundColor: NSColor.labelColor,
                .font: font
            ],
            range: fullRange
        )

        guard highlightsJSON else {
            // Human-readable mode: emphasize actual string payload values.
            applyRegex("(?s)<<<\\n.*?\\n>>>", color: NSColor.systemRed, to: attributed)
            applyRegex("\\\"(?:\\\\.|[^\\\"\\\\])*\\\"", color: NSColor.systemRed, to: attributed)
            return attributed
        }

        applyRegex("\\\"(?:\\\\.|[^\\\"\\\\])*\\\"", color: NSColor.systemRed, to: attributed)
        applyRegex("\\\"(?:\\\\.|[^\\\"\\\\])*\\\"(?=\\s*:)", color: NSColor.systemBlue, to: attributed)
        applyRegex("\\b-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b", color: NSColor.systemOrange, to: attributed)
        applyRegex("\\b(?:true|false|null)\\b", color: NSColor.systemPurple, to: attributed)

        return attributed
    }

    private static func applyRegex(_ pattern: String, color: NSColor, to attributed: NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: attributed.length)
        regex.matches(in: attributed.string, options: [], range: range).forEach { match in
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
