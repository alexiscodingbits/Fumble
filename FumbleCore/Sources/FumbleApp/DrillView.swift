import FumbleCore
import FumbleUI
import SwiftUI

/// The practice surface. Captures real keystrokes (via `.onKeyPress`, for true per-key handling
/// rather than fighting a TextField's autocorrect), colours each character as you go, and runs
/// as a continuous session: finishing a passage immediately loads the next, so you can keep
/// typing without clicking. Session WPM and accuracy accumulate across passages.
struct DrillView: View {
    let coordinator: AppCoordinator

    /// Where this surface gets its passages. Defaults to the weak-spot drill; other practice
    /// modes (custom text, numbers, code) inject their own generator and reuse everything else.
    var makePassage: ((AppCoordinator) -> DrillPlan)?

    @State private var plan = DrillPlan(text: "", focus: [])
    @State private var drill = DrillState(target: "")
    @State private var now: Double = ProcessInfo.processInfo.systemUptime
    @FocusState private var focused: Bool
    /// Set for one beat after a wrong keystroke; drives the border flash.
    @State private var errorFlash = false
    /// Monotonic token so a stale flash-reset task can't truncate a newer flash.
    @State private var errorFlashToken = 0

    // Session accumulators, across completed passages this session.
    @State private var sessionStart: Double?
    /// Active typing time this passage: per-keystroke deltas, idle gaps excluded — so walking
    /// away mid-passage doesn't count as practice toward the daily goal.
    @State private var passageActiveSeconds: Double = 0
    /// Active typing time across the session — the WPM denominator. Frozen while idle, so the
    /// number doesn't decay by the second when you stop typing.
    @State private var sessionActiveSeconds: Double = 0
    @State private var lastKeystrokeStamp: Double?
    @State private var completedChars = 0
    @State private var completedTyped = 0
    @State private var completedErrors = 0
    @State private var passagesDone = 0

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            typingSurface
            footer
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { startSession() }
        .onReceive(ticker) { _ in
            now = ProcessInfo.processInfo.systemUptime
            restartIfIdle()
            claimFocusIfWindowIsKey()
        }
    }

    // MARK: - Header (live session stats)

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Practice").font(.title2.weight(.semibold))
            Spacer()
            stat(sessionWPM.map { "\(Int($0.rounded()))" } ?? "—", "wpm")
            stat(sessionAccuracy.map { String(format: "%.0f%%", $0 * 100) } ?? "—", "acc")
            stat("\(passagesDone)", "passages")
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
        VStack(alignment: .leading, spacing: 14) {
            focusLine
            drillText
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(phases: .down) { press in handle(press) }
            Text(focused ? hintText : "Click here, then type.")
                .font(.caption2)
                .foregroundStyle(focused ? Color.secondary : Color.orange)
        }
        .onAppear { focused = true }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    /// Backspace only exists in advance mode; the stop-until-correct hint says what actually helps.
    private var hintText: String {
        coordinator.typingAssistRaw == DrillState.ErrorHandling.stopUntilCorrect.rawValue
            ? "Type the text above · the cursor waits until you hit the right key"
            : "Type the text above · ⌫ to fix mistakes · it keeps going"
    }

    @ViewBuilder
    private var focusLine: some View {
        if plan.isWarmUp {
            Text("Warm-up — type naturally. Once Fumble has learned your weak spots, drills will target them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                Text("Focusing on").font(.caption).foregroundStyle(.secondary)
                ForEach(plan.focus, id: \.self) { item in
                    Text(item)
                        .font(.caption.monospaced().weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
        }
    }

    private var drillText: some View {
        TypingTextView(
            target: drill.target, statuses: drill.statuses, cursor: drill.cursor,
            showWhitespaceDots: coordinator.showWhitespaceDots,
            cursorStyle: coordinator.cursorStyle
        )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.surfaceBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
            // Error flash only — see TrainerView for why focus doesn't draw a ring.
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(errorFlash ? Color.red.opacity(0.8) : .clear, lineWidth: 2)
            )
            .animation(.easeOut(duration: 0.15), value: errorFlash)
    }

    private var footer: some View {
        HStack {
            Button("New session") { startSession() }
            Spacer()
            Text("Practice is scored on its own — it does not affect your daily stats.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Session stats

    /// WPM across the whole session, over ACTIVE typing time — which freezes when you stop,
    /// so the figure doesn't decay by the second after a passage (wall-clock division did).
    private var sessionWPM: Double? {
        let chars = completedChars + drill.cursor
        guard chars >= 5, sessionActiveSeconds > 1 else { return nil }
        return (Double(chars) / 5.0) / (sessionActiveSeconds / 60)
    }

    private var sessionAccuracy: Double? {
        let typed = completedTyped + drill.totalTyped
        guard typed > 0 else { return nil }
        let errors = completedErrors + drill.errors
        return 1.0 - Double(errors) / Double(typed)
    }

    // MARK: - Input

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        // Delete/backspace — detected several ways because key routing varies: the .delete key
        // equivalent, forward-delete, and the raw backspace/DEL control characters.
        if press.key == .delete || press.key == .deleteForward
            || press.characters == "\u{8}" || press.characters == "\u{7f}" {
            drill.backspace()
            return .handled
        }

        guard press.characters.count == 1, let character = press.characters.first,
              character == " " || character.isLetter || character.isNumber
                || character.isPunctuation || character.isSymbol
        else { return .ignored }

        let stamp = ProcessInfo.processInfo.systemUptime
        if sessionStart == nil { sessionStart = stamp }
        if let last = lastKeystrokeStamp, stamp - last <= 5 {
            passageActiveSeconds += stamp - last
            sessionActiveSeconds += stamp - last
        }
        lastKeystrokeStamp = stamp
        drill.type(character, at: stamp)

        // Feedback: sounds per settings, and a brief border flash on error.
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

        // Continuous flow: finishing a passage rolls its counts into the session and loads the
        // next one seamlessly, so there's no dead end and no button to press.
        if drill.isComplete {
            completedChars += drill.target.count
            completedTyped += drill.totalTyped
            completedErrors += drill.errors
            passagesDone += 1
            // Daily-goal accounting: active typing time only.
            coordinator.recordPracticeTime(seconds: passageActiveSeconds)
            loadNextPassage()
        }
        return .handled
    }

    /// See TrainerView.restartIfIdle — same rule: 10s idle mid-passage restarts the same passage.
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
        completedTyped = 0
        completedErrors = 0
        passagesDone = 0
        loadNextPassage()
        now = ProcessInfo.processInfo.systemUptime
        focused = true
    }

    private func loadNextPassage() {
        plan = makePassage.map { $0(coordinator) } ?? coordinator.makeDrill()
        drill = DrillState(
            target: plan.text,
            errorHandling: DrillState.ErrorHandling(rawValue: coordinator.typingAssistRaw) ?? .stopUntilCorrect
        )
        passageActiveSeconds = 0
        lastKeystrokeStamp = nil
        focused = true
    }
}
