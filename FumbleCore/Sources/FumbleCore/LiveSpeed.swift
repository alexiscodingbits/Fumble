import Foundation

/// A rolling, instantaneous typing-speed estimate — "how fast are you going *right now*", as
/// opposed to the day's average.
///
/// Holds only a short trailing window of keystroke *timestamps* in memory (never persisted,
/// never characters), so it costs nothing and raises no privacy question beyond what the tap
/// already sees. When you stop typing it reports nil rather than decaying to a misleading zero.
public struct LiveSpeed: Sendable {
    /// The trailing window the estimate is computed over. Long enough to be steady, short
    /// enough to feel live.
    public var windowSeconds: Double
    /// If the most recent keystroke is older than this, you've stopped — report nil (idle)
    /// rather than a stale number.
    public var idleGapSeconds: Double

    private var timestamps: [Double] = []

    public init(windowSeconds: Double = 8, idleGapSeconds: Double = 2) {
        self.windowSeconds = windowSeconds
        self.idleGapSeconds = idleGapSeconds
    }

    public mutating func record(timestamp: Double) {
        timestamps.append(timestamp)
        trim(now: timestamp)
    }

    private mutating func trim(now: Double) {
        let cutoff = now - windowSeconds
        // Drop everything older than the window in one shot.
        if let firstFresh = timestamps.firstIndex(where: { $0 >= cutoff }) {
            if firstFresh > 0 { timestamps.removeFirst(firstFresh) }
        } else {
            timestamps.removeAll(keepingCapacity: true)
        }
    }

    /// Current speed in WPM, or nil when idle / not enough recent keys to be meaningful.
    ///
    /// Rate is measured across the span the keys were *actually* typed (first to last in the
    /// window), not first-to-now, so the gap between your last keystroke and this refresh tick
    /// doesn't drag the number down while you're still going. `count - 1` intervals over that
    /// span — the fencepost that avoids inflating a short burst.
    public func wordsPerMinute(now: Double) -> Double? {
        guard timestamps.count >= 3,
              let first = timestamps.first,
              let last = timestamps.last,
              now - last <= idleGapSeconds
        else { return nil }

        let span = last - first
        guard span > 0 else { return nil }
        return (Double(timestamps.count - 1) / 5.0) / (span / 60.0)
    }

    public mutating func reset() {
        timestamps.removeAll(keepingCapacity: true)
    }
}

/// A window of days to aggregate stats over. Drives the "average over…" selector.
public enum Timeframe: String, CaseIterable, Sendable, Identifiable {
    case today
    case week
    case month
    case all

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "30 days"
        case .all: "All time"
        }
    }

    /// Inclusive [start, end] of local midnights covered. `end` is today.
    public func range(now: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let end = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return (end, end)
        case .week:
            return (calendar.date(byAdding: .day, value: -6, to: end) ?? end, end)
        case .month:
            return (calendar.date(byAdding: .day, value: -29, to: end) ?? end, end)
        case .all:
            return (.distantPast, end)
        }
    }
}
