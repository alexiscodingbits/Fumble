import Foundation
import Observation

/// keybr's adaptive letter-unlocking loop — but seeded from your real typing, so you start
/// pre-aimed at your actual weak keys instead of grinding up from the home row.
///
/// The model keeps a per-key **confidence** (an estimated WPM), unlocks letters in frequency
/// order, always focuses the weakest unlocked letter that's below target, and unlocks the next
/// letter once every unlocked one has reached the target. The one difference from keybr — and
/// the whole point of Fumble — is the seed: keybr starts every letter at zero because it has no
/// data; we initialise confidence from captured latency, so letters you already type fast start
/// already unlocked and mastered, and the trainer's focus lands on a real weakness from run one.
@Observable
public final class KeyboardTrainer {

    public struct Config: Sendable, Equatable {
        /// WPM at which a letter counts as "mastered" (confidence 1). keybr's default is 35.
        public var targetWPM: Double = 35
        /// WPM mapped to confidence 0. Below this a key is as weak as the bar shows.
        public var floorWPM: Double = 12
        /// Never present fewer than this many letters, so early practice isn't one lonely key.
        public var minimumUnlocked: Int = 6
        /// How much a fresh drill result moves a key's running confidence (0–1). Low = smooth.
        public var blend: Double = 0.35

        public init() {}
    }

    public private(set) var config: Config
    /// Estimated WPM per key code. The running confidence signal.
    public private(set) var wpm: [Int: Double]
    /// How many of `alphabetByFrequency` are currently active.
    public private(set) var unlockedCount: Int

    /// Raw per-key telemetry, separate from `wpm`: `wpm` is the *blended* unlock signal, while
    /// this keeps what was actually measured, so the UI can show keybr-style feedback
    /// ("Last 36.3wpm, Top 54.1wpm, +1.4wpm/lesson") without smoothing hiding the trend.
    private struct KeyHistory {
        /// Most recent raw samples, oldest first, capped at `historySampleCap`.
        var samples: [Double]
        /// All-time best. Tracked outside `samples` so it survives the cap.
        var top: Double
    }
    /// Not `@ObservationIgnored` on purpose — the telemetry accessors below read this, and the
    /// UI must re-render when a drill lands a new sample.
    private var history: [Int: KeyHistory] = [:]
    /// keybr keeps a short window too: enough for a trend, short enough to reflect *current*
    /// form rather than averaging away the last month.
    private static let historySampleCap = 20

    private let alphabet = KeyIdentity.alphabetByFrequency

    /// - Parameter seed: estimated WPM per key code from real capture (missing = unknown).
    public init(seed: [Int: Double] = [:], config: Config = Config()) {
        self.config = config
        self.wpm = seed
        self.unlockedCount = 0
        self.unlockedCount = Self.initialUnlockCount(seed: seed, alphabet: alphabet, config: config)
    }

    /// Start with every already-mastered leading letter unlocked, plus the first not-yet-mastered
    /// one (the first real weakness), floored at `minimumUnlocked`. So a fast typist opens
    /// straight onto their weakest letter; a beginner opens on the first handful.
    private static func initialUnlockCount(seed: [Int: Double], alphabet: [KeyIdentity], config: Config) -> Int {
        var mastered = 0
        for key in alphabet {
            if let w = seed[key.keyCode], w >= config.targetWPM { mastered += 1 } else { break }
        }
        return min(alphabet.count, max(config.minimumUnlocked, mastered + 1))
    }

    // MARK: - Derived state

    public var unlockedKeys: [KeyIdentity] { Array(alphabet.prefix(unlockedCount)) }

    /// 0…1 progress bar value for a key. Unknown keys read as floor (0).
    public func confidence(for key: KeyIdentity) -> Double {
        let w = wpm[key.keyCode] ?? config.floorWPM
        let range = config.targetWPM - config.floorWPM
        guard range > 0 else { return w >= config.targetWPM ? 1 : 0 }
        return min(max((w - config.floorWPM) / range, 0), 1)
    }

    public func isMastered(_ key: KeyIdentity) -> Bool { confidence(for: key) >= 1 }

    /// The letter to drill now: the weakest unlocked letter still below target. Nil when every
    /// unlocked letter is mastered (a unlock is due, or the whole alphabet is done).
    public var focusKey: KeyIdentity? {
        unlockedKeys
            .filter { !isMastered($0) }
            .min { (wpm[$0.keyCode] ?? config.floorWPM) < (wpm[$1.keyCode] ?? config.floorWPM) }
    }

    public var allUnlockedMastered: Bool { unlockedKeys.allSatisfy { isMastered($0) } }
    public var isComplete: Bool { unlockedCount >= alphabet.count && allUnlockedMastered }

    public var masteredCount: Int { unlockedKeys.filter { isMastered($0) }.count }

    // MARK: - Per-key telemetry

    /// The raw WPM measured for this key in the most recent drill that reported it. Nil until
    /// the key has been measured at least once — a fresh key has no speed, not a speed of 0.
    public func lastWPM(for key: KeyIdentity) -> Double? {
        history[key.keyCode]?.samples.last
    }

    /// The best raw WPM ever measured for this key. Outlives the sample cap.
    public func topWPM(for key: KeyIdentity) -> Double? {
        history[key.keyCode]?.top
    }

    /// How many raw samples are currently stored for this key (at most `historySampleCap`).
    public func sampleCount(for key: KeyIdentity) -> Int {
        history[key.keyCode]?.samples.count ?? 0
    }

    /// WPM gained per lesson: the least-squares slope over the stored samples, with the sample
    /// index as x. Positive = improving. Nil below 3 samples — two points always fit a line, so
    /// a "trend" from them would just be noise presented with confidence.
    public func learningRate(for key: KeyIdentity) -> Double? {
        guard let samples = history[key.keyCode]?.samples, samples.count >= 3 else { return nil }
        let n = Double(samples.count)
        let meanX = (n - 1) / 2                       // x = 0, 1, ..., n-1
        let meanY = samples.reduce(0, +) / n
        var numerator = 0.0
        var denominator = 0.0
        for (index, sample) in samples.enumerated() {
            let dx = Double(index) - meanX
            numerator += dx * (sample - meanY)
            denominator += dx * dx
        }
        // denominator > 0 whenever n >= 2: the x values are distinct indices.
        return numerator / denominator
    }

    // MARK: - Progression

    /// Fold a completed drill's measured per-key WPM into the running confidence, then unlock the
    /// next letter if everything currently shown is mastered. Every measured key also gets its
    /// RAW sample appended to the telemetry history — the blend applies only to the unlock signal.
    public func record(perKeyWPM: [Int: Double]) {
        // The `sample > 0` guard covers history too: a non-positive WPM means "not actually
        // measured this lesson", and storing it would report a last speed of 0 and drag the
        // learning rate — nil/absent, not zero, is how we say "unknown".
        for (keyCode, sample) in perKeyWPM where sample > 0 {
            let previous = wpm[keyCode] ?? config.floorWPM
            wpm[keyCode] = previous + (sample - previous) * config.blend
            appendHistory(sample, for: keyCode)
        }
        if allUnlockedMastered, unlockedCount < alphabet.count {
            unlockedCount += 1
        }
    }

    private func appendHistory(_ sample: Double, for keyCode: Int) {
        var entry = history[keyCode] ?? KeyHistory(samples: [], top: sample)
        entry.samples.append(sample)
        if entry.samples.count > Self.historySampleCap {
            entry.samples.removeFirst()   // window slides; `top` below still remembers the peak
        }
        entry.top = max(entry.top, sample)
        history[keyCode] = entry
    }

    /// Manually unlock the next letter (a "skip / add a letter" control), if any remain.
    @discardableResult
    public func unlockNext() -> Bool {
        guard unlockedCount < alphabet.count else { return false }
        unlockedCount += 1
        return true
    }
}
