import SwiftUI
import QuartzCore

// Ambient loops (radar sweep, scrolling dashes) are rendered by Core
// Animation. The animations run on the render server, so once installed
// they cost zero app CPU per frame — no timeline ticks, no view diffing,
// no Canvas rasterization. The host view is AppKit on macOS and UIKit on
// tvOS (see PlatformShims); the layer code is identical on both.

// MARK: - Still rendering

/// Set by the gallery exporter: `ImageRenderer` cannot rasterize platform
/// views, so the overlays below swap their layer-backed host for a static
/// SwiftUI drawing of the same shape when this is true.
private struct AstraStaticRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var astraStaticRendering: Bool {
        get { self[AstraStaticRenderingKey.self] }
        set { self[AstraStaticRenderingKey.self] = newValue }
    }
}

/// Rotating sensor-sweep wedge; Core Animation when live, a fixed wedge in
/// stills.
struct SweepOverlay: View {
    @Environment(\.astraStaticRendering) private var isStatic
    var color: Color
    var period: Double
    var paused: Bool

    var body: some View {
        if isStatic {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.44
                var wedge = Path()
                wedge.move(to: center)
                wedge.addArc(center: center, radius: radius, startAngle: .degrees(-150), endAngle: .degrees(-130), clockwise: false)
                wedge.closeSubpath()
                context.fill(wedge, with: .color(color))
            }
        } else {
            SweepOverlayRepresentable(color: color, period: period, paused: paused)
        }
    }
}

/// Scrolling dashed polylines; Core Animation when live, static dashes in
/// stills.
struct DashFlowOverlay: View {
    @Environment(\.astraStaticRendering) private var isStatic
    var lines: [[CGPoint]]
    var color: Color
    var lineWidth: CGFloat
    var dash: [CGFloat]
    var cycleDuration: Double
    var paused: Bool

    var body: some View {
        if isStatic {
            Canvas { context, size in
                var path = Path()
                for line in lines {
                    guard let first = line.first else { continue }
                    path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                    for point in line.dropFirst() {
                        path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                    }
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round, dash: dash))
            }
        } else {
            DashFlowOverlayRepresentable(lines: lines, color: color, lineWidth: lineWidth, dash: dash, cycleDuration: cycleDuration, paused: paused)
        }
    }
}

/// Ambient scan band; nothing in stills.
struct ScanSweepOverlay: View {
    @Environment(\.astraStaticRendering) private var isStatic
    var color: Color
    var period: Double
    var paused: Bool

    var body: some View {
        if isStatic {
            Color.clear
        } else {
            ScanSweepOverlayRepresentable(color: color, period: period, paused: paused)
        }
    }
}

/// Breathing status dot; a plain dot with halo in stills.
struct PulseDotOverlay: View {
    @Environment(\.astraStaticRendering) private var isStatic
    var color: Color
    var period: Double
    var paused: Bool

    var body: some View {
        if isStatic {
            ZStack {
                Circle().fill(color.opacity(0.3))
                Circle().fill(color).scaleEffect(0.44)
            }
        } else {
            PulseDotOverlayRepresentable(color: color, period: period, paused: paused)
        }
    }
}

// MARK: - Shared pause plumbing

@MainActor
private func setLayerPaused(_ paused: Bool, on layer: CALayer) {
    if paused, layer.speed != 0 {
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = now
    } else if !paused, layer.speed == 0 {
        let pausedTime = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        let delta = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        layer.beginTime = delta
    }
}

// MARK: - Radar sweep

/// A rotating sensor-sweep wedge. `period` is seconds per revolution.
struct SweepOverlayRepresentable {
    var color: Color
    var period: Double
    var paused: Bool

    @MainActor fileprivate func apply(to view: SweepLayerView) {
        view.configure(color: PlatformColor(color), period: period)
        view.setPaused(paused)
    }
}

#if canImport(AppKit)
extension SweepOverlayRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> SweepLayerView {
        let view = SweepLayerView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: SweepLayerView, context: Context) {
        apply(to: nsView)
    }
}
#else
extension SweepOverlayRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> SweepLayerView {
        let view = SweepLayerView()
        apply(to: view)
        return view
    }

    func updateUIView(_ uiView: SweepLayerView, context: Context) {
        apply(to: uiView)
    }
}
#endif

final class SweepLayerView: LayerHostView {
    private let wedge = CAShapeLayer()
    private var period: Double = 0

    override func hostLayerDidLoad() {
        hostLayer.addSublayer(wedge)
    }

    func configure(color: PlatformColor, period: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wedge.fillColor = color.cgColor
        CATransaction.commit()
        if self.period != period {
            self.period = period
            installAnimation()
        }
    }

    func setPaused(_ paused: Bool) {
        setLayerPaused(paused, on: hostLayer)
    }

    override func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wedge.frame = bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.44
        let path = CGMutablePath()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: 0.35, endAngle: 0, clockwise: true)
        path.closeSubpath()
        wedge.path = path
        CATransaction.commit()
    }

    override func attachedToWindow() {
        installAnimation()
    }

    private func installAnimation() {
        wedge.removeAnimation(forKey: "sweep")
        guard period > 0 else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0.0
        // Layer y-axes point in opposite directions on the two platforms;
        // flip the sign so the sweep turns the same way on screen.
        spin.toValue = flipsY ? -2.0 * Double.pi : 2.0 * Double.pi
        spin.duration = period
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        wedge.add(spin, forKey: "sweep")
    }
}

// MARK: - Scrolling dashed lines

/// Polylines with a continuously scrolling dash pattern (routes, power
/// conduits). Points are normalized to the unit square with a top-left
/// origin, matching SwiftUI's coordinate space.
struct DashFlowOverlayRepresentable {
    var lines: [[CGPoint]]
    var color: Color
    var lineWidth: CGFloat
    var dash: [CGFloat]
    /// Seconds for the dash pattern to travel one full cycle.
    var cycleDuration: Double
    var paused: Bool

    @MainActor fileprivate func apply(to view: DashFlowLayerView) {
        view.configure(
            lines: lines,
            color: PlatformColor(color),
            lineWidth: lineWidth,
            dash: dash,
            cycleDuration: cycleDuration
        )
        view.setPaused(paused)
    }
}

#if canImport(AppKit)
extension DashFlowOverlayRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> DashFlowLayerView {
        let view = DashFlowLayerView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: DashFlowLayerView, context: Context) {
        apply(to: nsView)
    }
}
#else
extension DashFlowOverlayRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> DashFlowLayerView {
        let view = DashFlowLayerView()
        apply(to: view)
        return view
    }

    func updateUIView(_ uiView: DashFlowLayerView, context: Context) {
        apply(to: uiView)
    }
}
#endif

final class DashFlowLayerView: LayerHostView {
    private let shape = CAShapeLayer()
    private var normalizedLines: [[CGPoint]] = []
    private var cycleDuration: Double = 0
    private var dashSum: CGFloat = 0

    override func hostLayerDidLoad() {
        shape.fillColor = nil
        shape.lineCap = .round
        shape.lineJoin = .round
        hostLayer.addSublayer(shape)
    }

    func configure(lines: [[CGPoint]], color: PlatformColor, lineWidth: CGFloat, dash: [CGFloat], cycleDuration: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.strokeColor = color.cgColor
        shape.lineWidth = lineWidth
        shape.lineDashPattern = dash.map { NSNumber(value: Double($0)) }
        CATransaction.commit()

        let sum = dash.reduce(0, +)
        if normalizedLines != lines {
            normalizedLines = lines
            #if canImport(AppKit)
            needsLayout = true
            #else
            setNeedsLayout()
            #endif
        }
        if self.cycleDuration != cycleDuration || dashSum != sum {
            self.cycleDuration = cycleDuration
            dashSum = sum
            installAnimation()
        }
    }

    func setPaused(_ paused: Bool) {
        setLayerPaused(paused, on: hostLayer)
    }

    override func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        let path = CGMutablePath()
        for line in normalizedLines {
            guard let first = line.first else { continue }
            path.move(to: layerPoint(first))
            for point in line.dropFirst() {
                path.addLine(to: layerPoint(point))
            }
        }
        shape.path = path
        CATransaction.commit()
    }

    override func attachedToWindow() {
        installAnimation()
    }

    private func installAnimation() {
        shape.removeAnimation(forKey: "dashFlow")
        guard cycleDuration > 0, dashSum > 0 else { return }
        let flow = CABasicAnimation(keyPath: "lineDashPhase")
        flow.fromValue = 0
        flow.toValue = dashSum
        flow.duration = cycleDuration
        flow.repeatCount = .infinity
        flow.isRemovedOnCompletion = false
        shape.add(flow, forKey: "dashFlow")
    }
}

// MARK: - Scan sweep

/// A faint luminous band that sweeps across the view every `period`
/// seconds (the sweep itself takes ~1.1 s, then the band rests off-screen).
/// Pure Core Animation: a keyframe animation on the band's position.
struct ScanSweepOverlayRepresentable {
    var color: Color
    var period: Double
    var paused: Bool

    @MainActor fileprivate func apply(to view: ScanSweepLayerView) {
        view.configure(color: PlatformColor(color), period: period)
        view.setPaused(paused)
    }
}

#if canImport(AppKit)
extension ScanSweepOverlayRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> ScanSweepLayerView {
        let view = ScanSweepLayerView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: ScanSweepLayerView, context: Context) {
        apply(to: nsView)
    }
}
#else
extension ScanSweepOverlayRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> ScanSweepLayerView {
        let view = ScanSweepLayerView()
        apply(to: view)
        return view
    }

    func updateUIView(_ uiView: ScanSweepLayerView, context: Context) {
        apply(to: uiView)
    }
}
#endif

final class ScanSweepLayerView: LayerHostView {
    private let band = CAGradientLayer()
    private var period: Double = 0
    private let bandWidth: CGFloat = 72

    override func hostLayerDidLoad() {
        hostLayer.masksToBounds = true
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        band.locations = [0, 0.5, 1]
        band.opacity = 0.22
        hostLayer.addSublayer(band)
    }

    func configure(color: PlatformColor, period: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.colors = [
            color.withAlphaComponent(0).cgColor,
            color.cgColor,
            color.withAlphaComponent(0).cgColor
        ]
        CATransaction.commit()
        if self.period != period {
            self.period = period
            installAnimation()
        }
    }

    func setPaused(_ paused: Bool) {
        setLayerPaused(paused, on: hostLayer)
    }

    override func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.bounds = CGRect(x: 0, y: 0, width: bandWidth, height: bounds.height)
        band.position = CGPoint(x: -bandWidth, y: bounds.midY)
        CATransaction.commit()
        installAnimation()
    }

    override func attachedToWindow() {
        installAnimation()
    }

    private func installAnimation() {
        band.removeAnimation(forKey: "sweep")
        guard period > 0, bounds.width > 0 else { return }
        let travel = CAKeyframeAnimation(keyPath: "position.x")
        let start = -bandWidth
        let end = bounds.width + bandWidth
        travel.values = [start, end, end]
        travel.keyTimes = [0, NSNumber(value: min(0.9, 1.1 / period)), 1]
        travel.duration = period
        travel.repeatCount = .infinity
        travel.isRemovedOnCompletion = false
        travel.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .linear)]
        band.add(travel, forKey: "sweep")
    }
}

// MARK: - Pulse dot

/// A small status dot breathing between full and faint opacity. Used as
/// the live indicator in the console header; the render server does the
/// blinking.
struct PulseDotOverlayRepresentable {
    var color: Color
    var period: Double
    var paused: Bool

    @MainActor fileprivate func apply(to view: PulseDotLayerView) {
        view.configure(color: PlatformColor(color), period: period)
        view.setPaused(paused)
    }
}

#if canImport(AppKit)
extension PulseDotOverlayRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> PulseDotLayerView {
        let view = PulseDotLayerView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: PulseDotLayerView, context: Context) {
        apply(to: nsView)
    }
}
#else
extension PulseDotOverlayRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> PulseDotLayerView {
        let view = PulseDotLayerView()
        apply(to: view)
        return view
    }

    func updateUIView(_ uiView: PulseDotLayerView, context: Context) {
        apply(to: uiView)
    }
}
#endif

final class PulseDotLayerView: LayerHostView {
    private let dot = CAShapeLayer()
    private let halo = CAShapeLayer()
    private var period: Double = 0

    override func hostLayerDidLoad() {
        halo.opacity = 0.35
        hostLayer.addSublayer(halo)
        hostLayer.addSublayer(dot)
    }

    func configure(color: PlatformColor, period: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.fillColor = color.cgColor
        halo.fillColor = color.cgColor
        CATransaction.commit()
        if self.period != period {
            self.period = period
            installAnimation()
        }
    }

    func setPaused(_ paused: Bool) {
        setLayerPaused(paused, on: hostLayer)
    }

    override func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = min(bounds.width, bounds.height)
        let core = CGRect(x: bounds.midX - side * 0.22, y: bounds.midY - side * 0.22, width: side * 0.44, height: side * 0.44)
        dot.frame = bounds
        dot.path = CGPath(ellipseIn: core, transform: nil)
        halo.frame = bounds
        halo.path = CGPath(ellipseIn: bounds.insetBy(dx: side * 0.08, dy: side * 0.08), transform: nil)
        CATransaction.commit()
    }

    override func attachedToWindow() {
        installAnimation()
    }

    private func installAnimation() {
        dot.removeAnimation(forKey: "pulse")
        halo.removeAnimation(forKey: "pulse")
        guard period > 0 else { return }
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 1.0
        breathe.toValue = 0.25
        breathe.duration = period / 2
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.isRemovedOnCompletion = false
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.add(breathe, forKey: "pulse")

        let ring = CABasicAnimation(keyPath: "opacity")
        ring.fromValue = 0.0
        ring.toValue = 0.35
        ring.duration = period / 2
        ring.autoreverses = true
        ring.repeatCount = .infinity
        ring.isRemovedOnCompletion = false
        halo.add(ring, forKey: "pulse")
    }
}
