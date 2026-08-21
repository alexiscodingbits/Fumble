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

                    if let day, let analysis = WeakSpots.analyse(day) {
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
        VStack(alignment: .leading, spacing: 6) {
            // Title on the left, column headers aligned over their columns.
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("slow reach").font(.caption2).foregroundStyle(.tertiary)
                    .frame(width: 80, alignment: .trailing)
                    .help("Your 95th-percentile reach time for this — how slow your slower hits are")
                Text("time lost").font(.caption2).foregroundStyle(.tertiary)
                    .frame(width: 80, alignment: .trailing)
                    .help("Total time this cost you today versus your own baseline")
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0).font(.system(.body, design: .monospaced).weight(.medium))
                        .frame(minWidth: 60, alignment: .leading)
                    Spacer()
                    Text("\(row.2)ms").font(.caption.monospaced()).foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    Text(durationString(row.1)).font(.caption.monospaced())
                        .frame(width: 80, alignment: .trailing)
                }
            }
        }
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
