import SwiftUI

/// Trainer and data settings.
struct SettingsPaneView: View {
    let coordinator: AppCoordinator

    private var targetWPM: Binding<Double> {
        Binding(get: { coordinator.targetWPM }, set: { coordinator.targetWPM = $0 })
    }

    var body: some View {
        Form {
            Section("Trainer") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Target speed")
                        Spacer()
                        Text("\(Int(coordinator.targetWPM)) WPM").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: targetWPM, in: 15...120, step: 5)
                    Text("A letter is 'mastered' — and the next unlocks — once you reach this speed on it. keybr's default is 35.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                Button("Show data in Finder") { coordinator.revealDataInFinder() }
                Button("Delete all data", role: .destructive) { coordinator.deleteAllData() }
                Text("\(bytesString) on disk · local only, no account, no network. Fumble records which keys and when, never the characters you type.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }

    private var bytesString: String {
        let value = coordinator.bytesOnDisk
        if value < 1_024 { return "\(value) B" }
        if value < 1_024 * 1_024 { return String(format: "%.0f KB", Double(value) / 1_024) }
        return String(format: "%.1f MB", Double(value) / (1_024 * 1_024))
    }
}
