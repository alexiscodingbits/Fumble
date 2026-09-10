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
        // The trend chart: the one "how am I doing" picture, replacing rows of timings.
        if coordinator.wpmTrend.count >= 2 {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Speed").font(.caption.weight(.semibold))
                    Spacer()
                    if let latest = coordinator.wpmTrend.last {
                        // Today drops out of the trend until it has enough active typing, so
                        // the latest point isn't necessarily today — don't mislabel it.
                        Text(Calendar.current.isDateInToday(latest.date)
                             ? "today \(Int(latest.wpm.rounded())) wpm"
                             : "\(Int(latest.wpm.rounded())) wpm")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
                TrendChart(points: coordinator.wpmTrend)
                    .frame(height: 72)
            }
        }

        // Weak spots as plain chips — what to work on, without the wall of milliseconds.
        // The numbers still exist in the Stats pane for anyone who wants them.
        if !state.weakKeys.isEmpty || !state.weakBigrams.isEmpty {
            section("Needs work", caption: nil) {
                chipRow(labels: state.weakKeys.prefix(5).map(\.label)
                        + state.weakBigrams.prefix(4).map { $0.label.replacingOccurrences(of: "Space", with: "␣") })
            }
        }

        // "Where you type" lives in the Stats pane now — insight detail, not dashboard material.
    }

    private func chipRow(labels: [String]) -> some View {
        // One line — 5 key chips + 4 pair chips fit the popover comfortably at caption size.
        HStack(spacing: 4) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.caption.monospaced().weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
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
