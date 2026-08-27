import AppKit
import SwiftUI

enum LaneColor {
    static let accent = Color(red: 0.42, green: 0.47, blue: 0.91)
    static let accentSoft = Color(red: 0.65, green: 0.68, blue: 0.97)
    static let primaryActionFill = LinearGradient(
        colors: [
            Color(
                .displayP3,
                red: 69.0 / 255.0,
                green: 71.0 / 255.0,
                blue: 170.0 / 255.0,
                opacity: 1
            ),
            Color(
                .displayP3,
                red: 38.0 / 255.0,
                green: 39.0 / 255.0,
                blue: 155.0 / 255.0,
                opacity: 1
            ),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    static let mint = Color(red: 0.31, green: 0.76, blue: 0.66)
    static let amber = Color(red: 0.85, green: 0.60, blue: 0.34)
    static let danger = Color(red: 0.86, green: 0.34, blue: 0.39)
    static let canvas = Color.white
    static let surface = Color.white
    static let toolbar = Color.white
    static let sidebar = Color.white
    static let line = Color.primary.opacity(0.09)
    static let label1 = Color(nsColor: .labelColor)
    static let label2 = Color(nsColor: .secondaryLabelColor)
    static let fill1 = adaptive(
        light: NSColor.black.withAlphaComponent(0.03),
        dark: NSColor.white.withAlphaComponent(0.05)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? dark
                    : light
            }
        )
    }
}

enum LaneFont {
    static func display(_ size: CGFloat) -> Font {
        .custom("PublicSans-SemiBold", size: size)
    }

    static func label(_ size: CGFloat) -> Font {
        .custom("PublicSans-Medium", size: size)
    }

    static func interface(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        .custom(interfaceFontName(for: weight), size: size)
    }

    static func utility(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private static func interfaceFontName(for weight: Font.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black {
            return "PublicSans-Bold"
        }
        if weight == .semibold {
            return "PublicSans-SemiBold"
        }
        if weight == .medium {
            return "PublicSans-Medium"
        }
        return "PublicSans-Regular"
    }
}

enum LaneMetric {
    static let cornerRadius: CGFloat = 14
    static let compactRadius: CGFloat = 9
    static let contentPadding: CGFloat = 24
}

struct LaneCompactActionButtonStyle: ButtonStyle {
    enum Tone {
        case neutral
        case accent
        case destructive
    }

    enum Surface {
        case quiet
        case tinted
    }

    var tone: Tone = .neutral
    var surface: Surface = .quiet
    var minimumHeight: CGFloat = 26
    var horizontalPadding: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        LaneCompactActionButtonStyleBody(
            configuration: configuration,
            tone: tone,
            surface: surface,
            minimumHeight: minimumHeight,
            horizontalPadding: horizontalPadding
        )
    }
}

private struct LaneCompactActionButtonStyleBody: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let configuration: ButtonStyleConfiguration
    let tone: LaneCompactActionButtonStyle.Tone
    let surface: LaneCompactActionButtonStyle.Surface
    let minimumHeight: CGFloat
    let horizontalPadding: CGFloat

    var body: some View {
        configuration.label
            .font(LaneFont.interface(10.5, weight: .medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: minimumHeight)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: 7.5, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .contentShape(
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
            )
            .scaleEffect(
                isEnabled && configuration.isPressed && !reduceMotion
                    ? 0.985
                    : 1
            )
            .onHover { isHovering = $0 }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.11),
                value: configuration.isPressed
            )
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var foregroundColor: Color {
        guard isEnabled else {
            return Color(nsColor: .tertiaryLabelColor)
        }

        switch tone {
        case .neutral:
            return LaneColor.label1
        case .accent:
            return LaneColor.accent
        case .destructive:
            return LaneColor.danger
        }
    }

    private var backgroundColor: Color {
        guard isEnabled else {
            return LaneColor.fill1.opacity(0.72)
        }

        let strength: Double
        if configuration.isPressed {
            strength = surface == .tinted ? 0.17 : 0.09
        } else if isHovering {
            strength = surface == .tinted ? 0.13 : 0.065
        } else {
            strength = surface == .tinted ? 0.085 : 0.03
        }

        return toneColor.opacity(strength)
    }

    private var borderColor: Color {
        guard isEnabled else {
            return LaneColor.line.opacity(0.72)
        }

        switch tone {
        case .neutral:
            return Color.primary.opacity(isHovering ? 0.16 : 0.09)
        case .accent, .destructive:
            return toneColor.opacity(isHovering ? 0.36 : 0.22)
        }
    }

    private var toneColor: Color {
        switch tone {
        case .neutral:
            return Color.primary
        case .accent:
            return LaneColor.accent
        case .destructive:
            return LaneColor.danger
        }
    }
}

enum LaneAdaptiveSheetSize {
    static func downloadComposer(in availableSize: CGSize) -> CGSize {
        CGSize(
            width: fittedDimension(
                availableSize.width,
                fallback: 920,
                minimum: 500,
                maximum: 1_040,
                inset: 24
            ),
            height: fittedDimension(
                availableSize.height,
                fallback: 720,
                minimum: 520,
                maximum: 800,
                inset: 24
            )
        )
    }

    static func rssEditor(in availableSize: CGSize) -> CGSize {
        CGSize(
            width: fittedDimension(
                availableSize.width,
                fallback: 640,
                minimum: 460,
                maximum: 720,
                inset: 16
            ),
            height: fittedDimension(
                availableSize.height,
                fallback: 700,
                minimum: 500,
                maximum: 760,
                inset: 16
            )
        )
    }

    private static func fittedDimension(
        _ availableDimension: CGFloat,
        fallback: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat,
        inset: CGFloat
    ) -> CGFloat {
        guard availableDimension.isFinite, availableDimension > 0 else {
            return fallback
        }
        return min(maximum, max(minimum, availableDimension - inset))
    }
}

private struct LaneWindowContentSizeKey: EnvironmentKey {
    static let defaultValue = CGSize(width: 1_120, height: 720)
}

extension EnvironmentValues {
    var laneWindowContentSize: CGSize {
        get { self[LaneWindowContentSizeKey.self] }
        set { self[LaneWindowContentSizeKey.self] = newValue }
    }
}

extension View {
    func laneSurface(cornerRadius: CGFloat = LaneMetric.cornerRadius) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LaneColor.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(LaneColor.line, lineWidth: 1)
                }
        }
    }

    /// Keeps native macOS list selection behavior while allowing each row to
    /// draw AriaLane's own quiet selected state.
    func laneListSelectionAppearance() -> some View {
        background {
            LaneListSelectionConfigurator()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}

private struct LaneListSelectionConfigurator: NSViewRepresentable {
    final class Coordinator {
        weak var tableView: NSTableView?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureTableView(containing: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureTableView(containing: nsView, coordinator: context.coordinator)
    }

    private func configureTableView(
        containing view: NSView,
        coordinator: Coordinator
    ) {
        if let tableView = coordinator.tableView {
            tableView.selectionHighlightStyle = .none
            return
        }

        DispatchQueue.main.async {
            var ancestor = view.superview
            while let current = ancestor {
                if let tableView = current as? NSTableView {
                    tableView.selectionHighlightStyle = .none
                    coordinator.tableView = tableView
                    return
                }
                ancestor = current.superview
            }
        }
    }
}
