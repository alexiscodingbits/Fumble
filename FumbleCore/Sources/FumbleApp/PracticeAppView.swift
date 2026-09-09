import FumbleCore
import FumbleUI
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

    /// The practice modes — keybr's lesson tabs, minus what doesn't fit (books, multiplayer).
    enum Mode: String, CaseIterable, Identifiable {
        case trainer, weakSpots, customText, numbers, code
        var id: String { rawValue }
        var title: String {
            switch self {
            case .trainer: "Trainer"
            case .weakSpots: "Weak spots"
            case .customText: "Custom text"
            case .numbers: "Numbers"
            case .code: "Code"
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
            // Bottom-left of the app: the only ask in a free product.
            .safeAreaInset(edge: .bottom) {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/alexmcconnell")!)
                } label: {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .help("Fumble is free — this is the tip jar")
            }
        } detail: {
            switch pane {
            case .practice: practicePane.id(coordinator.dataEpoch)
            case .stats: StatsPaneView(coordinator: coordinator)
            case .settings: SettingsPaneView(coordinator: coordinator)
            }
        }
        // Fixed size: the content is fixed-layout (keyboard, lists, typing box), so a resizable
        // window just manufactures dead space. Fixed-size is a normal pattern for compact Mac
        // utility apps.
        .frame(width: 860, height: 620)
        .preferredColorScheme(coordinator.appearance.colorScheme)
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
            HStack(spacing: 12) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 480)
                Spacer()
                goalChip
            }
            .padding(12)

            Divider()

            switch mode {
            case .trainer:
                // The trainer instance itself lives on the coordinator, so switching away and
                // back loses nothing — only the in-flight passage resets.
                TrainerView(coordinator: coordinator).id("trainer")
            case .weakSpots:
                DrillView(coordinator: coordinator).id("weakSpots")
            case .customText:
                CustomTextPracticeView(coordinator: coordinator).id("customText")
            case .numbers:
                DrillView(coordinator: coordinator, makePassage: { _ in
                    var rng = SystemRandomNumberGenerator()
                    return DrillPlan(
                        text: NumberLessonGenerator.generate(groupCount: 12, using: &rng),
                        focus: ["numbers"]
                    )
                }).id("numbers")
            case .code:
                DrillView(coordinator: coordinator, makePassage: { _ in
                    var rng = SystemRandomNumberGenerator()
                    return DrillPlan(
                        text: CodeLessonGenerator.generate(lineCount: 4, using: &rng),
                        focus: ["symbols"]
                    )
                }).id("code")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Today's goal progress + streak, tucked beside the mode picker. Hidden when the goal is off.
    @ViewBuilder
    private var goalChip: some View {
        // Reading goalVersion ties this view to practice-time writes (the log itself lives in
        // UserDefaults, which isn't observable).
        let _ = coordinator.goalVersion
        if let progress = coordinator.goalProgress {
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text("\(Int(coordinator.todayPracticeSeconds / 60))/\(coordinator.dailyGoalMinutes)m")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if coordinator.currentStreak > 0 {
                    Text("🔥\(coordinator.currentStreak)")
                        .font(.caption)
                        .help("\(coordinator.currentStreak)-day streak of meeting your goal")
                }
            }
            .help("Today's practice toward your daily goal")
        }
    }
}

/// Custom-text mode: paste anything, practice it. The text persists; passages are drawn as
/// random windows so long texts don't always start at the beginning.
struct CustomTextPracticeView: View {
    let coordinator: AppCoordinator
    @State private var draft: String = ""
    @State private var practising = false

    var body: some View {
        if practising, !coordinator.customPracticeText.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Button("Edit text") { practising = false }
                        .buttonStyle(.borderless).font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.top, 10)
                DrillView(coordinator: coordinator, makePassage: { coordinator in
                    var rng = SystemRandomNumberGenerator()
                    let words = CustomTextLesson.words(
                        from: coordinator.customPracticeText,
                        removePunctuation: false, lowercase: false
                    )
                    guard !words.isEmpty else {
                        return DrillPlan(text: "add some custom text first", focus: [])
                    }
                    // A random ~30-word window, so long texts get varied passages.
                    let window = 30
                    let start = words.count > window
                        ? Int.random(in: 0...(words.count - window), using: &rng) : 0
                    let slice = words[start..<min(start + window, words.count)]
                    return DrillPlan(text: slice.joined(separator: " "), focus: ["your text"])
                })
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Practice your own text").font(.title3.weight(.semibold))
                Text("Paste anything — an article, your own writing, code. Punctuation and capitals are kept; characters that can't be typed are dropped.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $draft)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
                HStack {
                    Button("Start practising") {
                        coordinator.customPracticeText = draft
                        practising = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { draft = coordinator.customPracticeText }
        }
    }
}
