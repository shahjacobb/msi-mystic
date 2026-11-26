import SwiftUI
import AppKit

@main
struct MSILightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = LightController()

    var body: some Scene {
        WindowGroup("MSI Light") {
            ContentView()
                .environmentObject(controller)
                .frame(width: 400, height: 800)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
