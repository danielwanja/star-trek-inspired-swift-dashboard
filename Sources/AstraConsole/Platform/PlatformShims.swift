import SwiftUI
import QuartzCore

// The console renders on macOS (AppKit host) and tvOS (UIKit host). The
// SwiftUI layer is shared as-is; only the handful of places that need a
// native view or color go through these aliases.

#if canImport(AppKit)
import AppKit

typealias PlatformView = NSView
typealias PlatformColor = NSColor

#elseif canImport(UIKit)
import UIKit

typealias PlatformView = UIView
typealias PlatformColor = UIColor
#endif

/// A native view whose only job is to host Core Animation layers inside a
/// SwiftUI hierarchy. Subclasses override `layoutLayers()` (called whenever
/// the bounds change) and `attachedToWindow()` (called when the view is
/// (re)attached; CA drops animations from detached layers so this is where
/// repeating animations get reinstalled).
class LayerHostView: PlatformView {
    #if canImport(AppKit)
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        hostLayerDidLoad()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The backing layer. Always present because `wantsLayer` is set in init.
    var hostLayer: CALayer { layer! }

    /// Layer coordinates are bottom-left on AppKit; SwiftUI inputs are top-left.
    var flipsY: Bool { true }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            attachedToWindow()
        }
    }
    #else
    override init(frame: CGRect) {
        super.init(frame: frame)
        hostLayerDidLoad()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var hostLayer: CALayer { layer }

    var flipsY: Bool { false }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutLayers()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            attachedToWindow()
        }
    }
    #endif

    /// Called once the backing layer exists; add sublayers here.
    func hostLayerDidLoad() {}
    func layoutLayers() {}
    func attachedToWindow() {}

    /// Converts a unit-square point with a top-left origin into layer space.
    func layerPoint(_ normalized: CGPoint) -> CGPoint {
        let y = flipsY ? (1 - normalized.y) : normalized.y
        return CGPoint(x: normalized.x * bounds.width, y: y * bounds.height)
    }
}
