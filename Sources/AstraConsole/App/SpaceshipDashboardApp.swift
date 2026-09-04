#if os(macOS)
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            if NSApp.windows.isEmpty {
                NSApp.sendAction(#selector(NSApplication.newWindowForTab(_:)), to: nil, from: nil)
            }
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

/// The macOS app. Entry point is `Sources/SpaceshipDashboard/main.swift`,
/// which calls `SpaceshipDashboardApp.main()`; keeping the App type in the
/// library lets the tvOS target share every other file.
public struct SpaceshipDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: DashboardStore
    @State private var liveData: LiveDataHub
    @State private var transition: DashboardTransitionController
    @State private var presentation: PresentationController
    @State private var sync: ConsoleSyncPublisher

    public init() {
        let store = DashboardStore()
        let liveData = LiveDataHub()
        let transition = DashboardTransitionController(initialID: store.selectedDashboardID)
        let presentation = PresentationController()
        let sync = ConsoleSyncPublisher(
            store: store,
            liveData: liveData,
            transition: transition,
            deviceName: Host.current().localizedName ?? "Spaceship Dashboard"
        )
        _store = State(initialValue: store)
        _liveData = State(initialValue: liveData)
        _transition = State(initialValue: transition)
        _presentation = State(initialValue: presentation)
        _sync = State(initialValue: sync)

        // The presentation window hosts its own root; it shares the same
        // store/hub/transition so both surfaces stay in lockstep.
        presentation.configure { [store, liveData, transition, sync] _, inset in
            AnyView(
                PresentationRootView(
                    inset: inset,
                    linkStatus: nil
                )
                .environment(store)
                .environment(liveData)
                .environment(transition)
                .environment(sync)
            )
        }
    }

    public var body: some Scene {
        WindowGroup {
            DashboardRootView()
                .environment(store)
                .environment(liveData)
                .environment(transition)
                .environment(presentation)
                .environment(sync)
                .frame(minWidth: 1180, minHeight: 760)
                .onAppear {
                    liveData.start()
                    sync.start()
                }
                .onDisappear {
                    presentation.stop()
                    sync.stop()
                    liveData.stop()
                    store.flushSave()
                }
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Cast") {
                Button(presentation.isPresenting ? "Stop Casting" : "Cast to External Display") {
                    presentation.toggle()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                ForEach(presentation.screens) { screen in
                    Button("Cast to \(screen.label)") {
                        presentation.present(on: screen)
                    }
                }

                Divider()

                Toggle(
                    "Cast Automatically When a Display Appears",
                    isOn: Binding(
                        get: { presentation.autoPresentOnExternalDisplay },
                        set: { presentation.setAutoPresent($0) }
                    )
                )
            }
        }
    }
}
#endif
