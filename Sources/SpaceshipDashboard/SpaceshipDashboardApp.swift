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

@main
struct SpaceshipDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: DashboardStore
    @State private var liveData = LiveDataHub()
    @State private var transition: DashboardTransitionController

    init() {
        let store = DashboardStore()
        _store = State(initialValue: store)
        _transition = State(initialValue: DashboardTransitionController(initialID: store.selectedDashboardID))
    }

    var body: some Scene {
        WindowGroup {
            DashboardRootView()
                .environment(store)
                .environment(liveData)
                .environment(transition)
                .frame(minWidth: 1180, minHeight: 760)
                .onAppear { liveData.start() }
                .onDisappear {
                    liveData.stop()
                    store.flushSave()
                }
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
