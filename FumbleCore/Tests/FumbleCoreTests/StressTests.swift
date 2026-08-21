import Foundation
import Testing
@testable import FumbleCore

/// Deterministic RNG so a failure reproduces.
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Adversarial / fuzz coverage: throw garbage and extremes at every module and assert it neither
/// crashes nor violates an invariant. This is the "try to break it" pass.
@Suite("Stress")
struct StressTests {

    // MARK: - StatsRecorder fuzz

    @Test("recorder survives random event streams and keeps its counting invariant")
    func recorderFuzz() {
        var rng = SeededRNG(seed: 1)
        // A grab-bag of keycodes including modifiers, backspace, arrows, Return, Tab, letters.
        let codes = [0, 1, 2, 6, 17, 41, 36, 48, 49, 51, 56, 55, 123, 96, -5, 9999]

        for seed in 0..<40 {
            rng = SeededRNG(seed: UInt64(seed))
            let recorder = StatsRecorder(day: DayStats(date: Date(timeIntervalSince1970: 0)))
            var clock = 0.0
            for _ in 0..<500 {
                clock += Double.random(in: -0.5...5, using: &rng)   // includes backwards jumps
                let code = codes.randomElement(using: &rng)!
                recorder.record(KeyEvent(
                    key: KeyIdentity(keyCode: code),
                    timestamp: clock,
                    isAutorepeat: Bool.random(using: &rng),
                    isSynthetic: Bool.random(using: &rng),
                    isSecureInput: Bool.random(using: &rng),
                    appBundleID: Bool.random(using: &rng) ? "com.test.app" : nil
                ))
            }
            let day = recorder.day
            // Invariant: total presses equals the sum of per-key presses.
            let summed = day.keys.values.reduce(UInt64(0)) { $0 + $1.presses }
            #expect(summed == day.totalPresses)
            // Invariant: active time and correction counts are never negative / nonsensical.
            #expect(day.activeSeconds >= 0)
            #expect(day.totalCorrections <= day.totalPresses + day.rejectedSecureInput + day.rejectedSynthetic + 10)
            // Snapshot for persistence must round-trip through JSON.
            let snapshot = recorder.snapshotForPersistence()
            let data = try! JSONEncoder().encode(snapshot)
            let decoded = try! JSONDecoder().decode(DayStats.self, from: data)
            #expect(decoded.totalPresses == snapshot.totalPresses)
        }
    }

    @Test("day rollover mid-stream never fabricates a cross-day bigram")
    func dayRollover() {
        let recorder = StatsRecorder(day: DayStats(date: Date(timeIntervalSince1970: 0)))
        recorder.record(KeyEvent(key: KeyIdentity(keyCode: 0), timestamp: 0))
        recorder.startNewDay(Date(timeIntervalSince1970: 86_400))
        recorder.record(KeyEvent(key: KeyIdentity(keyCode: 1), timestamp: 0.1))
        #expect(recorder.day.bigrams.isEmpty)
    }

    // MARK: - LatencyHistogram extremes

    @Test("histogram handles extreme and degenerate inputs")
    func histogramExtremes() {
        var h = LatencyHistogram()
        for value in [0.0, 0.0001, 1e9, 9_999_999, 0.5] { h.add(milliseconds: value) }
        #expect(h.total == 5)
        _ = h.p50; _ = h.p95
        #expect(h.percentile(-1) != nil)   // clamps
        #expect(h.percentile(2) != nil)    // clamps
        // A single sample.
        var one = LatencyHistogram()
        one.add(milliseconds: 42)
        #expect(one.p50 != nil && one.p95 != nil)
    }

    // MARK: - WeakSpots degenerate days

    @Test("weak-spot analysis never divides by zero or crashes on odd days")
    func weakSpotsDegenerate() {
        // Empty day.
        #expect(WeakSpots.analyse(DayStats(date: Date(timeIntervalSince1970: 0))) == nil)

        // A day with tons of active time but a single key — not enough distinct keys.
        var day = DayStats(date: Date(timeIntervalSince1970: 0))
        var stat = KeyStat()
        for _ in 0..<500 { stat.latency.add(milliseconds: 100); stat.presses += 1 }
        day.keys[0] = stat
        day.totalPresses = 500
        day.activeSeconds = 3_600
        #expect(WeakSpots.analyse(day) == nil)   // < minimumBaselineKeys

        // Every key identical — a valid baseline, no weak spots.
        for code in [0, 1, 2, 3, 5, 12, 13, 14, 15, 17] {
            var s = KeyStat()
            for _ in 0..<100 { s.latency.add(milliseconds: 100); s.presses += 1 }
            day.keys[code] = s
        }
        let analysis = WeakSpots.analyse(day)
        #expect(analysis != nil)
        #expect(analysis?.keys.isEmpty == true)
    }

    // MARK: - KeyboardTrainer extremes

    @Test("trainer never loops forever or leaves an invalid state under random results")
    func trainerFuzz() {
        var rng = SeededRNG(seed: 7)
        for seed in 0..<30 {
            rng = SeededRNG(seed: UInt64(seed))
            // Random seed confidences, including some above and below target and some absent.
            var seedMap: [Int: Double] = [:]
            for key in KeyIdentity.alphabetByFrequency where Bool.random(using: &rng) {
                seedMap[key.keyCode] = Double.random(in: 0...120, using: &rng)
            }
            let trainer = KeyboardTrainer(seed: seedMap)
            #expect(trainer.unlockedCount >= 1 && trainer.unlockedCount <= 26)

            // Drive up to 200 lessons with random results; must terminate and stay valid.
            for _ in 0..<200 {
                if trainer.isComplete { break }
                var results: [Int: Double] = [:]
                for key in trainer.unlockedKeys {
                    results[key.keyCode] = Double.random(in: 0...100, using: &rng)
                }
                trainer.record(perKeyWPM: results)
                #expect(trainer.unlockedCount >= 1 && trainer.unlockedCount <= 26)
                // Focus, when present, is always an unlocked, non-mastered key.
                if let focus = trainer.focusKey {
                    #expect(trainer.unlockedKeys.contains { $0.keyCode == focus.keyCode })
                    #expect(!trainer.isMastered(focus))
                }
            }
        }
    }

    @Test("trainer seeded fully mastered is immediately complete with no focus")
    func trainerAllMastered() {
        var seed: [Int: Double] = [:]
        for key in KeyIdentity.alphabetByFrequency { seed[key.keyCode] = 200 }
        let trainer = KeyboardTrainer(seed: seed)
        // Unlock everything.
        for _ in 0..<30 where !trainer.isComplete {
            trainer.record(perKeyWPM: Dictionary(uniqueKeysWithValues: trainer.unlockedKeys.map { ($0.keyCode, 200.0) }))
        }
        #expect(trainer.isComplete)
        #expect(trainer.focusKey == nil)
        #expect(trainer.unlockNext() == false)   // nothing left to unlock
    }

    // MARK: - TrainerLessonGenerator edges

    @Test("lesson generator survives odd unlocked sets and only emits allowed letters")
    func lessonGeneratorFuzz() {
        var rng = SeededRNG(seed: 3)
        let all = KeyIdentity.alphabetByFrequency
        for seed in 0..<40 {
            rng = SeededRNG(seed: UInt64(seed))
            let count = Int.random(in: 1...26, using: &rng)
            let unlocked = Array(all.prefix(count))
            let focus = Bool.random(using: &rng) ? unlocked.randomElement(using: &rng) : nil
            let text = TrainerLessonGenerator.generate(unlocked: unlocked, focus: focus, wordCount: 24, using: &rng)

            let allowed = Set(unlocked.compactMap { KeyIdentity.labels[$0.keyCode]?.lowercased().first } + [" "])
            #expect(text.allSatisfy { allowed.contains($0) }, "seed \(seed) leaked a disallowed char")
            #expect(!text.isEmpty)
        }
    }

    @Test("lesson generator with a consonant-only set doesn't crash")
    func consonantOnly() {
        // Force a pathological set with no vowels (not reachable in normal unlock order, but
        // the generator must not assume vowels exist).
        let consonants = [17, 45, 1, 4].map(KeyIdentity.init(keyCode:))   // t n s h
        var rng = SeededRNG(seed: 9)
        let text = TrainerLessonGenerator.generate(unlocked: consonants, focus: consonants[0], wordCount: 10, using: &rng)
        #expect(text.split(separator: " ").count == 10)
    }

    // MARK: - StatsStore resilience

    @Test("store tolerates a garbage directory of files")
    func storeGarbage() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FumbleStress-\(UUID().uuidString)", isDirectory: true)
        let store = StatsStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Junk files of various kinds.
        try "not json".write(to: dir.appendingPathComponent("2020-01-01.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: dir.appendingPathComponent("2020-01-02.json"), atomically: true, encoding: .utf8)
        try Data([0xFF, 0x00, 0x13]).write(to: dir.appendingPathComponent("2020-01-03.json"))
        try "".write(to: dir.appendingPathComponent("notadate.json"), atomically: true, encoding: .utf8)
        try "x".write(to: dir.appendingPathComponent("ignore.txt"), atomically: true, encoding: .utf8)

        // Must not throw or crash; just skips what it can't read.
        _ = store.loadAll()
        // A valid save still works alongside the junk.
        var day = DayStats(date: Calendar.current.startOfDay(for: Date()))
        day.totalPresses = 5
        try store.save(day)
        #expect(store.loadAll().contains { $0.totalPresses == 5 })
    }
}
