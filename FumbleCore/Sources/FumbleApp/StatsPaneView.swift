import FumbleCore
import SwiftUI

/// The stats pane: a speed heatmap of your keyboard plus your ranked weak spots — keybr's
/// profile page, but built from your real all-day typing rather than in-app drills.
struct StatsPaneView: View {
    let coordinator: AppCoordinator

    var body: some View {
        let day = coordinator.statsSnapshot()
        let speeds = perKeyWPM(day)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your keyboard").font(.title2.weight(.semibold))

                if speeds.isEmpty {
                    placeholder
                } else {
                    Text("Speed per key — green is fast, red is slow, relative to your own range.")
                        .font(.caption).foregroundStyle(.secondary)
                    VirtualKeyboardView(focusKeyCode: nil, keyColor: { heatColor($0, speeds: speeds) })
                        .frame(maxWidth: .infinity)

                    if let day {
                        whereYouType(day)
                    }
                    if let day, let analysis = WeakSpots.analyse(day) {
                        // Side by side and stripped to the one number that matters (time lost);
                        // the per-press latency lives in a tooltip. Two visible columns of
                        // numbers was information overload.
                        HStack(alignment: .top, spacing: 32) {
                            weakList("Weak keys", rows: analysis.keys.prefix(6).map {
                                ($0.label, $0.timeCostSeconds, Int($0.p95))
                            })
                            weakList("Weak transitions", rows: analysis.drillable.compactMap { spot in
                                if case .bigram = spot.target {
                                    return (spot.label, spot.timeCostSeconds, Int(spot.p95))
                                }
                                return nil
                            }.prefix(6).map { $0 })
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not enough data yet").font(.headline)
            Text("Keep typing normally — the heatmap and rankings fill in as Fumble learns your keyboard.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func weakList(_ title: String, rows: [(String, Double, Int)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("time lost").font(.caption2).foregroundStyle(.tertiary)
                    .help("Total time this cost you versus your own baseline")
            }
            .padding(.bottom, 2)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0).font(.system(.callout, design: .monospaced).weight(.medium))
                    Spacer(minLength: 16)
                    Text(durationString(row.1)).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                // The per-press figure is detail, not headline — hover for it.
                .help("Typically \(row.2)ms per press at your slower end")
            }
        }
        .frame(maxWidth: 240, alignment: .leading)
    }

    /// Per-app breakdown — moved here from the dropdown: insight detail, not dashboard material.
    private func whereYouType(_ day: DayStats) -> some View {
        let total = Double(max(day.totalPresses, 1))
        let apps = day.apps
            .sorted { $0.value.presses > $1.value.presses }
            .prefix(6)
        return VStack(alignment: .leading, spacing: 3) {
            Text("Where you type").font(.headline).padding(.bottom, 2)
            ForEach(Array(apps), id: \.key) { bundleID, stat in
                HStack {
                    Text(bundleID.split(separator: ".").last.map(String.init) ?? bundleID)
                        .font(.callout)
                    Spacer(minLength: 16)
                    Text("\(Int((Double(stat.presses) / total * 100).rounded()))%")
                        .font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                .help("\(stat.presses) keystrokes")
            }
        }
        .frame(maxWidth: 240, alignment: .leading)
    }

    private func durationString(_ seconds: Double) -> String {
        if seconds < 1 { return "\(Int((seconds * 1000).rounded()))ms" }
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        return String(format: "%dm %02ds", Int(seconds) / 60, Int(seconds) % 60)
    }

    // MARK: - Heatmap

    private func perKeyWPM(_ day: DayStats?) -> [Int: Double] {
        guard let day else { return [:] }
        var result: [Int: Double] = [:]
        for key in KeyIdentity.alphabetByFrequency {
            if let stat = day.keys[key.keyCode], let wpm = stat.estimatedWPM() {
                result[key.keyCode] = wpm
            }
        }
        return result
    }

    private func heatColor(_ keyCode: Int, speeds: [Int: Double]) -> Color {
        guard let wpm = speeds[keyCode] else { return SkillColor.locked }
        let values = speeds.values
        let low = values.min() ?? wpm
        let high = values.max() ?? wpm
        guard high > low else { return SkillColor.color(0.5) }
        return SkillColor.color((wpm - low) / (high - low)).opacity(0.85)
    }
}
