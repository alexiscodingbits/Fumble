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

    // MARK: - Progression

    /// Fold a completed drill's measured per-key WPM into the running confidence, then unlock the
    /// next letter if everything currently shown is mastered.
    public func record(perKeyWPM: [Int: Double]) {
        for (keyCode, sample) in perKeyWPM where sample > 0 {
            let previous = wpm[keyCode] ?? config.floorWPM
            wpm[keyCode] = previous + (sample - previous) * config.blend
        }
        if allUnlockedMastered, unlockedCount < alphabet.count {
            unlockedCount += 1
        }
    }

    /// Manually unlock the next letter (a "skip / add a letter" control), if any remain.
    @discardableResult
    public func unlockNext() -> Bool {
        guard unlockedCount < alphabet.count else { return false }
        unlockedCount += 1
        return true
    }
}
