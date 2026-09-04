import SwiftUI
import QuartzCore

// Ambient loops (radar sweep, scrolling dashes) are rendered by Core
// Animation. The animations run on the render server, so once installed
// they cost zero app CPU per frame — no timeline ticks, no view diffing,
// no Canvas rasterization. The host view is AppKit on macOS and UIKit on
// tvOS (see PlatformShims); the layer code is identical on both.

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
struct SweepOverlay {
    var color: Color
    var period: Double
    var paused: Bool

    @MainActor fileprivate func apply(to view: SweepLayerView) {
        view.configure(color: PlatformColor(color), period: period)
        view.setPaused(paused)
    }
}

#if canImport(AppKit)
extension SweepOverlay: NSViewRepresentable {
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
extension SweepOverlay: UIViewRepresentable {
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
struct DashFlowOverlay {
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
extension DashFlowOverlay: NSViewRepresentable {
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
extension DashFlowOverlay: UIViewRepresentable {
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
