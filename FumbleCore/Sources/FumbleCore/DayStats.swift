import Foundation

/// Per-key aggregate for one day. Counters and a latency histogram — never content.
public struct KeyStat: Codable, Equatable, Sendable {
    /// Times this key was pressed (autorepeat and synthetic events excluded).
    public var presses: UInt64 = 0
    /// Times a press of this key was immediately undone by a backspace. Our best available
    /// proxy for "you got this wrong"; see `StatsRecorder` for the caveats.
    public var corrections: UInt64 = 0
    /// Time from the *previous* keypress to this one — i.e. the cost of reaching this key.
    public var latency = LatencyHistogram()

    public init() {}

    /// Correction rate in 0...1. Nil below `minimum` presses, where the ratio is noise.
    public func correctionRate(minimumPresses minimum: UInt64 = 20) -> Double? {
        guard presses >= minimum else { return nil }
        return Double(corrections) / Double(presses)
    }

    mutating func merge(_ other: KeyStat) {
        presses += other.presses
        corrections += other.corrections
        latency.merge(other.latency)
    }
}

/// Per-bigram aggregate. `latency` is the time from the first key to the second.
public struct BigramStat: Codable, Equatable, Sendable {
    public var count: UInt64 = 0
    public var latency = LatencyHistogram()

    public init() {}

    mutating func merge(_ other: BigramStat) {
        count += other.count
        latency.merge(other.latency)
    }
}

/// Per-application aggregate, keyed by bundle identifier.
public struct AppStat: Codable, Equatable, Sendable {
    public var presses: UInt64 = 0
    public var corrections: UInt64 = 0
    public var activeSeconds: Double = 0

    public init() {}

    mutating func merge(_ other: AppStat) {
        presses += other.presses
        corrections += other.corrections
        activeSeconds += other.activeSeconds
    }
}

/// Everything Fumble knows about one calendar day.
///
/// This struct **is** the on-disk format (one JSON file per day). It contains no ordered
/// sequence of keystrokes and no characters — only counts, histograms, and bundle IDs.
/// Nothing here can be turned back into text.
public struct DayStats: Codable, Equatable, Sendable {

    /// Bumped when the shape changes incompatibly, so the loader can migrate or discard.
    /// v2: added `motorLatency` (running global motor histogram) and `motorClassification`
    /// (per-tier diagnostics) when the flat latency cutoff became the adaptive `MotorFilter`.
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int = DayStats.currentSchemaVersion
    /// Midnight, local time, of the day this covers.
    public var date: Date

    public var keys: [Int: KeyStat] = [:]
    public var bigrams: [String: BigramStat] = [:]
    public var apps: [String: AppStat] = [:]

    /// Every accepted motor sample across all keys, pooled. Maintained incrementally so the
    /// `MotorFilter` has a cheap personal-global median to fall back on, and so `overallLatency`
    /// is a lookup rather than a merge of every key histogram on each call.
    public var motorLatency = LatencyHistogram()
    /// How motor samples were classified, by reference tier. Tuning/validation only.
    public var motorClassification = MotorFilterCounts()

    /// Every typing key pressed, including ones excluded from latency stats.
    public var totalPresses: UInt64 = 0
    public var totalCorrections: UInt64 = 0
    /// Wall-clock seconds spent actively typing — the denominator for honest WPM.
    /// Gaps longer than `RecorderConfig.idleThresholdSeconds` are not counted.
    public var activeSeconds: Double = 0

    // Diagnostics. Surfaced in the UI so the numbers are auditable rather than magic.
    /// Events rejected because they were injected by software, not typed. See `EventTap`.
    public var rejectedSynthetic: UInt64 = 0
    /// Events dropped because a secure-input field (password) had focus.
    public var rejectedSecureInput: UInt64 = 0
    /// Events dropped as OS autorepeat from a held key.
    public var rejectedAutorepeat: UInt64 = 0
    /// Latency samples discarded as thinking pauses rather than motor movement.
    public var discardedPauses: UInt64 = 0

    public init(date: Date) {
        self.date = date
    }

    // MARK: - Derived

    public subscript(key: KeyIdentity) -> KeyStat? { keys[key.keyCode] }
    public subscript(bigram: BigramIdentity) -> BigramStat? { bigrams[bigram.storageKey] }

    /// Words per minute over active time, using the conventional 5-characters-per-word rule.
    /// Nil until there's enough active time for the figure to mean anything.
    public func wordsPerMinute(minimumActiveSeconds: Double = 30) -> Double? {
        // `activeSeconds > 0` is a separate guard from the minimum: a caller passing a
        // minimum of 0 (tests, or a "show me anything" mode) would otherwise divide by zero
        // and hand NaN to the formatter.
        guard activeSeconds > 0, activeSeconds >= minimumActiveSeconds else { return nil }
        return (Double(totalPresses) / 5.0) / (activeSeconds / 60.0)
    }

    /// Share of keypresses that were *not* immediately backspaced, in 0...1.
    public func accuracy(minimumPresses: UInt64 = 100) -> Double? {
        guard totalPresses >= minimumPresses else { return nil }
        return 1.0 - (Double(totalCorrections) / Double(totalPresses))
    }

    /// Latency across every accepted motor sample. Identical to merging every key histogram,
    /// but maintained incrementally, so it's an O(1) read instead of an O(keys) merge.
    ///
    /// Falls back to the merge for pre-v2 day files, which predate `motorLatency` and so have
    /// an empty one — their latency lives only in the per-key histograms.
    public var overallLatency: LatencyHistogram {
        motorLatency.total > 0 ? motorLatency : LatencyHistogram.merging(keys.values.map(\.latency))
    }

    public func merged(with other: DayStats) -> DayStats {
        var result = self
        for (code, stat) in other.keys {
            result.keys[code, default: KeyStat()].merge(stat)
        }
        for (storageKey, stat) in other.bigrams {
            result.bigrams[storageKey, default: BigramStat()].merge(stat)
        }
        for (bundleID, stat) in other.apps {
            result.apps[bundleID, default: AppStat()].merge(stat)
        }
        result.motorLatency.merge(other.motorLatency)
        result.motorClassification.merge(other.motorClassification)
        result.totalPresses += other.totalPresses
        result.totalCorrections += other.totalCorrections
        result.activeSeconds += other.activeSeconds
        result.rejectedSynthetic += other.rejectedSynthetic
        result.rejectedSecureInput += other.rejectedSecureInput
        result.rejectedAutorepeat += other.rejectedAutorepeat
        result.discardedPauses += other.discardedPauses
        return result
    }

    public static func merging(_ days: [DayStats], date: Date) -> DayStats {
        var result = DayStats(date: date)
        for day in days { result = result.merged(with: day) }
        return result
    }

    /// Drops rare bigrams before the day is written to disk.
    ///
    /// This does double duty and both jobs matter:
    ///
    /// 1. **Privacy.** A bigram table is a partial n-gram model of your writing. Rare
    ///    n-grams are the identifying ones — a hand-typed password or an unusual identifier
    ///    shows up as an anomalous low-count entry. Discarding the long tail removes
    ///    precisely the entries that carry recoverable information.
    /// 2. **Size.** Unbounded bigram tables would grow without limit across a long day.
    ///
    /// It costs nothing analytically: a 2-sample latency estimate was never usable.
    public mutating func pruneRareBigrams(minimumCount: UInt64) {
        guard minimumCount > 1 else { return }
        bigrams = bigrams.filter { $0.value.count >= minimumCount }
    }
}

// A day file is long-lived data, and fields only ever get *added*. So decoding is written to
// tolerate any missing key by defaulting it, rather than failing the whole file — which is what
// broke pre-v2 files when `motorLatency`/`motorClassification` were introduced. `encode` stays
// synthesized. Only `date` is genuinely required.
extension DayStats {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, date, keys, bigrams, apps, motorLatency, motorClassification
        case totalPresses, totalCorrections, activeSeconds
        case rejectedSynthetic, rejectedSecureInput, rejectedAutorepeat, discardedPauses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(date: try container.decode(Date.self, forKey: .date))

        // Pre-v2 files have no schemaVersion? They do (v1 wrote it), but default defensively.
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        keys = try container.decodeIfPresent([Int: KeyStat].self, forKey: .keys) ?? [:]
        bigrams = try container.decodeIfPresent([String: BigramStat].self, forKey: .bigrams) ?? [:]
        apps = try container.decodeIfPresent([String: AppStat].self, forKey: .apps) ?? [:]
        motorLatency = try container.decodeIfPresent(LatencyHistogram.self, forKey: .motorLatency) ?? LatencyHistogram()
        motorClassification = try container.decodeIfPresent(MotorFilterCounts.self, forKey: .motorClassification) ?? MotorFilterCounts()
        totalPresses = try container.decodeIfPresent(UInt64.self, forKey: .totalPresses) ?? 0
        totalCorrections = try container.decodeIfPresent(UInt64.self, forKey: .totalCorrections) ?? 0
        activeSeconds = try container.decodeIfPresent(Double.self, forKey: .activeSeconds) ?? 0
        rejectedSynthetic = try container.decodeIfPresent(UInt64.self, forKey: .rejectedSynthetic) ?? 0
        rejectedSecureInput = try container.decodeIfPresent(UInt64.self, forKey: .rejectedSecureInput) ?? 0
        rejectedAutorepeat = try container.decodeIfPresent(UInt64.self, forKey: .rejectedAutorepeat) ?? 0
        discardedPauses = try container.decodeIfPresent(UInt64.self, forKey: .discardedPauses) ?? 0
    }
}
