import SwiftUI

enum AstraThemeID: String, CaseIterable, Codable, Identifiable {
    case classic
    case voyager
    case picardModern
    case horizon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .voyager: "Voyager"
        case .picardModern: "Picard Modern"
        case .horizon: "Horizon HUD"
        }
    }

    var shortTitle: String {
        switch self {
        case .classic: "CLS"
        case .voyager: "VOY"
        case .picardModern: "PIC"
        case .horizon: "HUD"
        }
    }

    var theme: AstraConsoleTheme {
        switch self {
        case .classic: .classic
        case .voyager: .voyager
        case .picardModern: .picardModern
        case .horizon: .horizon
        }
    }
}

enum AstraColorRole: String, CaseIterable, Codable {
    case apricot
    case gold
    case violet
    case rose
    case cyan
    case mint
    case red
    case blue
}

struct AstraPalette {
    var screen: Color
    var screenGradient: Color
    var text: Color
    var mutedText: Color
    var panel: Color
    var panelHighlight: Color
    var gridMinor: Color
    var gridMajor: Color
    var roles: [AstraColorRole: Color]

    func color(_ role: AstraColorRole) -> Color {
        roles[role] ?? roles[.apricot] ?? .orange
    }
}

struct AstraMetrics {
    var outerPadding: CGFloat
    var gap: CGFloat
    var fineGap: CGFloat
    var rail: CGFloat
    var minorRail: CGFloat
    var terminalRadius: CGFloat
    var panelRadius: CGFloat
    var dataRadius: CGFloat
    var panelOpacity: Double
}

struct AstraTypography {
    var displayFamily: String
    /// `nil` renders data labels in the system monospaced face.
    var dataFamily: String?
    /// Heaviest weight the display face should be asked for. Thin
    /// holographic faces look wrong at `.black`, so themes can cap it.
    var maxDisplayWeight: Font.Weight = .black
    /// Extra tracking applied to display labels (points).
    var displayTracking: CGFloat = 0

    init(displayFamily: String, dataFamily: String?, maxDisplayWeight: Font.Weight = .black, displayTracking: CGFloat = 0) {
        self.displayFamily = displayFamily
        self.dataFamily = dataFamily
        self.maxDisplayWeight = maxDisplayWeight
        self.displayTracking = displayTracking
    }

    func display(size: CGFloat, weight: Font.Weight = .black) -> Font {
        .custom(displayFamily, size: max(size, 14)).weight(cappedWeight(weight))
    }

    func data(size: CGFloat, weight: Font.Weight = .black) -> Font {
        if let dataFamily {
            return .custom(dataFamily, size: max(size, 12.5)).weight(weight)
        }
        return .system(size: max(size, 11.5), weight: weight == .black ? .semibold : weight, design: .monospaced)
    }

    func systemData(size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: max(size, 12), weight: weight, design: .monospaced)
    }

    private func cappedWeight(_ weight: Font.Weight) -> Font.Weight {
        let order: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        guard let wanted = order.firstIndex(of: weight), let cap = order.firstIndex(of: maxDisplayWeight) else { return weight }
        return order[min(wanted, cap)]
    }
}

/// How colored chrome is rendered.
enum AstraChromeStyle: Sendable, Equatable {
    /// LCARS-era: solid colored bars with black labels.
    case solid
    /// Holographic: thin luminous outlines over a faint tint, labels in the
    /// accent color, optional glow.
    case hairline
}

/// Static texture behind the console.
enum AstraBackdropStyle: Sendable, Equatable {
    case grid
    /// Dot lattice with faint concentric range rings and a horizon line.
    case reticle
}

struct AstraConsoleTheme {
    var id: AstraThemeID
    var palette: AstraPalette
    var metrics: AstraMetrics
    var typography: AstraTypography
    var animationIntensity: Double
    var chrome: AstraChromeStyle = .solid
    var backdrop: AstraBackdropStyle = .grid
    /// Blur radius of the glow behind chrome; 0 disables it.
    var glowRadius: CGFloat = 0

    func color(_ role: AstraColorRole) -> Color {
        palette.color(role)
    }

    // MARK: Chrome rendering

    /// Fill behind a piece of chrome carrying `role`.
    func chromeFill(_ role: AstraColorRole) -> Color {
        switch chrome {
        case .solid: color(role)
        case .hairline: color(role).opacity(0.13)
        }
    }

    /// Outline of a piece of chrome; clear for solid themes.
    func chromeStroke(_ role: AstraColorRole) -> Color {
        switch chrome {
        case .solid: .clear
        case .hairline: color(role).opacity(0.88)
        }
    }

    var chromeStrokeWidth: CGFloat {
        chrome == .hairline ? 1.2 : 0
    }

    /// Color for labels drawn on top of chrome.
    func chromeText(_ role: AstraColorRole) -> Color {
        switch chrome {
        case .solid: .black
        case .hairline: color(role)
        }
    }

    /// Color of an unlit segment/cell in gauges.
    func inactiveCell(_ role: AstraColorRole) -> Color {
        switch chrome {
        case .solid: palette.text.opacity(0.09)
        case .hairline: color(role).opacity(0.10)
        }
    }

    static let classic = AstraConsoleTheme(
        id: .classic,
        palette: AstraPalette(
            screen: Color(red: 0.006, green: 0.005, blue: 0.008),
            screenGradient: Color(red: 0.055, green: 0.024, blue: 0.045),
            text: Color(red: 0.96, green: 0.94, blue: 0.90),
            mutedText: Color(red: 0.70, green: 0.68, blue: 0.76),
            panel: Color(red: 0.020, green: 0.018, blue: 0.024),
            panelHighlight: Color(red: 0.090, green: 0.060, blue: 0.090),
            gridMinor: Color.white.opacity(0.028),
            gridMajor: Color(red: 1.0, green: 0.62, blue: 0.24).opacity(0.055),
            roles: [
                .apricot: Color(red: 1.00, green: 0.54, blue: 0.27),
                .gold: Color(red: 1.00, green: 0.76, blue: 0.18),
                .violet: Color(red: 0.74, green: 0.58, blue: 1.00),
                .rose: Color(red: 1.00, green: 0.78, blue: 0.86),
                .cyan: Color(red: 0.58, green: 0.66, blue: 1.00),
                .mint: Color(red: 1.00, green: 0.92, blue: 0.42),
                .red: Color(red: 0.90, green: 0.24, blue: 0.22),
                .blue: Color(red: 0.44, green: 0.58, blue: 0.98)
            ]
        ),
        metrics: AstraMetrics(
            outerPadding: 18,
            gap: 12,
            fineGap: 5,
            rail: 46,
            minorRail: 14,
            terminalRadius: 28,
            panelRadius: 8,
            dataRadius: 4,
            panelOpacity: 0.78
        ),
        typography: AstraTypography(displayFamily: "HelveticaNeue-CondensedBlack", dataFamily: "DINCondensed-Bold"),
        animationIntensity: 1
    )

    static let voyager = AstraConsoleTheme(
        id: .voyager,
        palette: AstraPalette(
            screen: Color(red: 0.008, green: 0.008, blue: 0.013),
            screenGradient: Color(red: 0.042, green: 0.032, blue: 0.055),
            text: Color(red: 0.97, green: 0.93, blue: 0.86),
            mutedText: Color(red: 0.74, green: 0.70, blue: 0.80),
            panel: Color(red: 0.024, green: 0.021, blue: 0.032),
            panelHighlight: Color(red: 0.060, green: 0.056, blue: 0.096),
            gridMinor: Color.white.opacity(0.030),
            gridMajor: Color(red: 0.65, green: 0.62, blue: 1.0).opacity(0.065),
            roles: [
                .apricot: Color(red: 1.00, green: 0.60, blue: 0.34),
                .gold: Color(red: 1.00, green: 0.80, blue: 0.42),
                .violet: Color(red: 0.78, green: 0.58, blue: 0.86),
                .rose: Color(red: 0.82, green: 0.34, blue: 0.58),
                .cyan: Color(red: 0.55, green: 0.78, blue: 1.00),
                .mint: Color(red: 0.35, green: 0.82, blue: 0.70),
                .red: Color(red: 0.93, green: 0.26, blue: 0.23),
                .blue: Color(red: 0.42, green: 0.55, blue: 0.96)
            ]
        ),
        metrics: AstraMetrics(
            outerPadding: 18,
            gap: 10,
            fineGap: 4,
            rail: 44,
            minorRail: 10,
            terminalRadius: 24,
            panelRadius: 9,
            dataRadius: 4,
            panelOpacity: 0.70
        ),
        typography: AstraTypography(displayFamily: "HelveticaNeue-CondensedBlack", dataFamily: "DINCondensed-Bold"),
        animationIntensity: 1.08
    )

    static let picardModern = AstraConsoleTheme(
        id: .picardModern,
        palette: AstraPalette(
            screen: Color(red: 0.004, green: 0.010, blue: 0.016),
            screenGradient: Color(red: 0.010, green: 0.060, blue: 0.080),
            text: Color(red: 0.90, green: 0.98, blue: 1.00),
            mutedText: Color(red: 0.56, green: 0.76, blue: 0.84),
            panel: Color(red: 0.010, green: 0.030, blue: 0.045),
            panelHighlight: Color(red: 0.018, green: 0.090, blue: 0.120),
            gridMinor: Color(red: 0.20, green: 0.72, blue: 0.90).opacity(0.038),
            gridMajor: Color(red: 0.15, green: 0.86, blue: 0.95).opacity(0.080),
            roles: [
                .apricot: Color(red: 1.00, green: 0.52, blue: 0.18),
                .gold: Color(red: 1.00, green: 0.77, blue: 0.22),
                .violet: Color(red: 0.40, green: 0.68, blue: 1.00),
                .rose: Color(red: 1.00, green: 0.31, blue: 0.30),
                .cyan: Color(red: 0.14, green: 0.82, blue: 0.95),
                .mint: Color(red: 0.24, green: 0.94, blue: 0.78),
                .red: Color(red: 1.00, green: 0.12, blue: 0.10),
                .blue: Color(red: 0.18, green: 0.46, blue: 0.94)
            ]
        ),
        metrics: AstraMetrics(
            outerPadding: 16,
            gap: 9,
            fineGap: 4,
            rail: 44,
            minorRail: 8,
            terminalRadius: 24,
            panelRadius: 7,
            dataRadius: 3,
            panelOpacity: 0.76
        ),
        typography: AstraTypography(displayFamily: "HelveticaNeue-CondensedBlack", dataFamily: "DINCondensed-Bold"),
        animationIntensity: 1.18
    )

    /// Deep-space holographic HUD: near-black blue glass, ice-cyan hairline
    /// chrome with a soft glow, thin geometric type, reticle backdrop.
    /// Warm roles are remapped to amber/coral so warnings still read as warm.
    static let horizon = AstraConsoleTheme(
        id: .horizon,
        palette: AstraPalette(
            screen: Color(red: 0.004, green: 0.012, blue: 0.024),
            screenGradient: Color(red: 0.020, green: 0.075, blue: 0.130),
            text: Color(red: 0.86, green: 0.96, blue: 1.00),
            mutedText: Color(red: 0.46, green: 0.70, blue: 0.82),
            panel: Color(red: 0.012, green: 0.040, blue: 0.068),
            panelHighlight: Color(red: 0.030, green: 0.110, blue: 0.170),
            gridMinor: Color(red: 0.30, green: 0.85, blue: 1.00).opacity(0.050),
            gridMajor: Color(red: 0.30, green: 0.85, blue: 1.00).opacity(0.110),
            roles: [
                .apricot: Color(red: 1.00, green: 0.72, blue: 0.36),
                .gold: Color(red: 1.00, green: 0.84, blue: 0.46),
                .violet: Color(red: 0.62, green: 0.74, blue: 1.00),
                .rose: Color(red: 1.00, green: 0.52, blue: 0.58),
                .cyan: Color(red: 0.36, green: 0.92, blue: 1.00),
                .mint: Color(red: 0.62, green: 1.00, blue: 0.90),
                .red: Color(red: 1.00, green: 0.30, blue: 0.34),
                .blue: Color(red: 0.34, green: 0.62, blue: 1.00)
            ]
        ),
        metrics: AstraMetrics(
            outerPadding: 18,
            gap: 12,
            fineGap: 6,
            rail: 40,
            minorRail: 8,
            terminalRadius: 6,
            panelRadius: 4,
            dataRadius: 2,
            panelOpacity: 0.55
        ),
        typography: AstraTypography(
            displayFamily: "AvenirNextCondensed-DemiBold",
            dataFamily: nil,
            maxDisplayWeight: .semibold,
            displayTracking: 1.4
        ),
        animationIntensity: 1.25,
        chrome: .hairline,
        backdrop: .reticle,
        glowRadius: 5
    )
}

private struct AstraThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = AstraConsoleTheme.classic
}

extension EnvironmentValues {
    var astraTheme: AstraConsoleTheme {
        get { self[AstraThemeEnvironmentKey.self] }
        set { self[AstraThemeEnvironmentKey.self] = newValue }
    }
}

extension AstraColorRole {
    var classicColor: Color {
        AstraConsoleTheme.classic.color(self)
    }

    var color: Color {
        classicColor
    }

    func color(in theme: AstraConsoleTheme) -> Color {
        theme.color(self)
    }
}

struct AstraPartialRoundedRectangle: InsettableShape {
    var leadingRadius: CGFloat
    var trailingRadius: CGFloat
    var insetAmount: CGFloat = 0

    init(leadingRadius: CGFloat, trailingRadius: CGFloat) {
        self.leadingRadius = leadingRadius
        self.trailingRadius = trailingRadius
    }

    func path(in rect: CGRect) -> Path {
        let inner = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radii = RectangleCornerRadii(
            topLeading: max(0, leadingRadius - insetAmount),
            bottomLeading: max(0, leadingRadius - insetAmount),
            bottomTrailing: max(0, trailingRadius - insetAmount),
            topTrailing: max(0, trailingRadius - insetAmount)
        )
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: inner)
    }

    func inset(by amount: CGFloat) -> AstraPartialRoundedRectangle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Renders a view as a piece of console chrome in the current theme: a
/// solid colored block (LCARS-era themes) or a luminous hairline outline
/// over a faint tint with glow (holographic themes). Pair it with
/// `theme.chromeText(role)` for the label color.
struct AstraChromeModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.astraTheme) private var theme
    var role: AstraColorRole
    var shape: S
    var emphasis: Double

    func body(content: Content) -> some View {
        content
            .background(theme.chromeFill(role).opacity(emphasis), in: shape)
            .overlay {
                if theme.chrome == .hairline {
                    shape.strokeBorder(theme.chromeStroke(role).opacity(emphasis), lineWidth: theme.chromeStrokeWidth)
                }
            }
            .shadow(color: theme.glowRadius > 0 ? theme.color(role).opacity(0.38 * emphasis) : .clear, radius: theme.glowRadius)
    }
}

extension View {
    /// See `AstraChromeModifier`. `emphasis` dims the chrome (0...1) for
    /// inactive states without changing its shape language.
    func astraChrome<S: InsettableShape>(_ role: AstraColorRole, in shape: S, emphasis: Double = 1) -> some View {
        modifier(AstraChromeModifier(role: role, shape: shape, emphasis: emphasis))
    }
}

/// A solid block of chrome (no content): the rails, caps and segments of
/// the console frames. Draws as fill or hairline according to the theme.
struct AstraChromeBlock<S: InsettableShape>: View {
    @Environment(\.astraTheme) private var theme
    var role: AstraColorRole
    var shape: S
    var emphasis: Double = 1

    var body: some View {
        Color.clear
            .astraChrome(role, in: shape, emphasis: emphasis)
    }
}

struct AstraPanel<Content: View>: View {
    @Environment(\.astraTheme) private var theme
    var accent: AstraColorRole
    var railEdge: HorizontalEdge = .leading
    var contentPadding: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: theme.metrics.fineGap) {
            if railEdge == .leading {
                rail
            }
            content
                .padding(contentPadding ?? theme.metrics.gap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(theme.palette.panel.opacity(theme.metrics.panelOpacity), in: panelShape)
            if railEdge == .trailing {
                rail
            }
        }
        .background(theme.palette.panel.opacity(0.38), in: panelShape)
        .overlay(panelShape.stroke(theme.color(accent).opacity(0.48), lineWidth: 1))
    }

    private var panelShape: AstraPartialRoundedRectangle {
        AstraPartialRoundedRectangle(
            leadingRadius: railEdge == .leading ? theme.metrics.terminalRadius : theme.metrics.panelRadius,
            trailingRadius: railEdge == .trailing ? theme.metrics.terminalRadius : theme.metrics.panelRadius
        )
    }

    private var rail: some View {
        VStack(spacing: theme.metrics.fineGap) {
            theme.color(accent)
                .frame(height: theme.metrics.rail)
                .clipShape(AstraPartialRoundedRectangle(
                    leadingRadius: railEdge == .leading ? theme.metrics.terminalRadius : 0,
                    trailingRadius: railEdge == .trailing ? theme.metrics.terminalRadius : 0
                ))
            theme.color(.violet)
            theme.color(.gold)
                .frame(height: theme.metrics.rail * 0.64)
                .clipShape(AstraPartialRoundedRectangle(
                    leadingRadius: railEdge == .leading ? theme.metrics.terminalRadius : 0,
                    trailingRadius: railEdge == .trailing ? theme.metrics.terminalRadius : 0
                ))
        }
        .frame(width: theme.metrics.rail)
    }
}
