import FumbleCore
import FumbleUI
import SwiftUI

/// The practice surface. Shows target text, captures real keystrokes (via `.onKeyPress`, so we
/// get true per-key handling rather than fighting a TextField's autocorrect), colours each
/// character as you go, and reports WPM + accuracy on completion.
struct DrillView: View {
    let coordinator: AppCoordinator

    @State private var plan: DrillPlan = DrillPlan(text: "", focus: [])
    @State private var drill = DrillState(target: "")
    @State private var now: Double = ProcessInfo.processInfo.systemUptime
    @FocusState private var focused: Bool

    // Drives the live WPM readout during a drill.
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if drill.isComplete {
                results
            } else {
                typingSurface
            }

            footer
        }
        .padding(24)
        .frame(width: 620, height: 340)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { newDrill() }
        .onReceive(ticker) { _ in now = ProcessInfo.processInfo.systemUptime }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Practice").font(.title2.weight(.semibold))
            Spacer()
            if !drill.isComplete, let wpm = drill.wordsPerMinute(now: now) {
                Text("\(Int(wpm.rounded())) wpm").font(.headline.monospaced()).foregroundStyle(.secondary)
            }
        }
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

    private var typingSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            focusLine
            drillText
                .focusable()
                .focused($focused)
                .onKeyPress(phases: .down) { press in handle(press) }
            Text(focused ? "Type the text above." : "Click here, then type.")
                .font(.caption2)
                .foregroundStyle(focused ? Color.secondary : Color.orange)
        }
        // Grab focus so keystrokes land here immediately.
        .onAppear { focused = true }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    /// The target rendered character-by-character, coloured by status.
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
                // Show the intended character in red; a wrong space gets an underline so it's visible.
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

    private var results: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Done").font(.title3.weight(.semibold))
            HStack(spacing: 24) {
                metric("WPM", drill.wordsPerMinute(now: now).map { "\(Int($0.rounded()))" } ?? "—")
                metric("Accuracy", drill.accuracy.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                metric("Characters", "\(drill.target.count)")
            }
            .padding(.vertical, 4)
            if !plan.isWarmUp {
                Text("Drilled: \(plan.focus.joined(separator: "  "))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title, design: .monospaced).weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button(drill.isComplete ? "Next drill" : "New drill") { newDrill() }
                .keyboardShortcut(.return, modifiers: drill.isComplete ? [] : [.command])
            Spacer()
            Text("Practice is scored on its own — it does not affect your daily stats.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Input

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .delete {
            drill.backspace()
            return .handled
        }
        // Single printable character (letters, space, digits, punctuation). Ignore modifiers,
        // arrows, Return, etc. so they don't count as mistypes.
        guard press.characters.count == 1, let character = press.characters.first,
              character == " " || character.isLetter || character.isNumber || character.isPunctuation
        else { return .ignored }

        drill.type(character, at: ProcessInfo.processInfo.systemUptime)
        return .handled
    }

    private func newDrill() {
        plan = coordinator.makeDrill()
        drill = DrillState(target: plan.text)
        now = ProcessInfo.processInfo.systemUptime
        focused = true
    }
}
