#if os(macOS)
import AppKit
import SwiftUI

/// Renders every widget (and one composite per widget group) to PNG files
/// for the documentation, using live data from the running app. Invoked
/// from the Gallery menu; always renders in the Horizon HUD theme so the
/// docs stay consistent whatever theme is active.
///
/// `ImageRenderer` cannot draw AppKit-hosted layers, so the export sets
/// `astraStaticRendering` and the Core Animation overlays render static
/// SwiftUI equivalents (a fixed sweep wedge, static dashed routes).
@MainActor
enum WidgetGalleryExporter {
    /// Virtual grid width the cards are laid out in (four columns).
    static let gridWidth: CGFloat = 1200
    /// Width of the group composites (a full presentation canvas).
    static let compositeWidth: CGFloat = 1500

    struct Summary {
        var widgets: Int
        var groups: Int
        var directory: URL
    }

    /// `demoData` swaps the developer, connectivity and weather categories
    /// for `GalleryDemoData` so the stills never show the machine's public
    /// IP, ISP, open services, repositories or home city. Host telemetry
    /// (CPU, memory, disk) stays live: it identifies nothing.
    static func export(to directory: URL, store: DashboardStore, liveData: LiveDataHub, theme: AstraConsoleTheme = .horizon, demoData: Bool = true) throws -> Summary {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let hub: LiveDataHub
        if demoData {
            let demo = LiveDataHub(source: .remote)
            demo.applyRemote(LiveDataSnapshot(now: Date(), telemetry: liveData.telemetry))
            GalleryDemoData.apply(to: demo)
            hub = demo
        } else {
            hub = liveData
        }

        var widgets = 0
        for kind in DashboardWidgetKind.allCases {
            let widget = DashboardWidget(kind: kind)
            let width = cardWidth(columns: widget.size.columns, gap: theme.metrics.gap)
            let card = ZStack {
                theme.palette.screen
                DashboardWidgetCard(
                    widget: widget,
                    isBuilderVisible: false,
                    onResizeWidget: { _, _ in },
                    onRemoveWidget: { _ in }
                )
                .frame(width: width)
                .padding(14)
            }
            try render(decorate(card, store: store, liveData: hub, theme: theme), to: directory.appendingPathComponent("\(kind.rawValue).png"))
            widgets += 1
        }

        var groups = 0
        for group in WidgetGroup.allCases {
            let kinds = DashboardWidgetKind.allCases.filter { $0.group == group }
            let layout = DashboardLayout(
                name: group.title,
                subtitle: "\(group.shortTitle) widget group",
                widgets: kinds.map { DashboardWidget(kind: $0) }
            )
            let composite = ZStack {
                ConsoleBackground()
                DashboardCanvas(
                    dashboard: layout,
                    isBuilderVisible: false,
                    onResizeWidget: { _, _ in },
                    onRemoveWidget: { _ in },
                    presentation: true
                )
                .padding(theme.metrics.outerPadding)
            }
            .frame(width: compositeWidth)
            // Composites are large; 1x keeps the docs folder small.
            try render(decorate(composite, store: store, liveData: hub, theme: theme), to: directory.appendingPathComponent("group-\(group.rawValue).png"), scale: 1)
            groups += 1
        }

        return Summary(widgets: widgets, groups: groups, directory: directory)
    }

    private static func cardWidth(columns: Int, gap: CGFloat) -> CGFloat {
        let column = (gridWidth - gap * CGFloat(DashboardCanvas.columns - 1)) / CGFloat(DashboardCanvas.columns)
        let span = min(columns, DashboardCanvas.columns)
        return column * CGFloat(span) + gap * CGFloat(span - 1)
    }

    private static func decorate<Content: View>(_ content: Content, store: DashboardStore, liveData: LiveDataHub, theme: AstraConsoleTheme) -> some View {
        content
            .environment(store)
            .environment(liveData)
            .environment(\.astraTheme, theme)
            .environment(\.astraAnimationsPaused, true)
            .environment(\.astraStaticRendering, true)
            .foregroundStyle(theme.palette.text)
            .preferredColorScheme(.dark)
    }

    private static func render<Content: View>(_ view: Content, to url: URL, scale: CGFloat = 2) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url, options: .atomic)
    }

    /// Menu entry point: asks for a folder (defaulting to
    /// docs/images/widgets under the current directory, i.e. the repo when
    /// launched with `swift run`), exports, then reveals the folder.
    static func exportInteractively(store: DashboardStore, liveData: LiveDataHub, demoData: Bool = true) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Here"
        panel.message = demoData
            ? "Choose the folder for the widget gallery PNGs (Horizon HUD theme, fictional DEV/LINK/WX data)"
            : "Choose the folder for the widget gallery PNGs (Horizon HUD theme, LIVE data — contains your IP, services and locations)"

        let suggested = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/images/widgets", isDirectory: true)
        try? FileManager.default.createDirectory(at: suggested, withIntermediateDirectories: true)
        panel.directoryURL = suggested

        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            let summary = try export(to: directory, store: store, liveData: liveData, demoData: demoData)
            NSWorkspace.shared.activateFileViewerSelecting([summary.directory])
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
#endif
