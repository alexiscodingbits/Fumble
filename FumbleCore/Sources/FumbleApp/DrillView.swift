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

    // Session accumulators, across completed passages this session.
    @State private var sessionStart: Double?
    @State private var passageStart: Double?
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
        .onReceive(ticker) { _ in now = ProcessInfo.processInfo.systemUptime }
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
                .focused($focused)
                .onKeyPress(phases: .down) { press in handle(press) }
            Text(focused ? "Type the text above · ⌫ to fix mistakes · it keeps going" : "Click here, then type.")
                .font(.caption2)
                .foregroundStyle(focused ? Color.secondary : Color.orange)
        }
        .onAppear { focused = true }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
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
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        errorFlash ? Color.red.opacity(0.8)
                            : focused ? Color.accentColor.opacity(0.6) : .clear,
                        lineWidth: 2
                    )
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

    /// WPM across the whole session, including the passage in progress.
    private var sessionWPM: Double? {
        guard let start = sessionStart else { return nil }
        let chars = completedChars + drill.cursor
        guard chars >= 5 else { return nil }
        let minutes = (now - start) / 60
        guard minutes > 0 else { return nil }
        return (Double(chars) / 5.0) / minutes
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
        if passageStart == nil { passageStart = stamp }
        drill.type(character, at: stamp)

        // Feedback: sounds per settings, and a brief border flash on error.
        coordinator.practiceKeystrokeFeedback(wasError: drill.lastEventWasError)
        if drill.lastEventWasError {
            errorFlash = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                errorFlash = false
            }
        }

        // Continuous flow: finishing a passage rolls its counts into the session and loads the
        // next one seamlessly, so there's no dead end and no button to press.
        if drill.isComplete {
            completedChars += drill.target.count
            completedTyped += drill.totalTyped
            completedErrors += drill.errors
            passagesDone += 1
            // Daily-goal accounting: the wall-clock span of this passage.
            if let start = passageStart { coordinator.recordPracticeTime(seconds: stamp - start) }
            loadNextPassage()
        }
        return .handled
    }

    private func startSession() {
        sessionStart = nil
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
            errorHandling: DrillState.ErrorHandling(rawValue: coordinator.typingAssistRaw) ?? .advance
        )
        passageStart = nil   // stamps on the first keystroke of the new passage
        focused = true
    }
}
