import Foundation
import Testing
@testable import FumbleCore

private enum K {
    static let t = KeyIdentity(keyCode: 17)
    static let h = KeyIdentity(keyCode: 4)
    static let a = KeyIdentity(keyCode: 0)
}

@Suite("MotorFilter")
struct MotorFilterTests {

    /// A day whose `t→h` transition has `count` clean motor samples, all at `latency` ms.
    private func dayWithTransition(count: Int, latency: Double) -> DayStats {
        var day = DayStats(date: Date(timeIntervalSince1970: 0))
        var bigram = BigramStat()
        for _ in 0..<count { bigram.latency.add(milliseconds: latency); bigram.count += 1 }
        day.bigrams[BigramIdentity(first: K.t, second: K.h).storageKey] = bigram
        // Give the global pool the same samples so cascade fallbacks are populated too.
        for _ in 0..<count { day.motorLatency.add(milliseconds: latency) }
        return day
    }

    @Test("cold start falls back to the flat cutoff")
    func coldStart() {
        let filter = MotorFilter()
        let empty = DayStats(date: Date(timeIntervalSince1970: 0))

        // No personal data yet: below the flat cutoff is a reach, above it is a think.
        #expect(filter.classify(gapMilliseconds: 300, previous: K.t, current: K.h, day: empty) == .motor(.coldStart))
        #expect(filter.classify(gapMilliseconds: 900, previous: K.t, current: K.h, day: empty) == .think)
    }

    @Test("once a transition has history, its own median sets the threshold")
    func perTransitionThreshold() {
        let filter = MotorFilter()
        // 100 samples of t→h at 100ms: median 100ms, threshold 4× = 400ms.
        let day = dayWithTransition(count: 100, latency: 100)

        // 1.2× the median: a real, slightly-slow reach — kept.
        #expect(filter.classify(gapMilliseconds: 120, previous: K.t, current: K.h, day: day) == .motor(.transition))
        // 5× the median: a think — dropped. A flat 600ms cutoff would have *kept* this.
        #expect(filter.classify(gapMilliseconds: 500, previous: K.t, current: K.h, day: day) == .think)
    }

    @Test("a slow typist's genuine reaches are not thrown away")
    func slowTypistKeepsReaches() {
        let filter = MotorFilter()
        // Median 200ms typist. A 600ms reach is 3× — real for them, and a flat 600ms cutoff
        // would sit right on top of it. Adaptive threshold is 4×200 = 800ms, so it's kept.
        let day = dayWithTransition(count: 100, latency: 200)
        #expect(filter.classify(gapMilliseconds: 600, previous: K.t, current: K.h, day: day) == .motor(.transition))
    }

    @Test("a fast typist is protected by the floor, not given a hair-trigger threshold")
    func fastTypistFloor() {
        var config = MotorFilter.Config()
        config.floorMilliseconds = 250
        let filter = MotorFilter(config: config)
        // Median 40ms. 4× = 160ms, which is below the floor, so the floor (250ms) wins.
        // A 200ms reach is therefore kept rather than rejected as 5× the median.
        let day = dayWithTransition(count: 100, latency: 40)
        #expect(filter.classify(gapMilliseconds: 200, previous: K.t, current: K.h, day: day) == .motor(.transition))
    }

    @Test("the ceiling rejects a huge gap even if the median somehow allowed it")
    func ceiling() {
        var config = MotorFilter.Config()
        config.ceilingMilliseconds = 3_000
        let filter = MotorFilter(config: config)
        // Median 900ms (very slow), 4× = 3600ms, but the ceiling caps at 3000ms.
        let day = dayWithTransition(count: 100, latency: 900)
        #expect(filter.classify(gapMilliseconds: 3_500, previous: K.t, current: K.h, day: day) == .think)
    }

    @Test("cascade falls through transition → key → global")
    func cascade() {
        let filter = MotorFilter()
        var day = DayStats(date: Date(timeIntervalSince1970: 0))

        // Only the destination key has history (no transition history): key tier is used.
        var keyStat = KeyStat()
        for _ in 0..<60 { keyStat.latency.add(milliseconds: 100); keyStat.presses += 1 }
        day.keys[K.h.keyCode] = keyStat
        #expect(filter.classify(gapMilliseconds: 300, previous: K.t, current: K.h, day: day) == .motor(.key))

        // Neither transition nor key qualifies, but the global pool does: global tier.
        var globalOnly = DayStats(date: Date(timeIntervalSince1970: 0))
        for _ in 0..<50 { globalOnly.motorLatency.add(milliseconds: 100) }
        #expect(filter.classify(gapMilliseconds: 300, previous: K.t, current: K.h, day: globalOnly) == .motor(.global))
    }

    @Test("a transition below its sample threshold does not use its own median yet")
    func belowTransitionThreshold() {
        let filter = MotorFilter()
        // Only 5 samples of t→h — not enough to trust. With nothing else populated, this
        // should fall through to cold start rather than trusting a 5-sample median.
        var day = DayStats(date: Date(timeIntervalSince1970: 0))
        var bigram = BigramStat()
        for _ in 0..<5 { bigram.latency.add(milliseconds: 100); bigram.count += 1 }
        day.bigrams[BigramIdentity(first: K.t, second: K.h).storageKey] = bigram

        let decision = filter.classify(gapMilliseconds: 300, previous: K.t, current: K.h, day: day)
        #expect(decision == .motor(.coldStart))
    }

    @Test("negative and non-finite gaps are treated as thinks, never recorded")
    func invalidGaps() {
        let filter = MotorFilter()
        let day = dayWithTransition(count: 100, latency: 100)
        #expect(filter.classify(gapMilliseconds: -5, previous: K.t, current: K.h, day: day) == .think)
        #expect(filter.classify(gapMilliseconds: .infinity, previous: K.t, current: K.h, day: day) == .think)
    }

    @Test("classification counts merge")
    func countsMerge() {
        var a = MotorFilterCounts()
        a.record(.transition); a.record(.transition); a.record(.global)
        var b = MotorFilterCounts()
        b.record(.key); b.record(.coldStart)

        a.merge(b)
        #expect(a.transition == 2)
        #expect(a.key == 1)
        #expect(a.global == 1)
        #expect(a.coldStart == 1)
        #expect(a.total == 5)
    }
}

@Suite("StatsRecorder + MotorFilter integration")
struct RecorderMotorFilterTests {

    @Test("adaptive filter tightens as a transition builds history")
    func adaptiveTightening() {
        let recorder = StatsRecorder(day: DayStats(date: Date(timeIntervalSince1970: 0)))
        var config = RecorderConfig()
        // Make the transition trust its own median after just a handful of samples, so the
        // test can exercise the transition path without thousands of events.
        config.motor.minimumTransitionSamples = 10
        config.motor.minimumKeySamples = 10
        config.motor.minimumGlobalSamples = 10
        config.motor.coldStartCutoffMilliseconds = 600
        recorder.config = config

        let t = KeyIdentity(keyCode: 17)
        let h = KeyIdentity(keyCode: 4)

        // Establish a fast t→h habit: 20 clean reaches at 90ms. breakSequence between pairs so
        // the 1s spacing to the next pair is never itself measured as a gap.
        var clock = 0.0
        for _ in 0..<20 {
            recorder.record(KeyEvent(key: t, timestamp: clock))
            recorder.record(KeyEvent(key: h, timestamp: clock + 0.09))   // 90ms reach
            recorder.breakSequence()
            clock += 1
        }

        let motorBefore = recorder.day.motorClassification.total
        #expect(motorBefore >= 20)

        // Now a 450ms t→h. Under the old flat 600ms cutoff this counted as a reach. Under the
        // learned threshold (~4×90 = 360ms) it's correctly rejected as a think.
        recorder.record(KeyEvent(key: t, timestamp: clock))
        recorder.record(KeyEvent(key: h, timestamp: clock + 0.45))

        #expect(recorder.day.discardedPauses >= 1)
        // The think was not added to the transition's latency samples.
        let transition = BigramIdentity(first: t, second: h)
        #expect(recorder.day[transition]?.latency.total == 20)
    }
}
