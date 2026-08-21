import FumbleCore
import Foundation

// Inspection tool. Two jobs: let a developer see the aggregates without opening the UI, and
// let a sceptical user dump exactly what is stored so they can check the privacy claim
// themselves. `--json` prints the day file verbatim.

let arguments = Array(CommandLine.arguments.dropFirst())
let wantsJSON = arguments.contains("--json")
let wantsAll = arguments.contains("--all")
let store = StatsStore.default()

func day(named name: String, stats: DayStats) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    print("── \(formatter.string(from: stats.date)) ──")
    print("  presses      \(stats.totalPresses)")
    print("  corrections  \(stats.totalCorrections)")
    print("  active       \(String(format: "%.1f", stats.activeSeconds))s")
    if let wpm = stats.wordsPerMinute() {
        print("  wpm          \(String(format: "%.1f", wpm))")
    } else {
        print("  wpm          (not enough active time)")
    }
    if let accuracy = stats.accuracy() {
        print("  accuracy     \(String(format: "%.2f%%", accuracy * 100))")
    }
    print("  keys tracked \(stats.keys.count), bigrams \(stats.bigrams.count), apps \(stats.apps.count)")
    print("  excluded     synthetic=\(stats.rejectedSynthetic) secure=\(stats.rejectedSecureInput) autorepeat=\(stats.rejectedAutorepeat) pauses=\(stats.discardedPauses) selfPractice=\(stats.rejectedSelfPractice)")

    // Motor-filter breakdown: which reference tier decided each accepted reach. If most
    // samples are still 'global' or 'coldStart' the per-transition idea isn't paying off yet;
    // a healthy long-running day should be dominated by 'transition' and 'key'.
    let motor = stats.motorClassification
    if motor.total > 0 {
        func pct(_ value: UInt64) -> String { String(format: "%.0f%%", Double(value) / Double(motor.total) * 100) }
        print("  motor by     transition=\(motor.transition) (\(pct(motor.transition)))  key=\(motor.key) (\(pct(motor.key)))  global=\(motor.global) (\(pct(motor.global)))  coldStart=\(motor.coldStart) (\(pct(motor.coldStart)))")
    }

    guard let analysis = WeakSpots.analyse(stats) else {
        print("  weak spots   (not enough data yet)")
        return
    }
    print("  baseline p95 \(Int(analysis.baselineP95))ms")
    print("  weak keys:")
    for spot in analysis.keys.prefix(10) {
        print(String(
            format: "    %-8@ n=%-6d p95=%4dms  +%3dms  cost=%.2fs",
            spot.label as NSString, Int(spot.samples), Int(spot.p95),
            Int(spot.excessLatencyMilliseconds), spot.timeCostSeconds
        ))
    }
    print("  weak transitions:")
    for spot in analysis.bigrams.prefix(10) {
        let marker = spot.isSameFingerBigram ? " (same finger)" : ""
        print(String(
            format: "    %-8@ n=%-6d p95=%4dms  +%3dms  cost=%.2fs%@",
            spot.label as NSString, Int(spot.samples), Int(spot.p95),
            Int(spot.excessLatencyMilliseconds), spot.timeCostSeconds, marker as NSString
        ))
    }
}

let today = Calendar.current.startOfDay(for: Date())
let days = wantsAll ? store.loadAll() : [(try? store.load(today)) ?? nil].compactMap { $0 }

if days.isEmpty {
    print("No data in \(store.directory.path)")
    exit(0)
}

if wantsJSON {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    for stats in days {
        if let data = try? encoder.encode(stats), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }
} else {
    print("Fumble — \(store.directory.path)")
    print("")
    for stats in days {
        day(named: "", stats: stats)
        print("")
    }
}
