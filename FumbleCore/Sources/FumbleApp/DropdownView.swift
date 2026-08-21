import FumbleCore
import FumbleUI
import SwiftUI

struct DropdownView: View {
    let coordinator: AppCoordinator
    @State private var showingDiagnostics = false
    @State private var confirmingDelete = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    private func openPractice() {
        openWindow(id: FumbleApp.practiceWindowID)
        // Accessory (menu-bar) apps don't come forward on their own; bring the window to front.
        NSApp.activate(ignoringOtherApps: true)
        // Close the menu-bar popover so it doesn't hang over the app window.
        dismiss()
    }

    private var state: MenuViewState { coordinator.viewState }

    /// Before there are ranked weak spots, a drill is a warm-up; after, it targets them.
    private var practiceLabel: String {
        if case .ready = state.readiness { return "Practice weak spots" }
        return "Practice (warm-up)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch state.readiness {
            case .needsPermission:
                permissionGate
            case .noData:
                liveAndTimeframe
                message(
                    "No keystrokes recorded yet.",
                    detail: "Type anywhere and this will fill in."
                )
            case .learning(let active, let required):
                liveAndTimeframe
                learningState(activeSeconds: active, requiredSeconds: required)
            case .ready:
                liveAndTimeframe
                summary
                weakSpots
            }

            if state.readiness != .needsPermission {
                Button {
                    openPractice()
                } label: {
                    Label(practiceLabel, systemImage: "figure.run")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Fumble").font(.headline)
            Spacer()
            if coordinator.tapFailedToStart {
                Label("tap failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("The keyboard tap could not start. Check Input Monitoring permission.")
            }
        }
    }

    /// Live speed on the left, timeframe selector for the averages on the right.
    private var liveAndTimeframe: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(coordinator.liveWPM.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(coordinator.liveWPM == nil ? .secondary : .primary)
                    .contentTransition(.numericText())
                Text("live wpm").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { coordinator.selectedTimeframe },
                set: { coordinator.selectedTimeframe = $0 }
            )) {
                ForEach(Timeframe.allCases) { frame in
                    Text(frame.label).tag(frame)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private var permissionGate: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Input Monitoring needed", systemImage: "lock.shield")
                .font(.subheadline.weight(.medium))
            Text("Fumble needs to see *which* keys you press and *when*. It never records the characters you type, and nothing leaves this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Grant access") { coordinator.requestPermission() }
                    .buttonStyle(.borderedProminent)
                Button("Open Settings") { coordinator.openPrivacySettings() }
            }
        }
    }

    private func learningState(activeSeconds: Double, requiredSeconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            summary
            ProgressView(value: min(activeSeconds / requiredSeconds, 1)) {
                Text("Learning your baseline")
                    .font(.caption)
            } currentValueLabel: {
                Text("\(Format.duration(seconds: activeSeconds)) of \(Format.duration(seconds: requiredSeconds)) typing")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // Said explicitly, because an empty weak-spots list would otherwise read as
            // "you have no weaknesses" rather than "we don't know yet".
            Text("Weak spots appear once there's enough typing to rank them honestly.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summary: some View {
        HStack(spacing: 16) {
            metric("WPM", state.wpm)
            metric("Accuracy", state.accuracy)
            metric("Keys", state.totalPresses)
            metric("Active", state.activeTime)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(.body, design: .monospaced).weight(.medium))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var weakSpots: some View {
        if !state.weakKeys.isEmpty {
            section(
                "Weak keys",
                caption: "Slowest relative to your own \(state.baselineP95) baseline · costing \(state.totalTimeCost) today"
            ) {
                ForEach(state.weakKeys) { row in rowView(row) }
            }
        }
        if !state.weakBigrams.isEmpty {
            section("Weak transitions", caption: "Key pairs that cost you the most time") {
                ForEach(state.weakBigrams) { row in rowView(row) }
            }
        }
        if !state.topApps.isEmpty {
            section("Where you type", caption: nil) {
                ForEach(state.topApps) { app in
                    HStack {
                        Text(app.name).font(.caption)
                        Spacer()
                        Text(app.presses).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(Format.percentage(app.share))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func rowView(_ row: MenuViewState.Row) -> some View {
        HStack(spacing: 6) {
            Text(row.label)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .frame(minWidth: 42, alignment: .leading)
            if row.isSameFinger {
                Image(systemName: "hand.raised")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    // Flagged rather than hidden: it explains the row without implying the
                    // user should grind it away.
                    .help("Same finger twice — inherently slow, not worth drilling")
            }
            Spacer()
            if let correctionRate = row.correctionRate {
                Text(correctionRate)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
                    .help("Backspaced after this key")
            }
            Text(row.excess)
                .font(.caption2.monospaced())
                .foregroundStyle(.orange)
                .frame(width: 52, alignment: .trailing)
                .help("Slower than your baseline, per press")
            Text(row.timeCost)
                .font(.caption2.monospaced())
                .frame(width: 46, alignment: .trailing)
                .help("Total time this cost you today")
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        caption: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold))
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.diagnostics.hasAnything {
                DisclosureGroup(isExpanded: $showingDiagnostics) {
                    VStack(alignment: .leading, spacing: 2) {
                        diagnosticRow("Injected by software", state.diagnostics.rejectedSynthetic,
                                      help: "Keystrokes posted by other apps — text expanders, automation, AI tools typing for you. Excluded from your WPM.")
                        diagnosticRow("Dropped in password fields", state.diagnostics.rejectedSecureInput,
                                      help: "Never recorded at all.")
                        diagnosticRow("Key autorepeat", state.diagnostics.rejectedAutorepeat, help: "Held keys aren't typing.")
                        diagnosticRow("Pauses ignored", state.diagnostics.discardedPauses,
                                      help: "Gaps too long to be finger movement — thinking, not typing.")
                        diagnosticRow("Practice typing", state.diagnostics.rejectedSelfPractice,
                                      help: "Typed inside Fumble's own practice window. Kept out of your daily stats so drills can't distort them.")
                    }
                    .padding(.top, 3)
                } label: {
                    Text("What was excluded").font(.caption2)
                }
                .font(.caption2)
            }

            HStack(spacing: 8) {
                Button("Show data") { coordinator.revealDataInFinder() }
                    .help(coordinator.dataDirectory.path)
                Button(confirmingDelete ? "Really delete?" : "Delete all") {
                    if confirmingDelete {
                        coordinator.deleteAllData()
                        confirmingDelete = false
                    } else {
                        confirmingDelete = true
                    }
                }
                .foregroundStyle(confirmingDelete ? .red : .primary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .font(.caption)
            .buttonStyle(.borderless)

            Text("\(Format.bytes(coordinator.bytesOnDisk)) on disk · local only, no account, no network")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func diagnosticRow(_ label: String, _ value: String, help: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospaced()
        }
        .font(.caption2)
        .help(help)
    }
}
