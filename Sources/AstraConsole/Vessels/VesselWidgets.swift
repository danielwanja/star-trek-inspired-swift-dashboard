import SwiftUI

// MARK: - Vessel Schematic

/// One vessel at a time: a rotating hull with spec column and callouts.
/// Cycles through the fleet on its own; on the Mac the hull can be dragged
/// (rotate), pinched (zoom) and stepped with PREV/NEXT.
struct VesselSchematicWidget: View {
    @Environment(\.astraTheme) private var theme
    @Environment(\.astraAnimationsPaused) private var animationsPaused

    var widgetID: UUID
    var size: WidgetSize

    @State private var manualIndex: Int?
    @State private var style: VesselRenderStyle
    @State private var isSpinning = true
    @State private var dragYaw: Double = 0
    @State private var dragPitch: Double = 0
    @State private var zoom: Double = 1
    @State private var dragStart: (yaw: Double, pitch: Double)?
    @State private var zoomStart: Double?

    /// Seconds each vessel stays on screen while cycling automatically.
    static let dwell: TimeInterval = 28

    init(widgetID: UUID, size: WidgetSize) {
        self.widgetID = widgetID
        self.size = size
        _style = State(initialValue: VesselWidgetPreferences.style(for: widgetID))
    }

    private var catalog: VesselCatalog { .shared }
    private var showsSpecColumn: Bool { size == .wide || size == .hero || size == .grand }
    private var showsCallouts: Bool { size != .compact && size != .tall }

    var body: some View {
        let vessels = catalog.vessels
        if vessels.isEmpty {
            VesselEmptyState(issues: catalog.issues, isLoading: catalog.isLoading)
        } else {
            ConsoleTimelineView(frameRate: 1) { date in
                let index = currentIndex(count: vessels.count, date: date)
                let vessel = vessels[index]
                content(for: vessel, index: index, count: vessels.count)
            }
        }
    }

    private func currentIndex(count: Int, date: Date) -> Int {
        if let manualIndex { return ((manualIndex % count) + count) % count }
        return Int(date.timeIntervalSinceReferenceDate / Self.dwell) % count
    }

    @ViewBuilder
    private func content(for vessel: Vessel, index: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VesselTitleRow(vessel: vessel, index: index, count: count, compact: size == .compact)

            HStack(alignment: .top, spacing: 12) {
                hull(for: vessel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsSpecColumn {
                    VesselSpecColumn(vessel: vessel)
                        .frame(width: 168)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if os(macOS)
            controls(count: count, index: index)
            #endif
        }
        .frame(maxWidth: .infinity, minHeight: size == .compact ? 110 : 230, maxHeight: .infinity, alignment: .topLeading)
    }

    private func hull(for vessel: Vessel) -> some View {
        AnimationPhaseView(speed: 0.035, frameRate: VesselWidgetPreferences.hullFrameInterval) { phase in
            Canvas { context, canvasSize in
                var pose = VesselPose.showcase
                pose.yaw += dragYaw + (isSpinning ? phase * .pi * 2 : 0)
                pose.pitch = (VesselPose.showcase.pitch + dragPitch).clamped(to: -1.25...1.25)
                pose.zoom = zoom * (showsCallouts ? 0.86 : 0.96)
                let renderer = VesselRenderer(
                    mesh: vessel.mesh,
                    pose: pose,
                    style: style,
                    accent: theme.color(vessel.accent),
                    theme: theme
                )
                let rect = CGRect(origin: .zero, size: canvasSize)
                let projection = renderer.draw(in: rect, context: &context)
                if showsCallouts {
                    renderer.drawCallouts(vessel.manifest.callouts, projection: projection, in: rect.insetBy(dx: 4, dy: 4), context: &context)
                }
            }
        }
        .drawingGroup()
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Text(style.title)
                .font(theme.typography.data(size: 11))
                .foregroundStyle(theme.color(vessel.accent).opacity(0.8))
                .padding(6)
        }
        #if os(macOS)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .simultaneousGesture(magnifyGesture)
        #endif
    }

    #if os(macOS)
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStart == nil { dragStart = (dragYaw, dragPitch) }
                guard let dragStart else { return }
                dragYaw = dragStart.yaw + value.translation.width * 0.012
                dragPitch = dragStart.pitch - value.translation.height * 0.010
            }
            .onEnded { _ in dragStart = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomStart == nil { zoomStart = zoom }
                zoom = ((zoomStart ?? 1) * value.magnification).clamped(to: 0.5...2.5)
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func controls(count: Int, index: Int) -> some View {
        HStack(spacing: 6) {
            Button("PREV") { manualIndex = index - 1 }
                .buttonStyle(ConsoleTextButtonStyle(color: .apricot, compact: true))
                .frame(width: 52, height: 24)
            Button("NEXT") { manualIndex = index + 1 }
                .buttonStyle(ConsoleTextButtonStyle(color: .apricot, compact: true))
                .frame(width: 52, height: 24)
            Button(manualIndex == nil ? "AUTO ●" : "AUTO") { manualIndex = nil }
                .buttonStyle(ConsoleTextButtonStyle(color: manualIndex == nil ? .mint : .violet, compact: true))
                .frame(width: 58, height: 24)
                .help("Cycle through the fleet automatically")

            Spacer(minLength: 4)

            Button(style.title) {
                style = style.next
                VesselWidgetPreferences.setStyle(style, for: widgetID)
            }
            .buttonStyle(ConsoleTextButtonStyle(color: .cyan, compact: true))
            .frame(width: 92, height: 24)
            .help("Wireframe, shaded or hidden-line")

            Button(isSpinning ? "SPIN ●" : "SPIN") { isSpinning.toggle() }
                .buttonStyle(ConsoleTextButtonStyle(color: isSpinning ? .mint : .violet, compact: true))
                .frame(width: 56, height: 24)
                .help("Continuous rotation; drag the hull to orbit, pinch to zoom")

            Button("RESET") {
                dragYaw = 0
                dragPitch = 0
                zoom = 1
            }
            .buttonStyle(ConsoleTextButtonStyle(color: .gold, compact: true))
            .frame(width: 56, height: 24)
        }
    }
    #endif
}

/// Name, designation and culture/era chips above the hull.
struct VesselTitleRow: View {
    @Environment(\.astraTheme) private var theme
    var vessel: Vessel
    var index: Int
    var count: Int
    var compact: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(format: "%02d", index + 1))
                .font(theme.typography.data(size: 13))
                .foregroundStyle(theme.color(vessel.accent))
            VStack(alignment: .leading, spacing: 1) {
                Text(vessel.name.uppercased())
                    .font(theme.typography.display(size: compact ? 16 : 20))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !vessel.manifest.designation.isEmpty {
                    Text(vessel.manifest.designation.uppercased())
                        .font(theme.typography.data(size: 12))
                        .foregroundStyle(theme.palette.mutedText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            Spacer(minLength: 6)
            if !compact {
                HeaderChip(title: vessel.culture.uppercased(), color: vessel.accent)
                if let era = vessel.manifest.era {
                    HeaderChip(title: era.uppercased(), color: .violet)
                }
            }
            Text(String(format: "%02d / %02d", index + 1, count))
                .font(theme.typography.data(size: 12))
                .foregroundStyle(theme.palette.mutedText.opacity(0.8))
        }
    }
}

/// Spec lines from the manifest, with the mesh's own numbers at the bottom.
struct VesselSpecColumn: View {
    @Environment(\.astraTheme) private var theme
    var vessel: Vessel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(vessel.manifest.stats.prefix(7).enumerated()), id: \.offset) { _, stat in
                specLine(stat.label, stat.value)
            }
            if vessel.manifest.stats.isEmpty {
                specLine("Class", vessel.manifest.vesselClass ?? "Unclassified")
                specLine("Registry", vessel.manifest.registry ?? "None")
            }
            Spacer(minLength: 0)
            Rectangle()
                .fill(theme.color(vessel.accent).opacity(0.35))
                .frame(height: 1)
            specLine("Mesh", "\(vessel.mesh.vertices.count) V · \(vessel.mesh.edgeCount) E")
            if let notes = vessel.manifest.notes {
                Text(notes)
                    .font(theme.typography.systemData(size: 11, weight: .medium))
                    .foregroundStyle(theme.palette.mutedText.opacity(0.8))
                    .lineLimit(3)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func specLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(theme.typography.data(size: 11))
                .foregroundStyle(theme.palette.mutedText.opacity(0.8))
            Text(value)
                .font(theme.typography.data(size: 13))
                .foregroundStyle(theme.palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Shown when no vessel loaded at all.
struct VesselEmptyState: View {
    @Environment(\.astraTheme) private var theme
    var issues: [String]
    var isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isLoading ? "SCANNING SHIPYARD…" : "NO VESSELS ON FILE")
                .font(theme.typography.display(size: 16))
                .foregroundStyle(theme.palette.text)
            #if os(macOS)
            if let folder = VesselCatalog.userDirectory {
                Text("Drop a folder with vessel.json + an OBJ into\n\(folder.path)")
                    .font(theme.typography.systemData(size: 11, weight: .medium))
                    .foregroundStyle(theme.palette.mutedText)
            }
            #else
            Text("Waiting for a Mac to sync its fleet.")
                .font(theme.typography.systemData(size: 12, weight: .medium))
                .foregroundStyle(theme.palette.mutedText)
            #endif
            ForEach(issues.prefix(3), id: \.self) { issue in
                Text(issue)
                    .font(theme.typography.systemData(size: 11, weight: .medium))
                    .foregroundStyle(theme.color(.rose))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Fleet Registry

/// A paged grid of small rotating hulls, one culture at a time.
struct FleetRegistryWidget: View {
    @Environment(\.astraTheme) private var theme
    var size: WidgetSize

    /// Seconds per page.
    static let pageDwell: TimeInterval = 14

    private var catalog: VesselCatalog { .shared }

    var body: some View {
        let fleets = catalog.fleets
        if fleets.isEmpty {
            VesselEmptyState(issues: catalog.issues, isLoading: catalog.isLoading)
        } else {
            ConsoleTimelineView(frameRate: VesselWidgetPreferences.gridFrameInterval) { date in
                Canvas { context, canvasSize in
                    draw(fleets: fleets, date: date, size: canvasSize, context: &context)
                }
            }
            .drawingGroup()
            .frame(maxWidth: .infinity, minHeight: size == .compact ? 120 : size == .grand ? 560 : 240, maxHeight: .infinity)
        }
    }

    static let minCellWidth: CGFloat = 118
    static let minCellHeight: CGFloat = 100

    /// Columns × rows holding `count` cells inside `size`, preferring the
    /// arrangement with the largest (roughly square) cells.
    static func grid(for count: Int, in size: CGSize, maxColumns: Int, maxRows: Int) -> (columns: Int, rows: Int) {
        guard count > 1 else { return (1, 1) }
        var best = (columns: maxColumns, rows: maxRows)
        var bestScore: CGFloat = -1
        for columns in 1...maxColumns {
            let rows = (count + columns - 1) / columns
            guard rows <= maxRows else { continue }
            let cellWidth = size.width / CGFloat(columns)
            let cellHeight = size.height / CGFloat(rows)
            // Hulls are wider than tall; favour cells around 4:3.
            let score = min(cellWidth, cellHeight * 1.33)
            if score > bestScore {
                bestScore = score
                best = (columns, rows)
            }
        }
        return best
    }

    private struct Page {
        var culture: String
        var vessels: [Vessel]
        var number: Int
        var total: Int
    }

    /// Pages are per culture, split further when a culture has more ships
    /// than the grid holds.
    private func pages(fleets: [(culture: String, vessels: [Vessel])], perPage: Int) -> [Page] {
        // When the whole fleet fits, show it as one roster; cultures only
        // become pages once there are more ships than cells.
        let all = fleets.flatMap(\.vessels)
        if all.count <= perPage {
            let title = fleets.count == 1 ? fleets[0].culture : "All cultures"
            return [Page(culture: title, vessels: all, number: 1, total: 1)]
        }
        var pages: [Page] = []
        for fleet in fleets {
            let chunks = stride(from: 0, to: fleet.vessels.count, by: perPage).map { start in
                Array(fleet.vessels[start..<min(start + perPage, fleet.vessels.count)])
            }
            for (index, chunk) in chunks.enumerated() {
                pages.append(Page(culture: fleet.culture, vessels: chunk, number: index + 1, total: chunks.count))
            }
        }
        return pages
    }

    private func draw(fleets: [(culture: String, vessels: [Vessel])], date: Date, size canvasSize: CGSize, context: inout GraphicsContext) {
        let footer: CGFloat = 26
        let gridRect = CGRect(x: 0, y: 0, width: canvasSize.width, height: max(60, canvasSize.height - footer))
        // Capacity at the smallest legible cell; a culture larger than this
        // spills onto a second page.
        let maxColumns = max(1, Int(gridRect.width / Self.minCellWidth))
        let maxRows = max(1, Int(gridRect.height / Self.minCellHeight))
        let pages = pages(fleets: fleets, perPage: maxColumns * maxRows)
        guard !pages.isEmpty else { return }
        let time = date.timeIntervalSinceReferenceDate
        let page = pages[Int(time / Self.pageDwell) % pages.count]

        // Then give this page's ships the biggest cells that still fit them
        // all, so a grand card shows a whole culture at once.
        let (columns, rows) = Self.grid(for: page.vessels.count, in: gridRect.size, maxColumns: maxColumns, maxRows: maxRows)
        let cellWidth = gridRect.width / CGFloat(columns)
        let cellHeight = gridRect.height / CGFloat(rows)
        let spin = time * 0.45 * theme.animationIntensity

        for (index, vessel) in page.vessels.enumerated() {
            let column = index % columns
            let row = index / columns
            let cell = CGRect(
                x: gridRect.minX + CGFloat(column) * cellWidth,
                y: gridRect.minY + CGFloat(row) * cellHeight,
                width: cellWidth,
                height: cellHeight
            ).insetBy(dx: 4, dy: 4)
            let accent = theme.color(vessel.accent)

            context.stroke(
                Path(roundedRect: cell, cornerRadius: 6),
                with: .color(accent.opacity(0.22)),
                lineWidth: 1
            )
            context.fill(
                Path(roundedRect: CGRect(x: cell.minX + 8, y: cell.minY, width: 26, height: 3), cornerRadius: 1.5),
                with: .color(accent)
            )

            let captionHeight: CGFloat = 30
            let hullRect = CGRect(x: cell.minX, y: cell.minY + 4, width: cell.width, height: cell.height - captionHeight - 4)
            var pose = VesselPose.showcase
            pose.yaw += spin + Double(index) * 0.9
            pose.zoom = 0.9
            let renderer = VesselRenderer(
                mesh: vessel.mesh,
                pose: pose,
                style: .wireframe,
                accent: accent,
                theme: theme,
                glow: false,
                reticle: false
            )
            renderer.draw(in: hullRect, context: &context)

            let name = context.resolve(
                Text(vessel.name.uppercased())
                    .font(theme.typography.data(size: 11))
                    .foregroundStyle(theme.palette.text)
            )
            let designation = context.resolve(
                Text(vessel.manifest.designation.uppercased())
                    .font(theme.typography.systemData(size: 10, weight: .semibold))
                    .foregroundStyle(theme.palette.mutedText.opacity(0.8))
            )
            let captionWidth = cell.width - 16
            context.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: cell.minX + 8, y: cell.maxY - captionHeight, width: captionWidth, height: captionHeight)))
                layer.draw(name, at: CGPoint(x: cell.minX + 8, y: cell.maxY - captionHeight + 2), anchor: .topLeading)
                layer.draw(designation, at: CGPoint(x: cell.minX + 8, y: cell.maxY - 4), anchor: .bottomLeading)
            }
        }

        // Footer: culture chip and page counter.
        let footerRect = CGRect(x: 0, y: canvasSize.height - footer + 4, width: canvasSize.width, height: footer - 4)
        let chipAccent = page.vessels.count == fleets.reduce(0, { $0 + $1.vessels.count }) && fleets.count > 1 ? AstraColorRole.apricot : (page.vessels.first?.accent ?? .apricot)
        let chipWidth = min(180, max(90, CGFloat(page.culture.count) * 9 + 30))
        context.drawChip(page.culture.uppercased(), in: CGRect(x: footerRect.minX, y: footerRect.minY, width: chipWidth, height: footerRect.height), theme: theme, color: chipAccent, fontSize: 11)
        let pageIndex = pages.firstIndex(where: { $0.culture == page.culture && $0.number == page.number }) ?? 0
        let counter = context.resolve(
            Text(String(format: "PAGE %02d / %02d  ·  %d VESSELS", pageIndex + 1, pages.count, fleets.reduce(0) { $0 + $1.vessels.count }))
                .font(theme.typography.data(size: 11))
                .foregroundStyle(theme.palette.mutedText.opacity(0.85))
        )
        context.draw(counter, at: CGPoint(x: footerRect.maxX, y: footerRect.midY), anchor: .trailing)
    }
}

// MARK: - Preferences

enum VesselWidgetPreferences {
    /// Hull redraw interval. The Apple TV renders every widget at once on a
    /// smaller GPU budget, so it ticks slower.
    static var hullFrameInterval: TimeInterval {
        #if os(tvOS)
        return 1.0 / 15.0
        #else
        return 1.0 / 24.0
        #endif
    }

    static var gridFrameInterval: TimeInterval {
        #if os(tvOS)
        return 1.0 / 10.0
        #else
        return 1.0 / 15.0
        #endif
    }

    private static func styleKey(_ id: UUID) -> String {
        "spaceship-dashboard.vessel.style.\(id.uuidString)"
    }

    static func style(for id: UUID) -> VesselRenderStyle {
        guard let raw = UserDefaults.standard.string(forKey: styleKey(id)),
              let style = VesselRenderStyle(rawValue: raw) else { return .wireframe }
        return style
    }

    static func setStyle(_ style: VesselRenderStyle, for id: UUID) {
        UserDefaults.standard.set(style.rawValue, forKey: styleKey(id))
    }
}
