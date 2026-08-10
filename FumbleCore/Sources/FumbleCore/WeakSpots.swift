import Foundation

/// One thing you are bad at, with the evidence for why we think so.
public struct WeakSpot: Equatable, Sendable, Identifiable {
    public enum Target: Equatable, Sendable {
        case key(KeyIdentity)
        case bigram(BigramIdentity)
    }

    public let target: Target
    /// Presses (key) or occurrences (bigram) observed today.
    public let samples: UInt64
    /// This target's 95th-percentile latency, ms.
    public let p95: Double
    /// Your own all-keys p95, ms — the baseline this is judged against.
    public let baselineP95: Double
    /// ms lost per press versus baseline. Always > 0 for a weak spot.
    public let excessLatencyMilliseconds: Double
    /// Total time this target cost you today, in seconds. `excess × samples`.
    ///
    /// This is the ranking metric and it is deliberately the interpretable one: "`;` cost
    /// you 4.2 seconds today" is a claim a user can accept or reject. A composite score
    /// with tuned weights would rank better on paper and be impossible to argue with.
    public let timeCostSeconds: Double
    /// Fraction of presses immediately backspaced, when there were enough presses to tell.
    public let correctionRate: Double?

    public var id: String {
        switch target {
        case .key(let key): "k\(key.keyCode)"
        case .bigram(let bigram): "b\(bigram.storageKey)"
        }
    }

    public var label: String {
        switch target {
        case .key(let key): key.label
        case .bigram(let bigram): bigram.label
        }
    }

    /// True when the culprit is one finger doing two jobs in a row. Worth flagging in the UI
    /// rather than drilling: same-finger bigrams are slower for everyone, and no amount of
    /// practice makes them fast. Telling someone to grind `ed` is telling them to fix their hand.
    public var isSameFingerBigram: Bool {
        switch target {
        case .key: false
        case .bigram(let bigram): bigram.isSameFinger
        }
    }
}

public struct WeakSpotOptions: Sendable {
    /// Minimum presses before a key is eligible. Below this, p95 is one bad sample.
    public var minimumKeySamples: UInt64 = 40
    /// Bigrams need a lower bar than keys: there are far more of them, so each is rarer.
    public var minimumBigramSamples: UInt64 = 15
    /// Ignore targets whose excess over baseline is under this. Everything is a few ms slower
    /// than the median; without a floor the list is noise sorted by frequency.
    public var minimumExcessMilliseconds: Double = 8
    /// Total active typing required before we'll rank anything at all.
    public var minimumActiveSeconds: Double = 120
    /// Distinct keys that must have enough samples before a baseline is meaningful. A median
    /// over three keys is not a baseline.
    public var minimumBaselineKeys: Int = 8

    public init() {}
}

/// Ranks what to practise, using the user as their own control.
///
/// The baseline is **your** all-keys p95, not an absolute target. A 40 WPM typist and a 110
/// WPM typist have completely different latency distributions; judged against a fixed
/// threshold the slower typist's entire keyboard is "weak", which is useless advice.
public enum WeakSpots {

    /// The latency a *typical key* costs this user: the median of per-key p95s, with every
    /// eligible key counting once.
    ///
    /// The obvious alternative — the p95 of all keystrokes pooled together — is wrong, and
    /// wrong in the specific way that matters most. Pooling weights each key by how often you
    /// press it, so a high-volume key *drags the baseline towards itself* and masks its own
    /// slowness. Space, `E` and `;` are exactly the keys that are both frequent and worth
    /// fixing, and pooling is blind to them. Weighting each key equally removes that feedback
    /// loop. (Caught by `ranksByTimeCost` — a mildly-slow key making up 40% of keystrokes
    /// scored zero excess against a pooled baseline.)
    ///
    /// Nil when too few keys have enough samples to make a median mean anything.
    static func baselineP95(
        for day: DayStats,
        options: WeakSpotOptions
    ) -> Double? {
        let perKeyP95 = day.keys
            .compactMap { keyCode, stat -> Double? in
                guard KeyIdentity(keyCode: keyCode).isTypingKey,
                      stat.latency.total >= options.minimumKeySamples
                else { return nil }
                return stat.latency.p95
            }
            .sorted()

        guard perKeyP95.count >= options.minimumBaselineKeys else { return nil }

        let middle = perKeyP95.count / 2
        return perKeyP95.count.isMultiple(of: 2)
            ? (perKeyP95[middle - 1] + perKeyP95[middle]) / 2
            : perKeyP95[middle]
    }

    /// Nil when there isn't yet enough data to say anything honest. The caller should show a
    /// "still learning" state rather than an empty list — an empty list reads as "you have no
    /// weaknesses", which is a lie.
    public static func analyse(
        _ day: DayStats,
        options: WeakSpotOptions = WeakSpotOptions()
    ) -> Analysis? {
        guard day.activeSeconds >= options.minimumActiveSeconds,
              let baseline = baselineP95(for: day, options: options)
        else { return nil }

        var keySpots: [WeakSpot] = []
        for (keyCode, stat) in day.keys {
            let key = KeyIdentity(keyCode: keyCode)
            guard key.isTypingKey,
                  stat.latency.total >= options.minimumKeySamples,
                  let p95 = stat.latency.p95
            else { continue }

            let excess = p95 - baseline
            guard excess >= options.minimumExcessMilliseconds else { continue }

            keySpots.append(WeakSpot(
                target: .key(key),
                samples: stat.latency.total,
                p95: p95,
                baselineP95: baseline,
                excessLatencyMilliseconds: excess,
                timeCostSeconds: (excess * Double(stat.latency.total)) / 1000,
                correctionRate: stat.correctionRate()
            ))
        }

        var bigramSpots: [WeakSpot] = []
        for (storageKey, stat) in day.bigrams {
            guard let bigram = BigramIdentity(storageKey: storageKey),
                  stat.latency.total >= options.minimumBigramSamples,
                  let p95 = stat.latency.p95
            else { continue }

            let excess = p95 - baseline
            guard excess >= options.minimumExcessMilliseconds else { continue }

            bigramSpots.append(WeakSpot(
                target: .bigram(bigram),
                samples: stat.latency.total,
                p95: p95,
                baselineP95: baseline,
                excessLatencyMilliseconds: excess,
                timeCostSeconds: (excess * Double(stat.latency.total)) / 1000,
                correctionRate: nil
            ))
        }

        // Sort by cost, then by id so equal-cost entries don't reshuffle between refreshes.
        let byCost: (WeakSpot, WeakSpot) -> Bool = {
            $0.timeCostSeconds == $1.timeCostSeconds
                ? $0.id < $1.id
                : $0.timeCostSeconds > $1.timeCostSeconds
        }

        return Analysis(
            baselineP95: baseline,
            keys: keySpots.sorted(by: byCost),
            bigrams: bigramSpots.sorted(by: byCost)
        )
    }

    public struct Analysis: Equatable, Sendable {
        public let baselineP95: Double
        public let keys: [WeakSpot]
        public let bigrams: [WeakSpot]

        /// Total time lost to weak keys today, in seconds. The headline number.
        public var totalKeyTimeCostSeconds: Double {
            keys.reduce(0) { $0 + $1.timeCostSeconds }
        }

        /// Weak spots worth drilling, excluding same-finger bigrams (anatomy, not skill).
        public var drillable: [WeakSpot] {
            (keys + bigrams)
                .filter { !$0.isSameFingerBigram }
                .sorted { $0.timeCostSeconds > $1.timeCostSeconds }
        }

        /// Keys ranked by how often you backspace them rather than how slowly you hit them.
        /// A separate list because accuracy and speed are separate problems with separate fixes.
        public func mostCorrected(in day: DayStats, limit: Int = 5) -> [(KeyIdentity, Double)] {
            day.keys
                .compactMap { keyCode, stat -> (KeyIdentity, Double)? in
                    let key = KeyIdentity(keyCode: keyCode)
                    guard key.isTypingKey, let rate = stat.correctionRate(), rate > 0 else { return nil }
                    return (key, rate)
                }
                .sorted { $0.1 == $1.1 ? $0.0.keyCode < $1.0.keyCode : $0.1 > $1.1 }
                .prefix(limit)
                .map { $0 }
        }
    }
}
