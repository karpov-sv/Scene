import SwiftUI
import AppKit

enum SceneFontSelectorData {
    static let systemFamily = "System"

    static let commonFamilies: [String] = [
        systemFamily,
        "Avenir Next",
        "Helvetica Neue",
        "Times New Roman",
        "Georgia",
        "Baskerville",
        "Menlo",
        "Courier New"
    ]

    static let commonSizes: [Double] = [
        9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 24, 28, 32, 36, 48, 64
    ]

    static func normalizedFamily(_ family: String) -> String {
        let trimmed = family.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || isSystemAlias(trimmed) || trimmed.hasPrefix(".") {
            return systemFamily
        }
        return trimmed
    }

    static func isUserSelectableFamily(_ family: String) -> Bool {
        let trimmed = family.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.hasPrefix(".") else { return false }
        return !isSystemAlias(trimmed)
    }

    static func isSystemAlias(_ family: String) -> Bool {
        let trimmed = family.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if trimmed.caseInsensitiveCompare(systemFamily) == .orderedSame {
            return true
        }

        let lower = trimmed.lowercased()
        let compact = lower.replacingOccurrences(of: " ", with: "")
        return compact.hasPrefix(".sfns")
            || compact.contains("sfns")
            || compact.hasPrefix(".apple")
            || compact.contains("applesystemui")
            || compact.contains("systemui")
    }
}

struct FontFamilyDropdown: View {
    let selectedFamily: String
    var previewPointSize: CGFloat = 13
    var controlSize: ControlSize = .regular
    var allFamilies: [String] = {
        let rawFamilies = NSFontManager.shared.availableFontFamilies
        var seen = Set<String>()
        var output: [String] = []
        for family in rawFamilies {
            let normalized = SceneFontSelectorData.normalizedFamily(family)
            guard SceneFontSelectorData.isUserSelectableFamily(normalized) else { continue }
            if seen.insert(normalized).inserted {
                output.append(normalized)
            }
        }
        return output.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }()
    let onSelectFamily: (String) -> Void
    let onOpenSystemFontPanel: () -> Void

    private var normalizedSelectedFamily: String {
        SceneFontSelectorData.normalizedFamily(selectedFamily)
    }

    private var commonFamilies: [String] {
        var result: [String] = [SceneFontSelectorData.systemFamily]
        for family in SceneFontSelectorData.commonFamilies where family != SceneFontSelectorData.systemFamily {
            if allFamilies.contains(family) {
                result.append(family)
            }
        }
        if normalizedSelectedFamily != SceneFontSelectorData.systemFamily,
           !result.contains(normalizedSelectedFamily) {
            result.append(normalizedSelectedFamily)
        }
        return result
    }

    private var allFontFamiliesSection: [String] {
        allFamilies
    }

    var body: some View {
        Menu {
            ForEach(commonFamilies, id: \.self) { family in
                Button {
                    onSelectFamily(family)
                } label: {
                    fontRowLabel(for: family)
                }
            }

            Divider()
            Button("Open System Font Panel...") {
                onOpenSystemFontPanel()
            }
            Divider()

            ForEach(allFontFamiliesSection, id: \.self) { family in
                Button {
                    onSelectFamily(family)
                } label: {
                    fontRowLabel(for: family)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(displayName(for: normalizedSelectedFamily))
                    .font(previewFont(for: normalizedSelectedFamily))
                    .lineLimit(1)
            }
        }
        .controlSize(controlSize)
    }

    @ViewBuilder
    private func fontRowLabel(for family: String) -> some View {
        HStack(spacing: 8) {
            Text(displayName(for: family))
                .font(previewFont(for: family))
            if SceneFontSelectorData.normalizedFamily(family) == normalizedSelectedFamily {
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
            }
        }
    }

    private func displayName(for family: String) -> String {
        let normalized = SceneFontSelectorData.normalizedFamily(family)
        return normalized == SceneFontSelectorData.systemFamily ? "System Font" : normalized
    }

    private func previewFont(for family: String) -> Font {
        let normalized = SceneFontSelectorData.normalizedFamily(family)
        let pointSize = max(10, min(previewPointSize, 22))
        if normalized == SceneFontSelectorData.systemFamily {
            return .system(size: pointSize)
        }

        if let namedFont = NSFont(name: normalized, size: pointSize) {
            return Font(namedFont)
        }

        if let familyFont = NSFontManager.shared.font(
            withFamily: normalized,
            traits: [],
            weight: 5,
            size: pointSize
        ) {
            return Font(familyFont)
        }

        return .system(size: pointSize)
    }
}

struct FontSizeDropdown: View {
    let selectedSize: Double
    var controlSize: ControlSize = .regular
    var supportedSizes: [Double] = SceneFontSelectorData.commonSizes
    let onSelectSize: (Double) -> Void

    private var normalizedSize: Double {
        max(1, selectedSize)
    }

    var body: some View {
        Menu {
            ForEach(supportedSizes, id: \.self) { size in
                Button {
                    onSelectSize(size)
                } label: {
                    HStack(spacing: 8) {
                        Text(sizeLabel(size))
                            .monospacedDigit()
                        if abs(size - normalizedSize) < 0.01 {
                            Spacer(minLength: 0)
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(sizeLabel(normalizedSize))
                    .monospacedDigit()
            }
        }
        .controlSize(controlSize)
    }

    private func sizeLabel(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.01 {
            return "\(Int(value.rounded())) pt"
        }
        return String(format: "%.1f pt", value)
    }
}
