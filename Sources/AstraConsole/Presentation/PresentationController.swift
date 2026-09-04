#if os(macOS)
import AppKit
import SwiftUI
import Observation

/// A display the console can be presented on. `id` is the CoreGraphics
/// display number, which is stable while the display stays connected.
struct PresentationScreen: Identifiable, Equatable, Sendable {
    let id: UInt32
    let name: String
    let isMain: Bool
    let size: CGSize

    var label: String {
        "\(name) · \(Int(size.width))×\(Int(size.height))"
    }
}

/// Owns the presentation window: a borderless, full-screen, chromeless
/// console on a chosen display (typically the Apple TV via AirPlay
/// "Use As Separate Display"). macOS offers no API to start AirPlay
/// mirroring itself, so the user picks the Apple TV in Control Center;
/// once the display exists this controller can move there automatically.
@MainActor
@Observable
final class PresentationController {
    private(set) var isPresenting = false
    private(set) var screens: [PresentationScreen] = []
    private(set) var activeScreen: PresentationScreen?

    /// Present as soon as a non-main display appears (the AirPlay case).
    private(set) var autoPresentOnExternalDisplay: Bool

    /// TV-safe margin as a fraction of the display's shorter side.
    var safeMarginFraction: CGFloat = 0.035

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let autoPresentKey = "spaceship-dashboard.present.auto.v1"
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var makeContent: ((PresentationScreen, CGFloat) -> AnyView)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoPresentOnExternalDisplay = defaults.object(forKey: autoPresentKey) as? Bool ?? true
        screens = Self.currentScreens()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensChanged()
            }
        }
    }

    /// The App injects the root view (with its environment) here so this
    /// controller does not need to know about stores. The closure receives
    /// the TV-safe inset to apply inside the console background.
    func configure(content: @escaping (_ screen: PresentationScreen, _ inset: CGFloat) -> AnyView) {
        makeContent = content
    }

    func setAutoPresent(_ enabled: Bool) {
        autoPresentOnExternalDisplay = enabled
        defaults.set(enabled, forKey: autoPresentKey)
    }

    var externalScreens: [PresentationScreen] {
        screens.filter { !$0.isMain }
    }

    /// External display if there is one, otherwise the main display.
    var preferredScreen: PresentationScreen? {
        externalScreens.first ?? screens.first
    }

    func toggle() {
        if isPresenting {
            stop()
        } else if let screen = preferredScreen {
            present(on: screen)
        }
    }

    func present(on screen: PresentationScreen) {
        guard let makeContent, let nsScreen = Self.nsScreen(for: screen.id) else { return }
        if window == nil {
            window = Self.makeWindow()
        }
        guard let window else { return }

        let inset = min(nsScreen.frame.width, nsScreen.frame.height) * safeMarginFraction
        let hosting = PresentationHostingView(rootView: makeContent(screen, inset))
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.setFrame(nsScreen.frame, display: true)
        window.orderFrontRegardless()

        activeScreen = screen
        isPresenting = true
    }

    func stop() {
        guard isPresenting else { return }
        (window?.contentView as? CursorHiding)?.restoreCursor()
        window?.orderOut(nil)
        window?.contentView = nil
        activeScreen = nil
        isPresenting = false
    }

    // MARK: Display changes

    private func screensChanged() {
        let previous = screens
        screens = Self.currentScreens()

        if isPresenting {
            guard let active = activeScreen else { return }
            if !screens.contains(where: { $0.id == active.id }) {
                // The display went away (AirPlay stopped): fall back rather
                // than leave an orphaned full-screen window on the main display.
                stop()
            } else if active.isMain, let external = externalScreens.first {
                present(on: external)
            } else if let nsScreen = Self.nsScreen(for: active.id) {
                window?.setFrame(nsScreen.frame, display: true)
            }
        } else if autoPresentOnExternalDisplay {
            let previousIDs = Set(previous.map(\.id))
            if let appeared = externalScreens.first(where: { !previousIDs.contains($0.id) }) {
                present(on: appeared)
            }
        }
    }

    // MARK: Screens

    private static func currentScreens() -> [PresentationScreen] {
        NSScreen.screens.compactMap { screen in
            guard let id = displayID(of: screen) else { return nil }
            return PresentationScreen(
                id: id,
                name: screen.localizedName,
                isMain: screen == NSScreen.screens.first,
                size: screen.frame.size
            )
        }
    }

    private static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func nsScreen(for id: UInt32) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Above the menu bar on that display, on every Space of it.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.isExcludedFromWindowsMenu = true
        return window
    }
}

// MARK: - Cursor hiding

@MainActor
private protocol CursorHiding: AnyObject {
    func restoreCursor()
}

/// Hosting view that hides the pointer while it is over the presentation
/// display. Hide/unhide are balanced so the pointer never gets stuck.
private final class PresentationHostingView<Content: View>: NSHostingView<Content>, CursorHiding {
    private var cursorHidden = false
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if !cursorHidden {
            NSCursor.hide()
            cursorHidden = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        restoreCursor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            restoreCursor()
        }
    }

    func restoreCursor() {
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
    }
}

// MARK: - Remote panel (Mac window while presenting)

/// Replaces the dashboard canvas in the Mac window while the console is on
/// an external display, so widgets are rendered exactly once.
struct PresentationRemotePanel: View {
    @Environment(DashboardStore.self) private var store
    @Environment(PresentationController.self) private var presentation
    @Environment(ConsoleSyncPublisher.self) private var sync
    @Environment(\.astraTheme) private var theme
    var dashboard: DashboardLayout

    var body: some View {
        AstraCFrame(
            accent: dashboard.accentRole,
            secondary: dashboard.secondaryRole,
            topLabel: "REMOTE · \(dashboard.name)",
            bottomLabel: dashboard.deckCode,
            railWidth: 150
        ) {
            VStack(alignment: .leading, spacing: theme.metrics.gap) {
                HStack(spacing: theme.metrics.fineGap) {
                    HeaderChip(title: "CASTING", color: .cyan)
                    HeaderChip(title: presentation.activeScreen?.name.uppercased() ?? "DISPLAY", color: .gold)
                    HeaderChip(title: sync.isLinked ? "TV LINK \(sync.receiverCount)" : sync.status, color: sync.isLinked ? .mint : .violet)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(dashboard.name.uppercased())
                        .font(theme.typography.display(size: 34))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Text("CONSOLE IS ON THE EXTERNAL DISPLAY · THIS WINDOW IS THE REMOTE")
                        .font(theme.typography.data(size: 14))
                        .foregroundStyle(theme.color(.gold))
                    Text("Pick dashboards and themes here; widgets render once, on the display. Use EDIT to change layouts while casting.")
                        .font(theme.typography.systemData(size: 12, weight: .semibold))
                        .foregroundStyle(theme.palette.mutedText)
                }

                HStack(spacing: theme.metrics.fineGap) {
                    Button {
                        presentation.stop()
                    } label: {
                        Text("STOP CAST")
                            .frame(width: 110, height: 34)
                    }
                    .buttonStyle(ConsoleTextButtonStyle(color: .rose))

                    ForEach(presentation.screens) { screen in
                        Button {
                            presentation.present(on: screen)
                        } label: {
                            Text(screen.label.uppercased())
                                .frame(height: 34)
                                .padding(.horizontal, 14)
                        }
                        .buttonStyle(ConsoleTextButtonStyle(color: screen.id == presentation.activeScreen?.id ? .gold : .violet))
                    }
                    Spacer()
                }

                Spacer()
            }
            .padding(theme.metrics.gap)
        }
    }
}
#endif
