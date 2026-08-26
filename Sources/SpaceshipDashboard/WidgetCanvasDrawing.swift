import SwiftUI

/// One metric row (label, value, segmented progress bar) drawn directly
/// into a `GraphicsContext`. Animated widgets draw these instead of
/// composing `MetricLine`/`SegmentedBar` views so a timeline tick
/// invalidates a single Canvas draw, not a tree of dozens of views.
struct CanvasMetricRow {
    var label: String
    var value: String
    var progress: Double
    var color: AstraColorRole
}

enum MetricRowLayout {
    static let rowHeight: CGFloat = 33
    static let spacing: CGFloat = 11
    static let barHeight: CGFloat = 10

    static func height(rows: Int, rowHeight: CGFloat = rowHeight, spacing: CGFloat = spacing) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * rowHeight + CGFloat(rows - 1) * spacing
    }
}

extension GraphicsContext {
    func drawSegmentedBar(
        in rect: CGRect,
        progress: Double,
        theme: AstraConsoleTheme,
        color: AstraColorRole,
        segments: Int = 18
    ) {
        let gap: CGFloat = 3
        let width = (rect.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
        guard width > 0 else { return }
        let onColor = theme.color(color)
        let offColor = theme.palette.text.opacity(0.09)
        let clamped = progress.clamped(to: 0...1)
        for index in 0..<segments {
            let x = rect.minX + CGFloat(index) * (width + gap)
            let cell = CGRect(x: x, y: rect.minY, width: width, height: rect.height)
            let lit = Double(index) / Double(max(1, segments - 1)) <= clamped
            fill(Path(roundedRect: cell, cornerRadius: 2), with: .color(lit ? onColor : offColor))
        }
    }

    func drawChip(
        _ text: String,
        in rect: CGRect,
        theme: AstraConsoleTheme,
        color: AstraColorRole,
        fontSize: CGFloat = 12
    ) {
        let shape = AstraPartialRoundedRectangle(leadingRadius: 12, trailingRadius: 4)
        fill(shape.path(in: rect), with: .color(theme.color(color)))
        let resolved = resolve(
            Text(text)
                .font(theme.typography.data(size: fontSize))
                .foregroundStyle(Color.black)
        )
        draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }

    func drawMetricRow(
        _ row: CanvasMetricRow,
        in rect: CGRect,
        theme: AstraConsoleTheme,
        segments: Int = 18
    ) {
        let label = resolve(
            Text(row.label.uppercased())
                .font(theme.typography.data(size: 13))
                .foregroundStyle(theme.palette.mutedText.opacity(0.82))
        )
        draw(label, at: CGPoint(x: rect.minX, y: rect.minY), anchor: .topLeading)

        let value = resolve(
            Text(row.value)
                .font(theme.typography.data(size: 14))
                .foregroundStyle(theme.palette.text)
        )
        draw(value, at: CGPoint(x: rect.maxX, y: rect.minY), anchor: .topTrailing)

        let barRect = CGRect(
            x: rect.minX,
            y: rect.maxY - MetricRowLayout.barHeight,
            width: rect.width,
            height: MetricRowLayout.barHeight
        )
        drawSegmentedBar(in: barRect, progress: row.progress, theme: theme, color: row.color, segments: segments)
    }

    func drawMetricRows(
        _ rows: [CanvasMetricRow],
        in rect: CGRect,
        theme: AstraConsoleTheme,
        segments: Int = 18
    ) {
        for (index, row) in rows.enumerated() {
            let top = rect.minY + CGFloat(index) * (MetricRowLayout.rowHeight + MetricRowLayout.spacing)
            let rowRect = CGRect(x: rect.minX, y: top, width: rect.width, height: MetricRowLayout.rowHeight)
            drawMetricRow(row, in: rowRect, theme: theme, segments: segments)
        }
    }
}
