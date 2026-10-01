import Foundation

/// Turns your weak spots into practice text.
///
/// Given the keys and transitions you're slowest at, it samples real words from a pool, weighted
/// toward the ones that make you type those weak keys and transitions. The result is a line of
/// ordinary words — but disproportionately the words that exercise exactly what you're bad at.
/// That's the whole point over keybr: you practise real text skewed to your weaknesses, not
/// pseudo-random letters skewed to a frequency model.
public struct DrillGenerator {

    public let words: [String]

    public init(words: [String] = WordList.common) {
        self.words = words
    }

    /// The weaknesses a drill should target, reduced to the keycodes and key-pairs the generator
    /// scores against.
    public struct Targets: Equatable, Sendable {
        public var keyCodes: Set<Int>
        public var bigrams: Set<BigramIdentity>

        public init(keyCodes: Set<Int> = [], bigrams: Set<BigramIdentity> = []) {
            self.keyCodes = keyCodes
            self.bigrams = bigrams
        }

        public var isEmpty: Bool { keyCodes.isEmpty && bigrams.isEmpty }

        /// Pull targets straight from an analysis — the top few of each, which is all a single
        /// drill can meaningfully focus on.
        public init(analysis: WeakSpots.Analysis, topKeys: Int = 5, topBigrams: Int = 5) {
            keyCodes = Set(analysis.keys.prefix(topKeys).compactMap { spot -> Int? in
                if case .key(let key) = spot.target { return key.keyCode }
                return nil
            })
            bigrams = Set(analysis.drillable.prefix(topBigrams).compactMap { spot -> BigramIdentity? in
                if case .bigram(let bigram) = spot.target { return bigram }
                return nil
            })
        }
    }

    /// How strongly a word's weak content skews its odds of being picked. A word contributes
    /// `1 + weight × hits` to the sampling distribution, so the pool never collapses to only
    /// weak words (that reads as gibberish and kills the sense of typing real text) — it just
    /// leans that way.
    public var keyWeight = 1
    public var bigramWeight = 3   // a specific weak transition is worth more than a weak key

    /// A word's weak-target score: how much practising it exercises the targets.
    func score(_ word: String, targets: Targets) -> Int {
        let codes = word.compactMap { KeyIdentity.characterToKeyCode[$0] }
        guard !codes.isEmpty else { return 0 }

        var total = 0
        for code in codes where targets.keyCodes.contains(code) { total += keyWeight }
        if !targets.bigrams.isEmpty {
            for i in 0..<(codes.count - 1) {
                let pair = BigramIdentity(
                    first: KeyIdentity(keyCode: codes[i]),
                    second: KeyIdentity(keyCode: codes[i + 1])
                )
                if targets.bigrams.contains(pair) { total += bigramWeight }
            }
        }
        return total
    }

    /// Generate a drill of `wordCount` words, space-separated.
    ///
    /// `rng` is injected so tests are deterministic; the app passes a system RNG. With no targets
    /// (a fresh user, or a warm-up) it's an unweighted sample — still real words, just not skewed.
    public func generate<R: RandomNumberGenerator>(
        targets: Targets,
        wordCount: Int = 30,
        using rng: inout R
    ) -> String {
        guard wordCount > 0, !words.isEmpty else { return "" }

        let baseWeights = words.map { 1 + (targets.isEmpty ? 0 : score($0, targets: targets)) }
        // Sampling WITHOUT replacement: a word's weight drops to zero once picked, so no word
        // appears twice in a lesson while the pool has anything left. "sequence" three times
        // in fifteen words reads as a bug, not a drill. Only when every word has been used
        // (pool smaller than the lesson) do the weights reset and repeats begin.
        var weights = baseWeights
        var totalWeight = weights.reduce(0, +)

        var picked: [String] = []
        picked.reserveCapacity(wordCount)

        for _ in 0..<wordCount {
            if totalWeight == 0 {
                weights = baseWeights
                totalWeight = weights.reduce(0, +)
            }
            let index = weightedIndex(weights: weights, total: totalWeight, using: &rng)
            picked.append(words[index])
            totalWeight -= weights[index]
            weights[index] = 0
        }
        return picked.joined(separator: " ")
    }

    private func weightedIndex<R: RandomNumberGenerator>(
        weights: [Int], total: Int, using rng: inout R
    ) -> Int {
        guard total > 0 else { return Int.random(in: 0..<weights.count, using: &rng) }
        var target = Int.random(in: 0..<total, using: &rng)
        for (index, weight) in weights.enumerated() {
            target -= weight
            if target < 0 { return index }
        }
        return weights.count - 1
    }
}
