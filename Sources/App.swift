import SwiftUI
import AppKit

@main
struct LumeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = LightController()

    var body: some Scene {
        WindowGroup("Lume") {
            ContentView()
                .environmentObject(controller)
                .frame(width: 380, height: 690)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
