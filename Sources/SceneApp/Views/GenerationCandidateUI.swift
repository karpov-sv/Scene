import SwiftUI

enum GenerationCandidateUI {
    static func statusLabel(_ status: AppStore.ProseGenerationCandidate.Status) -> String {
        switch status {
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .completed:
            return "Ready"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    static func statusColor(_ status: AppStore.ProseGenerationCandidate.Status) -> Color {
        switch status {
        case .queued, .running:
            return .secondary
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }
}

struct GenerationCandidateStatusBadge: View {
    let status: AppStore.ProseGenerationCandidate.Status

    var body: some View {
        Text(GenerationCandidateUI.statusLabel(status))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(GenerationCandidateUI.statusColor(status))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(GenerationCandidateUI.statusColor(status).opacity(0.15))
            )
    }
}

struct GenerationCandidateTextPreview: View {
    let text: String
    let placeholder: String
    var fixedHeight: CGFloat? = nil
    var minHeight: CGFloat = 100
    var maxHeight: CGFloat = 220
    var font: Font = .body
    var chromeStyle: ChromeStyle = .outlined

    enum ChromeStyle {
        case outlined
        case subtle
    }

    private var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? placeholder : text
    }

    private var usesPlaceholder: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            Text(displayText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(font)
                .foregroundStyle(usesPlaceholder ? .secondary : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(height: fixedHeight)
        .frame(minHeight: fixedHeight == nil ? minHeight : nil, maxHeight: fixedHeight == nil ? maxHeight : nil)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if chromeStyle == .outlined {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var backgroundColor: Color {
        switch chromeStyle {
        case .outlined:
            return Color(nsColor: .textBackgroundColor)
        case .subtle:
            return Color(nsColor: .textBackgroundColor).opacity(0.25)
        }
    }

    private var cornerRadius: CGFloat {
        switch chromeStyle {
        case .outlined:
            return 6
        case .subtle:
            return 10
        }
    }
}

struct GenerationCandidateErrorBox: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}
