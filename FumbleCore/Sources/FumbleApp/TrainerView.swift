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
    /// Active typing time across the whole session — the WPM denominator. Frozen while idle,
    /// so the number doesn't decay by the second when you stop typing.
    @State private var sessionActiveSeconds: Double = 0
    @State private var lastKeystrokeStamp: Double?
    @State private var completedChars = 0

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        // A plain VStack like the other practice tabs — the ScrollView dated from when the
        // (since-removed) confidence bars made the pane taller than the window.
        VStack(alignment: .leading, spacing: 16) {
            header
            VirtualKeyboardView(focusKeyCode: trainer.focusKey?.keyCode, keyColor: keyColor)
                .frame(maxWidth: .infinity)
            Text("Keys: progress to your target (green = at target) · grey = locked · blue outline = being practised")
                .font(.caption2).foregroundStyle(.tertiary)
            typingSurface
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { if drill.target.isEmpty { startSession() } }
        .onReceive(ticker) { _ in
            now = ProcessInfo.processInfo.systemUptime
            restartIfIdle()
            claimFocusIfWindowIsKey()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                if let focus = trainer.focusKey {
                    // Say what's happening in words — "Focus B · L index" reads as jargon to
                    // anyone who didn't build the app.
                    HStack(spacing: 10) {
                        Text(focus.label)
                            .font(.system(.title, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Practising your slowest letter")
                                .font(.caption.weight(.medium))
                            if let finger = focus.homeFinger {
                                Text("press it with your \(finger.longName)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .lineLimit(1).layoutPriority(-1)
                    }
                } else {
                    Label("All letters at target — raise the target speed in Settings to keep progressing",
                          systemImage: "checkmark.seal.fill")
                        .font(.subheadline).foregroundStyle(.green)
                        .lineLimit(1)
                }
                Spacer()
                stat(liveWPM.map { "\(Int($0.rounded()))" } ?? "—", "wpm")
                    .help("Your speed this session, measured over active typing time")
                stat("\(trainer.unlockedKeys.count)/26", "letters")
                    .help("Letters unlocked so far — the rest unlock as you reach the target speed")
                stat(String(format: "%.0f", coordinator.targetWPM), "target")
                    .help("A letter is mastered at this speed (change it in Settings)")
            }
            // keybr's per-key feedback line: how the focus letter is actually progressing.
            if let focus = trainer.focusKey, let last = trainer.lastWPM(for: focus) {
                HStack(spacing: 10) {
                    Text("last lesson \(Int(last.rounded())) wpm")
                    if let top = trainer.topWPM(for: focus) {
                        Text("best \(Int(top.rounded())) wpm")
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

    // MARK: - Typing surface

    private var typingSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            TypingTextView(
                target: drill.target, statuses: drill.statuses, cursor: drill.cursor,
                showWhitespaceDots: coordinator.showWhitespaceDots,
                cursorStyle: coordinator.cursorStyle
            )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.surfaceBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
                // Only the error flash draws a ring. Focus is signalled by the hint line below,
                // not a border: a focus stroke plus the system focus ring read as a box inside
                // a box, and the surface is the whole pane's obvious place to type anyway.
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(errorFlash ? Color.red.opacity(0.8) : .clear, lineWidth: 2))
                .animation(.easeOut(duration: 0.15), value: errorFlash)
                .focusable()
                .focusEffectDisabled()
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
        // Measured over ACTIVE typing time, which freezes when you stop — dividing by
        // wall-clock made the number visibly decay ~1/second after finishing a lesson.
        let chars = completedChars + drill.cursor
        guard chars >= 5, sessionActiveSeconds > 1 else { return nil }
        return (Double(chars) / 5.0) / (sessionActiveSeconds / 60)
    }

    private func keyColor(_ keyCode: Int) -> Color {
        guard trainer.unlockedKeys.contains(where: { $0.keyCode == keyCode }) else {
            return SkillColor.locked
        }
        // Coloured by progress toward the TARGET, keybr-style: green means "this letter is at
        // your target speed", full stop. An all-green board is a real signal (raise the target),
        // and it can never contradict the "all letters at target" banner. Relative-spread
        // colouring did contradict it — every board showed red somewhere, even at target.
        // (The relative heatmap still exists where it belongs: Stats.)
        return SkillColor.color(trainer.confidence(for: KeyIdentity(keyCode: keyCode))).opacity(0.85)
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
            sessionActiveSeconds += stamp - last
        }
        lastKeystrokeStamp = stamp
        drill.type(character, at: stamp)

        coordinator.practiceKeystrokeFeedback()
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

    /// keybr behaviour: walk away mid-lesson for 10s and the SAME lesson restarts from the top.
    /// A half-typed passage resumed after a break gives a garbage WPM for the passage and, worse,
    /// a garbage per-key sample for the trainer — the first reach after a coffee isn't a reach.
    /// Same text, so nothing is "lost" beyond the position.
    private func restartIfIdle() {
        guard let last = lastKeystrokeStamp, drill.cursor > 0, !drill.isComplete,
              now - last >= Self.idleRestartSeconds else { return }
        drill = DrillState(target: String(drill.target), errorHandling: drill.errorHandling)
        passageActiveSeconds = 0
        lastKeystrokeStamp = nil
    }
    private static let idleRestartSeconds: Double = 10

    /// Type-anywhere: the moment the practice window is key, the typing surface holds focus.
    /// `focused = true` in onAppear alone isn't enough — on first show the sidebar list takes
    /// first responder, and the intro sheet steals it on a fresh install — so the ticker keeps
    /// re-asserting. Skipped while a sheet is up (it's the key window then) and when another
    /// window is in front. There are no other text inputs on this pane, so nothing is stolen.
    private func claimFocusIfWindowIsKey() {
        guard !focused, let window = NSApp.keyWindow, !window.isSheet else { return }
        focused = true
    }

    private func startSession() {
        sessionStart = nil
        sessionActiveSeconds = 0
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
            unlocked: trainer.unlockedKeys, focus: trainer.focusKey, wordCount: coordinator.lessonWordCount,
            naturalWords: WordList.english(spelling: coordinator.spelling), using: &rng
        )
        drill = DrillState(
            target: text,
            errorHandling: DrillState.ErrorHandling(rawValue: coordinator.typingAssistRaw) ?? .stopUntilCorrect
        )
        passageActiveSeconds = 0
        lastKeystrokeStamp = nil
        focused = true
    }
}
