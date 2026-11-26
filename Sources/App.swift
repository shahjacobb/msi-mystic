import SwiftUI
import AppKit

@main
struct MSIMonitorLightingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = LightController()

    var body: some Scene {
        WindowGroup("MSI Monitor Lighting") {
            ContentView()
                .environmentObject(controller)
                .frame(width: 380, height: 780)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
