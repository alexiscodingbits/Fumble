import Foundation
import Testing
@testable import FumbleCore

@Suite("WeakSpots")
struct WeakSpotsTests {

    /// Builds a day with a controlled latency profile: every key at `baseline` ms, except
    /// `slowKey` at `slowLatency` ms.
    private func makeDay(
        keys: [KeyIdentity],
        samplesPerKey: Int,
        baseline: Double,
        slowKey: KeyIdentity? = nil,
        slowLatency: Double = 300,
        activeSeconds: Double = 600
    ) -> DayStats {
        var day = DayStats(date: Date(timeIntervalSince1970: 0))
        for key in keys {
            var stat = KeyStat()
            let latency = key == slowKey ? slowLatency : baseline
            for _ in 0..<samplesPerKey {
                stat.latency.add(milliseconds: latency)
                stat.presses += 1
            }
            day.keys[key.keyCode] = stat
            day.totalPresses += UInt64(samplesPerKey)
        }
        day.activeSeconds = activeSeconds
        return day
    }

    private var ordinaryKeys: [KeyIdentity] {
        [0, 1, 2, 3, 5, 12, 13, 14, 15, 17].map(KeyIdentity.init(keyCode:))
    }

    @Test("returns nil before there is enough data to be honest")
    func insufficientData() {
        let day = makeDay(keys: ordinaryKeys, samplesPerKey: 100, baseline: 100, activeSeconds: 10)
        // An empty list would read as "you have no weaknesses". Nil forces the UI to say
        // "still learning" instead.
        #expect(WeakSpots.analyse(day) == nil)
    }

    @Test("identifies the slow key and leaves the rest alone")
    func findsSlowKey() throws {
        let slow = KeyIdentity(keyCode: 6)   // Z
        var day = makeDay(keys: ordinaryKeys, samplesPerKey: 100, baseline: 90)
        var stat = KeyStat()
        for _ in 0..<100 {
            stat.latency.add(milliseconds: 300)
            stat.presses += 1
        }
        day.keys[slow.keyCode] = stat
        day.totalPresses += 100

        let analysis = try #require(WeakSpots.analyse(day))
        #expect(analysis.keys.first?.label == "Z")
        // Everything else sits at the baseline, so nothing else should clear the excess floor.
        #expect(analysis.keys.count == 1)
    }

    @Test("baseline is the user's own p95, not an absolute threshold")
    func baselineIsRelative() throws {
        // A uniformly slow typist: every key at 400ms. Nobody should be flagged, because
        // nothing here is a *relative* weakness — judged absolutely, the whole keyboard would be.
        let day = makeDay(keys: ordinaryKeys, samplesPerKey: 100, baseline: 400)
        let analysis = try #require(WeakSpots.analyse(day))
        #expect(analysis.keys.isEmpty)
        #expect(analysis.baselineP95 >= 400)
    }

    @Test("ranks by total time cost, not by per-press slowness")
    func ranksByTimeCost() throws {
        var day = makeDay(keys: ordinaryKeys, samplesPerKey: 200, baseline: 80)

        // Very slow, but rare: 50 presses at +220ms ≈ 11s.
        var rare = KeyStat()
        for _ in 0..<50 { rare.latency.add(milliseconds: 300); rare.presses += 1 }
        day.keys[6] = rare   // Z

        // Mildly slow, but constant: 2000 presses at +40ms ≈ 80s. This is the one actually
        // costing you time, and a naive "slowest key" ranking would bury it.
        var common = KeyStat()
        for _ in 0..<2_000 { common.latency.add(milliseconds: 125); common.presses += 1 }
        day.keys[41] = common   // ;

        day.totalPresses += 2_050
        day.activeSeconds = 3_600

        let analysis = try #require(WeakSpots.analyse(day))
        #expect(analysis.keys.first?.label == ";")
        let top = try #require(analysis.keys.first)
        let second = try #require(analysis.keys.dropFirst().first)
        #expect(top.timeCostSeconds > second.timeCostSeconds)
    }

    @Test("ignores keys with too few samples")
    func minimumSamples() throws {
        var day = makeDay(keys: ordinaryKeys, samplesPerKey: 100, baseline: 90)
        // Three very slow presses — a p95 from three samples is one bad sample.
        var sparse = KeyStat()
        for _ in 0..<3 { sparse.latency.add(milliseconds: 500); sparse.presses += 1 }
        day.keys[6] = sparse
        day.totalPresses += 3

        let analysis = try #require(WeakSpots.analyse(day))
        #expect(!analysis.keys.contains { $0.label == "Z" })
    }

    @Test("excludes non-typing keys from weak spots")
    func excludesNonTypingKeys() throws {
        var day = makeDay(keys: ordinaryKeys, samplesPerKey: 100, baseline: 90)
        // Arrow keys are slow by nature and not something to drill.
        var arrow = KeyStat()
        for _ in 0..<200 { arrow.latency.add(milliseconds: 450); arrow.presses += 1 }
        day.keys[123] = arrow   // Left
        day.totalPresses += 200

        let analysis = try #require(WeakSpots.analyse(day))
        #expect(!analysis.keys.contains { $0.label == "Left" })
    }

    @Test("same-finger bigrams are reported but excluded from drills")
    func sameFingerBigrams() throws {
        var day = makeDay(keys: ordinaryKeys, samplesPerKey: 300, baseline: 80)

        // E then D — both left middle finger. Slow because of anatomy.
        let sameFinger = BigramIdentity(first: KeyIdentity(keyCode: 14), second: KeyIdentity(keyCode: 2))
        var sameFingerStat = BigramStat()
        for _ in 0..<100 { sameFingerStat.latency.add(milliseconds: 250); sameFingerStat.count += 1 }
        day.bigrams[sameFinger.storageKey] = sameFingerStat

        // A then L — different hands. Slow because of skill.
        let crossHand = BigramIdentity(first: KeyIdentity(keyCode: 0), second: KeyIdentity(keyCode: 37))
        var crossHandStat = BigramStat()
        for _ in 0..<100 { crossHandStat.latency.add(milliseconds: 250); crossHandStat.count += 1 }
        day.bigrams[crossHand.storageKey] = crossHandStat

        day.activeSeconds = 3_600
        let analysis = try #require(WeakSpots.analyse(day))

        #expect(sameFinger.isSameFinger)
        #expect(!crossHand.isSameFinger)
        // Both are visible in the analysis...
        #expect(analysis.bigrams.contains { $0.label == sameFinger.label })
        // ...but only the trainable one is offered as a drill. Telling someone to grind a
        // same-finger bigram is telling them to fix their hand.
        #expect(!analysis.drillable.contains { $0.label == sameFinger.label })
        #expect(analysis.drillable.contains { $0.label == crossHand.label })
    }

    @Test("ordering is stable for equal-cost entries")
    func stableOrdering() throws {
        var day = makeDay(keys: ordinaryKeys, samplesPerKey: 200, baseline: 80)
        for keyCode in [6, 41, 44] {
            var stat = KeyStat()
            for _ in 0..<100 { stat.latency.add(milliseconds: 250); stat.presses += 1 }
            day.keys[keyCode] = stat
            day.totalPresses += 100
        }
        day.activeSeconds = 3_600

        let first = try #require(WeakSpots.analyse(day))
        let second = try #require(WeakSpots.analyse(day))
        // Identical input must not reshuffle between refreshes, or the list flickers.
        #expect(first.keys.map(\.id) == second.keys.map(\.id))
    }

    @Test("correction ranking is separate from latency ranking")
    func correctionsAreSeparate() throws {
        var day = makeDay(keys: ordinaryKeys, samplesPerKey: 200, baseline: 90)
        // Fast but inaccurate: never flagged as slow, but worth surfacing. Z (keycode 6) is
        // deliberately not one of `ordinaryKeys`, so build its stat rather than mutating a
        // key that doesn't exist.
        var inaccurate = KeyStat()
        inaccurate.presses = 200
        inaccurate.corrections = 40
        for _ in 0..<200 { inaccurate.latency.add(milliseconds: 90) }
        day.keys[6] = inaccurate
        day.totalPresses += 200

        let analysis = try #require(WeakSpots.analyse(day))
        let corrected = analysis.mostCorrected(in: day)
        #expect(corrected.first?.0.label == "Z")
        #expect(abs((corrected.first?.1 ?? 0) - 0.2) < 0.001)
    }
}
