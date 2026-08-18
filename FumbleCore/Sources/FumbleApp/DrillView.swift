import FumbleCore
import FumbleUI
import SwiftUI

/// The practice surface. Captures real keystrokes (via `.onKeyPress`, for true per-key handling
/// rather than fighting a TextField's autocorrect), colours each character as you go, and runs
/// as a continuous session: finishing a passage immediately loads the next, so you can keep
/// typing without clicking. Session WPM and accuracy accumulate across passages.
struct DrillView: View {
    let coordinator: AppCoordinator

    @State private var plan = DrillPlan(text: "", focus: [])
    @State private var drill = DrillState(target: "")
    @State private var now: Double = ProcessInfo.processInfo.systemUptime
    @FocusState private var focused: Bool

    // Session accumulators, across completed passages this session.
    @State private var sessionStart: Double?
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
        Text(attributedTarget)
            .font(.system(size: 22, design: .monospaced))
            .lineSpacing(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 2)
            )
    }

    private var attributedTarget: AttributedString {
        var result = AttributedString()
        for (index, character) in drill.target.enumerated() {
            var piece = AttributedString(String(character))
            switch drill.statuses[index] {
            case .pending:
                piece.foregroundColor = .secondary.opacity(0.5)
            case .correct:
                piece.foregroundColor = .primary
            case .incorrect:
                piece.foregroundColor = .red
                if character == " " { piece.underlineStyle = .single }
            case .current:
                piece.foregroundColor = .primary
                piece.backgroundColor = .accentColor.opacity(0.35)
            }
            result += piece
        }
        return result
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
              character == " " || character.isLetter || character.isNumber || character.isPunctuation
        else { return .ignored }

        if sessionStart == nil { sessionStart = ProcessInfo.processInfo.systemUptime }
        drill.type(character, at: ProcessInfo.processInfo.systemUptime)

        // Continuous flow: finishing a passage rolls its counts into the session and loads the
        // next one seamlessly, so there's no dead end and no button to press.
        if drill.isComplete {
            completedChars += drill.target.count
            completedTyped += drill.totalTyped
            completedErrors += drill.errors
            passagesDone += 1
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
        plan = coordinator.makeDrill()
        drill = DrillState(target: plan.text)
        focused = true
    }
}
