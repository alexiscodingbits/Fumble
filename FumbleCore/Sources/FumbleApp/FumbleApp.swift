import AppKit
import FumbleUI
import SwiftUI

@main
struct FumbleApp: App {
    @State private var coordinator = AppCoordinator.shared
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

        // The practice surface lives in a real window (a menu-bar popover can't hold focus for
        // key capture). A full multi-pane app: Practice / Stats / Settings.
        Window("Fumble", id: Self.practiceWindowID) {
            PracticeAppView(coordinator: coordinator)
        }
        .windowResizability(.contentMinSize)
    }

    static let practiceWindowID = "practice"
}

/// Exists for one reason: `applicationWillTerminate`, so the final flush happens. SwiftUI's
/// `App` lifecycle gives no equivalent hook for an `LSUIElement` menu-bar app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Fallback start: normally the menu-bar label's onAppear starts capture, but a
            // crowded menu bar can keep the item (and its onAppear) from ever appearing.
            // start() is idempotent, so both paths firing is fine.
            AppCoordinator.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            (coordinator ?? AppCoordinator.shared).shutDown()
        }
    }
}
