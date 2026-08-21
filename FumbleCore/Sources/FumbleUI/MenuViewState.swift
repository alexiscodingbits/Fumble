import Foundation
import FumbleCore

/// Everything the dropdown renders, computed from a `DayStats` with no SwiftUI involved.
///
/// Keeping this a plain value type means the entire UI's *content* is testable, which matters
/// because SwiftUI views can't be verified headlessly.
public struct MenuViewState: Equatable, Sendable {

    /// What the app is currently able to say. The empty and learning states are distinct on
    /// purpose — "no data" and "not enough data to be honest yet" are different messages.
    public enum Readiness: Equatable, Sendable {
        case needsPermission
        case noData
        case learning(activeSeconds: Double, requiredSeconds: Double)
        case ready
    }

    public let readiness: Readiness
    public let barText: String
    public let wpm: String
    public let accuracy: String
    public let totalPresses: String
    public let activeTime: String
    public let baselineP95: String

    public let weakKeys: [Row]
    public let weakBigrams: [Row]
    public let topApps: [AppRow]

    public let totalTimeCost: String
    public let diagnostics: Diagnostics

    public struct Row: Equatable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let samples: String
        public let p95: String
        public let excess: String
        public let timeCost: String
        public let correctionRate: String?
        /// Flagged in the UI as anatomy rather than skill; see `WeakSpot.isSameFingerBigram`.
        public let isSameFinger: Bool
        public let finger: String?
    }

    public struct AppRow: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let presses: String
        public let share: Double
    }

    public struct Diagnostics: Equatable, Sendable {
        public let rejectedSynthetic: String
        public let rejectedSecureInput: String
        public let rejectedAutorepeat: String
        public let discardedPauses: String
        public let rejectedSelfPractice: String
        /// True when anything was rejected — the UI only shows the section if so, but it must
        /// always be *available*. These counters are how a user audits the WPM figure.
        public let hasAnything: Bool
    }

    public static func build(
        day: DayStats?,
        hasPermission: Bool,
        options: WeakSpotOptions = WeakSpotOptions(),
        rowLimit: Int = 6
    ) -> MenuViewState {
        guard hasPermission else { return placeholder(readiness: .needsPermission) }
        guard let day, day.totalPresses > 0 else { return placeholder(readiness: .noData) }

        let analysis = WeakSpots.analyse(day, options: options)
        let readiness: Readiness = analysis == nil
            ? .learning(activeSeconds: day.activeSeconds, requiredSeconds: options.minimumActiveSeconds)
            : .ready

        let wpmValue = day.wordsPerMinute()
        let accuracyValue = day.accuracy()

        // The bar stays terse — it's a status item, not a dashboard.
        let barText: String = {
            guard let wpmValue else { return "—" }
            return "\(Int(wpmValue.rounded())) wpm"
        }()

        let totalPresses = day.totalPresses

        return MenuViewState(
            readiness: readiness,
            barText: barText,
            wpm: Format.wpm(wpmValue),
            accuracy: Format.accuracy(accuracyValue),
            totalPresses: Format.count(totalPresses),
            activeTime: Format.duration(seconds: day.activeSeconds),
            baselineP95: Format.milliseconds(analysis?.baselineP95),
            weakKeys: (analysis?.keys ?? []).prefix(rowLimit).map { row(for: $0) },
            weakBigrams: (analysis?.bigrams ?? []).prefix(rowLimit).map { row(for: $0) },
            topApps: appRows(day: day, limit: rowLimit),
            totalTimeCost: Format.duration(seconds: analysis?.totalKeyTimeCostSeconds ?? 0),
            diagnostics: Diagnostics(
                rejectedSynthetic: Format.count(day.rejectedSynthetic),
                rejectedSecureInput: Format.count(day.rejectedSecureInput),
                rejectedAutorepeat: Format.count(day.rejectedAutorepeat),
                discardedPauses: Format.count(day.discardedPauses),
                rejectedSelfPractice: Format.count(day.rejectedSelfPractice),
                hasAnything: day.rejectedSynthetic + day.rejectedSecureInput
                    + day.rejectedAutorepeat + day.discardedPauses + day.rejectedSelfPractice > 0
            )
        )
    }

    static func row(for spot: WeakSpot) -> Row {
        let finger: String? = {
            switch spot.target {
            case .key(let key): key.homeFinger?.displayName
            case .bigram: nil
            }
        }()
        return Row(
            id: spot.id,
            label: spot.label,
            samples: Format.count(spot.samples),
            p95: Format.milliseconds(spot.p95),
            excess: "+\(Format.milliseconds(spot.excessLatencyMilliseconds))",
            timeCost: Format.duration(seconds: spot.timeCostSeconds),
            correctionRate: spot.correctionRate.map { Format.percentage($0) },
            isSameFinger: spot.isSameFingerBigram,
            finger: finger
        )
    }

    static func appRows(day: DayStats, limit: Int) -> [AppRow] {
        let total = Double(max(day.totalPresses, 1))
        return day.apps
            .sorted { $0.value.presses == $1.value.presses ? $0.key < $1.key : $0.value.presses > $1.value.presses }
            .prefix(limit)
            .map { bundleID, stat in
                AppRow(
                    id: bundleID,
                    name: Format.appName(bundleID: bundleID),
                    presses: Format.count(stat.presses),
                    share: Double(stat.presses) / total
                )
            }
    }

    static func placeholder(readiness: Readiness) -> MenuViewState {
        MenuViewState(
            readiness: readiness,
            barText: "—",
            wpm: "—", accuracy: "—", totalPresses: "0",
            activeTime: "—", baselineP95: "—",
            weakKeys: [], weakBigrams: [], topApps: [],
            totalTimeCost: "—",
            diagnostics: Diagnostics(
                rejectedSynthetic: "0", rejectedSecureInput: "0",
                rejectedAutorepeat: "0", discardedPauses: "0",
                rejectedSelfPractice: "0", hasAnything: false
            )
        )
    }
}
