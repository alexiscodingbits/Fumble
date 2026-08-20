import FumbleCore
import FumbleUI
import SwiftUI

/// The adaptive trainer surface — keybr's loop, pre-aimed at your real weak letters. Shows the
/// virtual keyboard (coloured by confidence, focus key highlighted), per-letter confidence bars,
/// and a typing area; finishing a lesson updates confidence and generates the next one.
struct TrainerView: View {
    let coordinator: AppCoordinator

    @State private var trainer: KeyboardTrainer
    @State private var drill = DrillState(target: "")
    @State private var now: Double = ProcessInfo.processInfo.systemUptime
    @FocusState private var focused: Bool

    @State private var sessionStart: Double?
    @State private var completedChars = 0

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _trainer = State(initialValue: coordinator.makeTrainer())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                VirtualKeyboardView(focusKeyCode: trainer.focusKey?.keyCode, keyColor: keyColor)
                    .frame(maxWidth: .infinity)
                confidenceBars
                typingSurface
            }
            .padding(24)
        }
        .onAppear { if drill.target.isEmpty { startSession() } }
        .onReceive(ticker) { _ in now = ProcessInfo.processInfo.systemUptime }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            if let focus = trainer.focusKey {
                HStack(spacing: 8) {
                    Text("Focus").font(.caption).foregroundStyle(.secondary)
                    Text(focus.label)
                        .font(.system(.title, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    if let finger = focus.homeFinger {
                        Text(finger.displayName).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).layoutPriority(-1)
                    }
                }
            } else {
                Label("All letters mastered", systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(.green)
            }
            Spacer()
            stat(liveWPM.map { "\(Int($0.rounded()))" } ?? "—", "wpm")
            stat("\(trainer.unlockedKeys.count)/26", "letters")
            stat(String(format: "%.0f", coordinator.targetWPM), "target")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.headline.monospaced())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.leading, 12)
    }

    // MARK: - Confidence bars

    private var confidenceBars: some View {
        // Bars share the available width so the row never overflows, however many letters are
        // unlocked (it grows to all 26).
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(trainer.unlockedKeys, id: \.keyCode) { key in
                let confidence = trainer.confidence(for: key)
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SkillColor.color(confidence))
                        .frame(height: 6 + 40 * confidence)
                    Text(key.label)
                        .font(.system(size: 11, weight: key == trainer.focusKey ? .bold : .regular,
                                      design: .monospaced))
                        .foregroundStyle(key == trainer.focusKey ? Color.accentColor : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 64, alignment: .bottom)
    }

    // MARK: - Typing surface

    private var typingSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(attributedTarget)
                .font(.system(size: 22, design: .monospaced))
                .lineSpacing(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 2))
                .focusable()
                .focused($focused)
                .onKeyPress(phases: .down) { handle($0) }
            Text(focused ? "Type the letters above · it keeps going" : "Click here, then type.")
                .font(.caption2)
                .foregroundStyle(focused ? Color.secondary : Color.orange)
        }
        .onAppear { focused = true }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private var attributedTarget: AttributedString {
        var result = AttributedString()
        for (index, character) in drill.target.enumerated() {
            var piece = AttributedString(String(character))
            switch drill.statuses[index] {
            case .pending: piece.foregroundColor = .secondary.opacity(0.5)
            case .correct: piece.foregroundColor = .primary
            case .incorrect: piece.foregroundColor = .red
            case .current:
                piece.foregroundColor = .primary
                piece.backgroundColor = .accentColor.opacity(0.35)
            }
            result += piece
        }
        return result
    }

    // MARK: - Logic

    private var liveWPM: Double? {
        guard let start = sessionStart else { return nil }
        let chars = completedChars + drill.cursor
        guard chars >= 5 else { return nil }
        let minutes = (now - start) / 60
        guard minutes > 0 else { return nil }
        return (Double(chars) / 5.0) / minutes
    }

    private func keyColor(_ keyCode: Int) -> Color {
        let key = KeyIdentity(keyCode: keyCode)
        guard trainer.unlockedKeys.contains(where: { $0.keyCode == keyCode }) else {
            return SkillColor.locked
        }
        return SkillColor.color(trainer.confidence(for: key)).opacity(0.85)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .delete || press.key == .deleteForward
            || press.characters == "\u{8}" || press.characters == "\u{7f}" {
            drill.backspace()
            return .handled
        }
        guard press.characters.count == 1, let character = press.characters.first,
              character == " " || character.isLetter else { return .ignored }

        if sessionStart == nil { sessionStart = ProcessInfo.processInfo.systemUptime }
        drill.type(character, at: ProcessInfo.processInfo.systemUptime)

        if drill.isComplete {
            completedChars += drill.target.count
            trainer.record(perKeyWPM: drill.perKeyWPM())   // updates confidence + may unlock
            loadNextLesson()
        }
        return .handled
    }

    private func startSession() {
        sessionStart = nil
        completedChars = 0
        loadNextLesson()
        now = ProcessInfo.processInfo.systemUptime
        focused = true
    }

    private func loadNextLesson() {
        var rng = SystemRandomNumberGenerator()
        let text = TrainerLessonGenerator.generate(
            unlocked: trainer.unlockedKeys, focus: trainer.focusKey, wordCount: 24, using: &rng
        )
        drill = DrillState(target: text)
        focused = true
    }
}
