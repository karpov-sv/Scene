import SwiftUI
import AppKit

struct AppKitColorWell: NSViewRepresentable {
    @Binding var selection: CodableRGBA?
    var supportsOpacity: Bool = true
    var isBordered: Bool = true
    var autoDeactivateOnChange: Bool = false
    var isMixedSelection: Bool = false
    var mixedPlaceholderColor: NSColor = .quaternaryLabelColor

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selection: $selection,
            supportsOpacity: supportsOpacity,
            autoDeactivateOnChange: autoDeactivateOnChange,
            isMixedSelection: isMixedSelection,
            mixedPlaceholderColor: mixedPlaceholderColor
        )
    }

    func makeNSView(context: Context) -> NSColorWell {
        let colorWell = NSColorWell(frame: .zero)
        colorWell.target = context.coordinator
        colorWell.action = #selector(Coordinator.colorDidChange(_:))
        colorWell.isBordered = isBordered
        colorWell.colorWellStyle = .minimal
        configureAlphaSupport(for: colorWell, enabled: supportsOpacity)
        colorWell.color = context.coordinator.nsColor(from: selection)
        return colorWell
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.supportsOpacity = supportsOpacity
        context.coordinator.autoDeactivateOnChange = autoDeactivateOnChange
        context.coordinator.isMixedSelection = isMixedSelection
        context.coordinator.mixedPlaceholderColor = mixedPlaceholderColor
        nsView.colorWellStyle = .minimal
        configureAlphaSupport(for: nsView, enabled: supportsOpacity)
        nsView.isBordered = isBordered

        // NSColorWell uses shared NSColorPanel. While it is visible, avoid
        // any model->well color synchronization to prevent cross-talk.
        if NSColorPanel.shared.isVisible {
            return
        }

        let desiredColor = context.coordinator.nsColor(from: selection)
        if !context.coordinator.colorsMatch(nsView.color, desiredColor) {
            nsView.color = desiredColor
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<CodableRGBA?>
        var supportsOpacity: Bool
        var autoDeactivateOnChange: Bool
        var isMixedSelection: Bool
        var mixedPlaceholderColor: NSColor

        init(
            selection: Binding<CodableRGBA?>,
            supportsOpacity: Bool,
            autoDeactivateOnChange: Bool,
            isMixedSelection: Bool,
            mixedPlaceholderColor: NSColor
        ) {
            self.selection = selection
            self.supportsOpacity = supportsOpacity
            self.autoDeactivateOnChange = autoDeactivateOnChange
            self.isMixedSelection = isMixedSelection
            self.mixedPlaceholderColor = mixedPlaceholderColor
        }

        @objc func colorDidChange(_ sender: NSColorWell) {
            guard sender.isActive else { return }
            if !isUserSelectableColor(sender.color) {
                // Color selector was dismissed
                return
            }

            let fallbackColor = nsColor(from: selection.wrappedValue)
            let normalized = normalizedColor(from: sender.color, fallback: fallbackColor)
            if isMixedSelection && selection.wrappedValue == nil {
                let placeholder = normalizedColor(from: mixedPlaceholderColor)
                if colorsMatch(normalized, placeholder) {
                    return
                }
            }
            let rgba = rgba(from: normalized)
            if !rgbaMatch(selection.wrappedValue, rgba) {
                selection.wrappedValue = rgba
                if autoDeactivateOnChange {
                    sender.deactivate()
                }
            }
        }

        func nsColor(from rgba: CodableRGBA?) -> NSColor {
            if isMixedSelection {
                return normalizedColor(from: mixedPlaceholderColor)
            }
            guard let rgba else { return normalizedColor(from: mixedPlaceholderColor) }
            return NSColor(
                deviceRed: CGFloat(rgba.red),
                green: CGFloat(rgba.green),
                blue: CGFloat(rgba.blue),
                alpha: CGFloat(supportsOpacity ? rgba.alpha : 1.0)
            )
        }

        func rgba(from source: NSColor) -> CodableRGBA {
            let rgb = normalizedColor(from: source)
            return CodableRGBA(
                red: quantize(Double(rgb.redComponent)),
                green: quantize(Double(rgb.greenComponent)),
                blue: quantize(Double(rgb.blueComponent)),
                alpha: quantize(Double(rgb.alphaComponent))
            )
        }

        func normalizedColor(
            from source: NSColor,
            fallback fallbackColor: NSColor = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1.0)
        ) -> NSColor {
            let rgb = source.usingColorSpace(.deviceRGB) ?? normalizedColorFallback(from: fallbackColor)
            let alpha: CGFloat = supportsOpacity ? rgb.alphaComponent : 1.0
            return NSColor(
                deviceRed: rgb.redComponent,
                green: rgb.greenComponent,
                blue: rgb.blueComponent,
                alpha: alpha
            )
        }

        func isUserSelectableColor(_ color: NSColor) -> Bool {
            if isSystemCatalogColor(color) {
                return false
            }
            let model = color.colorSpace.colorSpaceModel
            return model == .rgb || model == .gray
        }

        func isSystemCatalogColor(_ color: NSColor) -> Bool {
            if #available(macOS 10.13, *) {
                if color.type == .catalog &&
                    color.catalogNameComponent.caseInsensitiveCompare("System") == .orderedSame {
                    return true
                }
            }

            // Fallback for dynamic system named colors such as "Catalog color:
            // System textColor", which can be emitted on panel dismiss.
            let description = color.description.lowercased()
            return description.contains("catalog color: system")
        }

        func normalizedColorFallback(from fallbackColor: NSColor) -> NSColor {
            fallbackColor.usingColorSpace(.deviceRGB)
                ?? NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1.0)
        }

        func rgbaMatch(_ lhs: CodableRGBA?, _ rhs: CodableRGBA) -> Bool {
            guard let lhs else { return false }
            let tolerance = 0.5 / 255.0
            return abs(lhs.red - rhs.red) <= tolerance &&
            abs(lhs.green - rhs.green) <= tolerance &&
            abs(lhs.blue - rhs.blue) <= tolerance &&
            abs(lhs.alpha - rhs.alpha) <= tolerance
        }

        func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
            let l = normalizedColor(from: lhs)
            let r = normalizedColor(from: rhs)
            let tolerance: CGFloat = 0.5 / 255.0
            return abs(l.redComponent - r.redComponent) <= tolerance &&
            abs(l.greenComponent - r.greenComponent) <= tolerance &&
            abs(l.blueComponent - r.blueComponent) <= tolerance &&
            abs(l.alphaComponent - r.alphaComponent) <= tolerance
        }

        private func quantize(_ component: Double) -> Double {
            let clamped = min(1.0, max(0.0, component))
            return (clamped * 255.0).rounded() / 255.0
        }
    }

    private func configureAlphaSupport(for colorWell: NSColorWell, enabled: Bool) {
        colorWell.supportsAlpha = enabled
    }
}
