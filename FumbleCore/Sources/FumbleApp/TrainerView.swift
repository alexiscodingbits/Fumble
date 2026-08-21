import FumbleCore
import FumbleUI
import SwiftUI

/// The adaptive trainer surface — keybr's loop, pre-aimed at your real weak letters. Shows the
/// virtual keyboard (coloured by confidence, focus key highlighted), per-letter confidence bars,
/// and a typing area; finishing a lesson updates confidence and generates the next one.
struct TrainerView: View {
    let coordinator: AppCoordinator

    /// The session-lived trainer. Owned by the coordinator (not view @State) so switching
    /// panes/modes can't wipe lesson progress, and the seed computation isn't re-run on every
    /// parent re-render. Same instance every call; @Observable keeps the view tracking it.
    private var trainer: KeyboardTrainer { coordinator.trainer() }

    @State private var drill = DrillState(target: "")
    @State private var now: Double = ProcessInfo.processInfo.systemUptime
    @FocusState private var focused: Bool
    @State private var errorFlash = false
    /// Monotonic token so a stale flash-reset task can't truncate a newer flash.
    @State private var errorFlashToken = 0

    @State private var sessionStart: Double?
    /// Active typing time this lesson (idle-capped deltas) — daily-goal accounting.
    @State private var passageActiveSeconds: Double = 0
    @State private var lastKeystrokeStamp: Double?
    @State private var completedChars = 0

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

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
        VStack(alignment: .leading, spacing: 4) {
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
            // keybr's per-key feedback line: how the focus letter is actually progressing.
            if let focus = trainer.focusKey, let last = trainer.lastWPM(for: focus) {
                HStack(spacing: 10) {
                    Text("Last \(Int(last.rounded())) wpm")
                    if let top = trainer.topWPM(for: focus) {
                        Text("Top \(Int(top.rounded())) wpm")
                    }
                    if let rate = trainer.learningRate(for: focus) {
                        Text(String(format: "%@%.1f wpm/lesson", rate >= 0 ? "+" : "", rate))
                            .foregroundStyle(rate >= 0 ? Color.green : Color.orange)
                    }
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }
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
            Text(TypingText.render(
                target: drill.target, statuses: drill.statuses,
                showWhitespaceDots: coordinator.showWhitespaceDots,
                cursorStyle: coordinator.cursorStyle
            ))
                .font(.system(size: 22, design: .monospaced))
                .lineSpacing(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        errorFlash ? Color.red.opacity(0.8)
                            : focused ? Color.accentColor.opacity(0.6) : .clear,
                        lineWidth: 2
                    ))
                .animation(.easeOut(duration: 0.15), value: errorFlash)
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

        let stamp = ProcessInfo.processInfo.systemUptime
        if sessionStart == nil { sessionStart = stamp }
        if let last = lastKeystrokeStamp, stamp - last <= 5 {
            passageActiveSeconds += stamp - last
        }
        lastKeystrokeStamp = stamp
        drill.type(character, at: stamp)

        coordinator.practiceKeystrokeFeedback(wasError: drill.lastEventWasError)
        if drill.lastEventWasError {
            errorFlash = true
            errorFlashToken += 1
            let token = errorFlashToken
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                // Only the newest error's task may clear the flash; an older task going off
                // mid-flash would truncate it.
                if errorFlashToken == token { errorFlash = false }
            }
        }

        if drill.isComplete {
            completedChars += drill.target.count
            trainer.record(perKeyWPM: drill.perKeyWPM())   // updates confidence + may unlock
            coordinator.saveTrainer()                       // progress survives quit/relaunch
            coordinator.recordPracticeTime(seconds: passageActiveSeconds)
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
        // naturalWords is what keeps rare-letter lessons readable: real q/z/x words instead of
        // pseudo-word soup ("quick quote unique", not "qqlqq muqq").
        let text = TrainerLessonGenerator.generate(
            unlocked: trainer.unlockedKeys, focus: trainer.focusKey, wordCount: 24,
            naturalWords: WordList.english, using: &rng
        )
        drill = DrillState(
            target: text,
            errorHandling: DrillState.ErrorHandling(rawValue: coordinator.typingAssistRaw) ?? .advance
        )
        passageActiveSeconds = 0
        lastKeystrokeStamp = nil
        focused = true
    }
}
