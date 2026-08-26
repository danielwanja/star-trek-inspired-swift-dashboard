import SwiftUI
import AppKit
import QuartzCore

// Ambient loops (radar sweep, scrolling dashes) are rendered by Core
// Animation. The animations run on the render server, so once installed
// they cost zero app CPU per frame — no timeline ticks, no view diffing,
// no Canvas rasterization.

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
struct SweepOverlay: NSViewRepresentable {
    var color: Color
    var period: Double
    var paused: Bool

    func makeNSView(context: Context) -> SweepLayerView {
        let view = SweepLayerView()
        view.configure(color: NSColor(color), period: period)
        view.setPaused(paused)
        return view
    }

    func updateNSView(_ nsView: SweepLayerView, context: Context) {
        nsView.configure(color: NSColor(color), period: period)
        nsView.setPaused(paused)
    }
}

final class SweepLayerView: NSView {
    private let wedge = CAShapeLayer()
    private var period: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(wedge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(color: NSColor, period: Double) {
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
        guard let layer else { return }
        setLayerPaused(paused, on: layer)
    }

    override func layout() {
        super.layout()
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // SwiftUI can detach and reattach the backing view; CA drops
        // animations from detached layers, so reinstall on attach.
        if window != nil {
            installAnimation()
        }
    }

    private func installAnimation() {
        wedge.removeAnimation(forKey: "sweep")
        guard period > 0 else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0.0
        spin.toValue = -2.0 * Double.pi
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
struct DashFlowOverlay: NSViewRepresentable {
    var lines: [[CGPoint]]
    var color: Color
    var lineWidth: CGFloat
    var dash: [CGFloat]
    /// Seconds for the dash pattern to travel one full cycle.
    var cycleDuration: Double
    var paused: Bool

    func makeNSView(context: Context) -> DashFlowLayerView {
        let view = DashFlowLayerView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: DashFlowLayerView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: DashFlowLayerView) {
        view.configure(
            lines: lines,
            color: NSColor(color),
            lineWidth: lineWidth,
            dash: dash,
            cycleDuration: cycleDuration
        )
        view.setPaused(paused)
    }
}

final class DashFlowLayerView: NSView {
    private let shape = CAShapeLayer()
    private var normalizedLines: [[CGPoint]] = []
    private var cycleDuration: Double = 0
    private var dashSum: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        shape.fillColor = nil
        shape.lineCap = .round
        shape.lineJoin = .round
        layer?.addSublayer(shape)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(lines: [[CGPoint]], color: NSColor, lineWidth: CGFloat, dash: [CGFloat], cycleDuration: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.strokeColor = color.cgColor
        shape.lineWidth = lineWidth
        shape.lineDashPattern = dash.map { NSNumber(value: Double($0)) }
        CATransaction.commit()

        let sum = dash.reduce(0, +)
        if normalizedLines != lines {
            normalizedLines = lines
            needsLayout = true
        }
        if self.cycleDuration != cycleDuration || dashSum != sum {
            self.cycleDuration = cycleDuration
            dashSum = sum
            installAnimation()
        }
    }

    func setPaused(_ paused: Bool) {
        guard let layer else { return }
        setLayerPaused(paused, on: layer)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        let path = CGMutablePath()
        for line in normalizedLines {
            guard let first = line.first else { continue }
            path.move(to: point(first))
            for point in line.dropFirst() {
                path.addLine(to: self.point(point))
            }
        }
        shape.path = path
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installAnimation()
        }
    }

    private func point(_ normalized: CGPoint) -> CGPoint {
        // Flip y: the layer's origin is bottom-left, inputs are top-left.
        CGPoint(x: normalized.x * bounds.width, y: (1 - normalized.y) * bounds.height)
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
