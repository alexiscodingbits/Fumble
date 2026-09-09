import FumbleUI
import SwiftUI

/// Trainer, practice-feel, goal, and data settings.
struct SettingsPaneView: View {
    let coordinator: AppCoordinator
    @State private var confirmingDelete = false

    private var targetWPM: Binding<Double> {
        Binding(get: { coordinator.targetWPM }, set: { coordinator.targetWPM = $0 })
    }
    private var typingAssist: Binding<DrillState.ErrorHandling> {
        Binding(
            get: { DrillState.ErrorHandling(rawValue: coordinator.typingAssistRaw) ?? .advance },
            set: { coordinator.typingAssistRaw = $0.rawValue }
        )
    }
    private var keyClicks: Binding<Bool> {
        Binding(get: { coordinator.soundMode == .keys }, set: { coordinator.soundMode = $0 ? .keys : .off })
    }
    private var soundVolume: Binding<Double> {
        Binding(get: { coordinator.soundVolume }, set: { coordinator.soundVolume = $0 })
    }
    private var whitespaceDots: Binding<Bool> {
        Binding(get: { coordinator.showWhitespaceDots }, set: { coordinator.showWhitespaceDots = $0 })
    }
    private var cursorStyle: Binding<CursorStyle> {
        Binding(get: { coordinator.cursorStyle }, set: { coordinator.cursorStyle = $0 })
    }
    private var goalMinutes: Binding<Double> {
        Binding(get: { Double(coordinator.dailyGoalMinutes) }, set: { coordinator.dailyGoalMinutes = Int($0) })
    }
    private var appearance: Binding<AppearanceMode> {
        Binding(get: { coordinator.appearance }, set: { coordinator.appearance = $0 })
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
                    Text("A letter is 'mastered' — and the next unlocks — once you reach this speed on it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Typing") {
                Picker("On a wrong key", selection: typingAssist) {
                    Text("Keep going — fix with ⌫").tag(DrillState.ErrorHandling.advance)
                    Text("Stop until correct").tag(DrillState.ErrorHandling.stopUntilCorrect)
                }
                Text("'Stop until correct' is how most tutors teach accuracy: the cursor waits at a mistake. 'Keep going' favours flow and rewards self-correction.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show spaces as dots", isOn: whitespaceDots)
                Picker("Cursor", selection: cursorStyle) {
                    ForEach(CursorStyle.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Sounds") {
                Toggle("Key click sounds", isOn: keyClicks)
                if coordinator.soundMode != .off {
                    HStack {
                        Text("Volume")
                        Slider(value: soundVolume, in: 0...1)
                        Button("Test") { coordinator.sounds.key(volume: coordinator.soundVolume) }
                            .buttonStyle(.borderless)
                    }
                }
            }

            Section("Daily goal") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Practice goal")
                        Spacer()
                        Text(coordinator.dailyGoalMinutes == 0 ? "Off" : "\(coordinator.dailyGoalMinutes) min/day")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: goalMinutes, in: 0...60, step: 5)
                    Text("A reminder, never a limit. Streaks count days you met the goal.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                Button("Show data in Finder") { coordinator.revealDataInFinder() }
                Button(confirmingDelete ? "Really delete everything?" : "Delete all data",
                       role: .destructive) {
                    if confirmingDelete {
                        coordinator.deleteAllData()
                        confirmingDelete = false
                    } else {
                        confirmingDelete = true   // single-click total erasure needs a second look
                    }
                }
                Text("\(bytesString) on disk · local only, no account, no network. Fumble records which keys and when, never the characters you type. Typing inside Fumble's own practice window is excluded from your daily stats.")
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
