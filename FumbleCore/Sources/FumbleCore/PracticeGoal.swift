import Foundation

/// Daily practice goal + streak math. Pure functions over a per-day practiced-seconds table;
/// storage is the app's concern.
///
/// Mirrors keybr's "daily goal": a gentle target, never a limit. The streak definition matters
/// more than it looks: if "streak" died the moment you hadn't practised *today*, it would read 0
/// every morning and punish you before the day started. So today only counts when met, and an
/// unmet today doesn't break yesterday's chain — only a fully missed day does.
public enum PracticeGoal {

    /// Progress toward the goal, clamped 0…1. A zero/negative goal means "off" and reports nil
    /// so the UI can hide the ring rather than show a meaningless full bar.
    public static func progress(practicedSeconds: Double, goalSeconds: Double) -> Double? {
        guard goalSeconds > 0 else { return nil }
        guard practicedSeconds > 0 else { return 0 }
        return min(practicedSeconds / goalSeconds, 1)
    }

    /// Consecutive days meeting the goal, ending today (if met) or yesterday (if today is still
    /// in progress). Keys of `practicedSecondsByDay` must be local-midnight dates.
    public static func streak(
        practicedSecondsByDay: [Date: Double],
        goalSeconds: Double,
        today: Date,
        calendar: Calendar = .current
    ) -> Int {
        guard goalSeconds > 0 else { return 0 }
        let todayStart = calendar.startOfDay(for: today)

        func met(_ day: Date) -> Bool {
            (practicedSecondsByDay[day] ?? 0) >= goalSeconds
        }

        // Anchor: today when met, else yesterday — an in-progress today never breaks the chain.
        var anchor = todayStart
        if !met(anchor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: anchor) else { return 0 }
            anchor = yesterday
        }

        var count = 0
        var day = anchor
        while met(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
