import Foundation

/// Decides whether the gap before a keystroke was a *motor* event (your finger reaching the
/// key — the thing worth measuring) or a *think* (you deciding what to type — noise we must
/// throw out before it poisons the stats).
///
/// The naive version of this is a single global cutoff: "anything over 600ms is a think."
/// That's wrong in one specific, damaging way — it's the *same* number for everyone and for
/// every key. A fast typist's genuine slow reach is well under a slow typist's genuine fast
/// one, so a fixed line either lets thinks through (too loose) or discards real reaches (too
/// tight). Either way you end up drilling people on keys that were never actually slow.
///
/// So the threshold is learned, per transition, per person, from data we already collect:
///
///   threshold = clamp(k × your-own-median-for-this-transition, floor, ceiling)
///
/// A gap 1.2× your usual `t→h` is a real reach and counts. A gap 5× your usual is a think and
/// is dropped. Everything is relative to *you*, and every decision is explainable in one
/// sentence ("discarded because it was 5× slower than your usual for this key pair") — no
/// training data, no model file, no black box.
///
/// **Why the median is safe to compute from contaminated data.** The reference median is taken
/// over samples that were *already accepted as motor* (see `StatsRecorder`), so the reference
/// is clean by construction. And even a raw median would be robust: a minority of huge
/// think-pauses barely move a median (unlike a mean), which is exactly why we use it.
public struct MotorFilter: Sendable {

    public struct Config: Sendable, Equatable {
        /// How many times your own median a gap may be and still count as a reach. Right-skewed
        /// typing latencies put a genuine slow reach around 2–2.5× the median, so 4× leaves
        /// headroom for real reaches while cutting thinks, which start well above that.
        public var medianMultiple: Double = 4.0
        /// The threshold never drops below this, so a very fast typist (tiny median) doesn't get
        /// a pathologically tight cutoff that rejects every slightly-slow-but-real keystroke.
        public var floorMilliseconds: Double = 250
        /// Nothing above this is ever a motor sample, whatever the median says. A hard safety net.
        public var ceilingMilliseconds: Double = 3_000
        /// Used before there's any personal data to learn from — day one, first keystrokes.
        public var coldStartCutoffMilliseconds: Double = 600

        /// Samples a *transition* needs before its own median is trusted. Low, because a
        /// transition is specific: 25 clean samples of `t→h` is a meaningful median.
        public var minimumTransitionSamples: UInt64 = 25
        /// Samples a *key* needs before its median is trusted (used when the transition is too rare).
        public var minimumKeySamples: UInt64 = 50
        /// Samples your *overall* typing needs before the personal-global median is trusted. The
        /// fastest reference to fill, so it takes over from the flat cold-start cutoff quickly.
        public var minimumGlobalSamples: UInt64 = 40

        public init() {}
    }

    public var config: Config
    public init(config: Config = Config()) { self.config = config }

    /// Which reference the decision was based on. Surfaced as a diagnostic so that, with real
    /// data, we can see whether per-transition references are actually kicking in or whether
    /// we're mostly still leaning on the global fallback — the thing that tells us if the whole
    /// per-transition idea is even earning its keep.
    public enum Tier: Sendable, Equatable {
        case transition   // learned from this exact key pair
        case key          // learned from the destination key
        case global       // learned from your typing overall
        case coldStart    // no personal data yet; flat cutoff
    }

    public enum Decision: Sendable, Equatable {
        case motor(Tier)
        case think
    }

    /// The reference median (ms) for a transition, walking the cascade
    /// transition → key → global and stopping at the first trustworthy one. Nil in cold start.
    ///
    /// All three histograms hold only already-accepted motor samples, so every median here is a
    /// clean motor center rather than a contaminated one.
    func reference(previous: KeyIdentity, current: KeyIdentity, day: DayStats) -> (median: Double, tier: Tier)? {
        let transition = BigramIdentity(first: previous, second: current)
        if let latency = day.bigrams[transition.storageKey]?.latency,
           latency.total >= config.minimumTransitionSamples,
           let median = latency.p50 {
            return (median, .transition)
        }
        if let latency = day.keys[current.keyCode]?.latency,
           latency.total >= config.minimumKeySamples,
           let median = latency.p50 {
            return (median, .key)
        }
        if day.motorLatency.total >= config.minimumGlobalSamples,
           let median = day.motorLatency.p50 {
            return (median, .global)
        }
        return nil
    }

    public func classify(
        gapMilliseconds: Double,
        previous: KeyIdentity,
        current: KeyIdentity,
        day: DayStats
    ) -> Decision {
        guard gapMilliseconds >= 0, gapMilliseconds.isFinite else { return .think }

        if let (median, tier) = reference(previous: previous, current: current, day: day) {
            let threshold = min(
                max(config.medianMultiple * median, config.floorMilliseconds),
                config.ceilingMilliseconds
            )
            return gapMilliseconds <= threshold ? .motor(tier) : .think
        }

        // Cold start: no personal reference yet, fall back to the flat cutoff.
        return gapMilliseconds <= config.coldStartCutoffMilliseconds ? .motor(.coldStart) : .think
    }
}

/// How motor samples were classified over a day, by which reference tier decided them. A tuning
/// and validation aid, not a user-facing stat.
public struct MotorFilterCounts: Codable, Equatable, Sendable {
    public var transition: UInt64 = 0
    public var key: UInt64 = 0
    public var global: UInt64 = 0
    public var coldStart: UInt64 = 0

    public init() {}

    public var total: UInt64 { transition + key + global + coldStart }

    mutating func record(_ tier: MotorFilter.Tier) {
        switch tier {
        case .transition: transition += 1
        case .key: key += 1
        case .global: global += 1
        case .coldStart: coldStart += 1
        }
    }

    mutating func merge(_ other: MotorFilterCounts) {
        transition += other.transition
        key += other.key
        global += other.global
        coldStart += other.coldStart
    }
}
