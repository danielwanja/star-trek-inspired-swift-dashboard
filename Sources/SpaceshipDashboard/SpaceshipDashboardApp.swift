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
    @StateObject private var store = DashboardStore()
    @StateObject private var liveData = LiveDataHub()

    var body: some Scene {
        WindowGroup {
            DashboardRootView()
                .environmentObject(store)
                .environmentObject(liveData)
                .frame(minWidth: 1180, minHeight: 760)
                .onAppear { liveData.start() }
                .onDisappear { liveData.stop() }
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
