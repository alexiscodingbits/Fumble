import AppKit
import FumbleUI
import SwiftUI

@main
struct FumbleApp: App {
    @State private var coordinator = AppCoordinator()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            DropdownView(coordinator: coordinator)
        } label: {
            // A glyph plus a number. While you're typing it shows live speed (with a ›
            // marker); when idle it falls back to the selected timeframe's average.
            HStack(spacing: 3) {
                Image(systemName: "keyboard")
                if let live = coordinator.liveWPM {
                    Text("› \(Int(live.rounded()))")
                } else {
                    Text(coordinator.viewState.barText)
                }
            }
            .onAppear {
                appDelegate.coordinator = coordinator
                coordinator.start()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Exists for one reason: `applicationWillTerminate`, so the final flush happens. SwiftUI's
/// `App` lifecycle gives no equivalent hook for an `LSUIElement` menu-bar app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var coordinator: AppCoordinator?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            coordinator?.shutDown()
        }
    }
}
