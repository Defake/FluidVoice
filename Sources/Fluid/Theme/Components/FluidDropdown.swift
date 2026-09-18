import SwiftUI

/// Shared dropdown surface. Native menus, pickers, and searchable popovers use
/// this appearance while retaining their own selection and presentation logic.
struct FluidDropdownSurface: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        let highlighted = self.isHovered && self.isEnabled
        content
            .background {
                RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                    .fill(self.theme.palette.elevatedCardBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                            .fill(self.theme.palette.accent.opacity(highlighted ? 0.08 : 0))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                    .strokeBorder(highlighted ? self.theme.palette.accent.opacity(0.45) : self.theme.palette.cardBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
            .onHover { self.isHovered = $0 }
            .animation(self.reduceMotion ? nil : .easeOut(duration: 0.14), value: highlighted)
    }
}

struct FluidDropdownChevron: View {
    @Environment(\.theme) private var theme
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.fluidSystem(size: 10, weight: .semibold))
            .foregroundStyle(self.theme.palette.secondaryText)
            .accessibilityHidden(true)
    }
}

private struct FluidDropdownControlStyle: ViewModifier {
    var fillsWidth = false

    @Environment(\.theme) private var theme

    @ViewBuilder func body(content: Content) -> some View {
        if self.fillsWidth {
            content
                .menuStyle(.button)
                .buttonStyle(FluidDropdownButtonStyle(fillsWidth: true))
                .menuIndicator(.hidden)
                .labelsHidden()
        } else {
            content
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .labelsHidden()
                .font(self.theme.typography.bodySmall)
                .foregroundStyle(self.theme.palette.primaryText)
                .padding(.leading, 12)
                .padding(.trailing, 30)
                .padding(.vertical, 9)
                .fluidDropdownSurface()
                .overlay(alignment: .trailing) {
                    FluidDropdownChevron().padding(.trailing, 12).allowsHitTesting(false)
                }
        }
    }
}

/// Keep the surface inside the native control's label, so its padding and
/// expanded width participate in hit testing, not just the selected text.
private struct FluidDropdownButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    let fillsWidth: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(self.theme.typography.bodySmall)
            .foregroundStyle(self.theme.palette.primaryText)
            .frame(maxWidth: self.fillsWidth ? .infinity : nil, alignment: .leading)
            .padding(.leading, 12)
            .padding(.trailing, 30)
            .padding(.vertical, 9)
            .fluidDropdownSurface()
            .overlay(alignment: .trailing) {
                FluidDropdownChevron().padding(.trailing, 12).allowsHitTesting(false)
            }
    }
}

extension View {
    /// Apply outside a native menu/picker, rather than inside its label:
    /// macOS may flatten label styling when building the native control.
    /// Full-width selectors use a Menu containing an inline Picker. Native
    /// menu Pickers and borderless menus ignore custom ButtonStyle hit geometry.
    func fluidDropdownStyle(fillsWidth: Bool = false) -> some View {
        modifier(FluidDropdownControlStyle(fillsWidth: fillsWidth))
    }

    /// For custom searchable controls that provide their own label and chevron.
    func fluidDropdownSurface(cornerRadius: CGFloat = 10) -> some View {
        modifier(FluidDropdownSurface(cornerRadius: cornerRadius))
    }
}

struct FluidDropdown<Content: View>: View {
    let title: String
    var width: CGFloat = 192
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: self.content) { Text(self.title) }
            .fluidDropdownStyle()
            .frame(width: self.width)
    }
}
