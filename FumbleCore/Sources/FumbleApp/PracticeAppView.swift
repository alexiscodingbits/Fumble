import SwiftUI

/// The full practice app: a multi-pane window (Practice / Stats / Settings) hosted in a real
/// window, with a Dock icon and app menus while it's open — so "Practice" feels like an actual
/// app rather than a popover.
struct PracticeAppView: View {
    let coordinator: AppCoordinator

    enum Pane: String, CaseIterable, Identifiable {
        case practice, stats, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .practice: "Practice"
            case .stats: "Stats"
            case .settings: "Settings"
            }
        }
        var icon: String {
            switch self {
            case .practice: "figure.run"
            case .stats: "chart.bar.xaxis"
            case .settings: "gearshape"
            }
        }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case trainer, freeDrill
        var id: String { rawValue }
        var title: String {
            switch self {
            case .trainer: "Trainer"
            case .freeDrill: "Weak-spot drill"
            }
        }
    }

    @State private var pane: Pane = .practice
    @State private var mode: Mode = .trainer

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.icon).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch pane {
            case .practice: practicePane
            case .stats: StatsPaneView(coordinator: coordinator)
            case .settings: SettingsPaneView(coordinator: coordinator)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        // Become a regular app (Dock icon + menus) while the window is open; drop back to a
        // menu-bar accessory when it closes.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }

    private var practicePane: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            .frame(maxWidth: 360)

            Divider()

            switch mode {
            case .trainer:
                // Rebuilt when switching in, so it re-seeds from the latest captured data.
                TrainerView(coordinator: coordinator).id("trainer")
            case .freeDrill:
                DrillView(coordinator: coordinator).id("freeDrill")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
