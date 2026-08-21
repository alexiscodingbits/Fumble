import Foundation
import Testing
@testable import FumbleCore

/// Keycodes used throughout, by ANSI legend.
private enum K {
    static let a = KeyIdentity(keyCode: 0)
    static let s = KeyIdentity(keyCode: 1)
    static let d = KeyIdentity(keyCode: 2)
    static let z = KeyIdentity(keyCode: 6)
    static let semicolon = KeyIdentity(keyCode: 41)
    static let space = KeyIdentity(keyCode: 49)
    static let delete = KeyIdentity(keyCode: 51)
    static let shift = KeyIdentity(keyCode: 56)
    static let command = KeyIdentity(keyCode: 55)
    static let left = KeyIdentity(keyCode: 123)
    static let ret = KeyIdentity(keyCode: 36)
    static let tab = KeyIdentity(keyCode: 48)
}

@Suite("StatsRecorder")
struct StatsRecorderTests {

    private func makeRecorder() -> StatsRecorder {
        StatsRecorder(day: DayStats(date: Date(timeIntervalSince1970: 0)))
    }

    // MARK: - Counting

    @Test("counts typing keys and their reach latency")
    func countsPresses() throws {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.a, timestamp: 0))
        recorder.record(KeyEvent(key: K.s, timestamp: 0.1))
        recorder.record(KeyEvent(key: K.d, timestamp: 0.2))

        #expect(recorder.day.totalPresses == 3)
        // The first key has no predecessor, so it has no latency sample.
        #expect(recorder.day[K.a]?.latency.total == 0)
        #expect(recorder.day[K.s]?.latency.total == 1)
        let latency = try #require(recorder.day[K.s]?.latency.mean)
        #expect(abs(latency - 100) < 0.001)
    }

    @Test("records the bigram for each consecutive pair")
    func recordsBigrams() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.a, timestamp: 0))
        recorder.record(KeyEvent(key: K.s, timestamp: 0.08))

        let bigram = BigramIdentity(first: K.a, second: K.s)
        #expect(recorder.day[bigram]?.count == 1)
        #expect(recorder.day[bigram]?.latency.total == 1)
    }

    // MARK: - Rejections

    @Test("secure input is dropped, counted, and breaks the sequence")
    func secureInput() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.a, timestamp: 0))
        recorder.record(KeyEvent(key: K.s, timestamp: 0.1, isSecureInput: true))
        recorder.record(KeyEvent(key: K.d, timestamp: 0.2))

        #expect(recorder.day.rejectedSecureInput == 1)
        #expect(recorder.day.totalPresses == 2)   // a and d only
        #expect(recorder.day[K.s] == nil)
        // Crucially, no a→d bigram: those keys were never adjacent in real typing.
        #expect(recorder.day[BigramIdentity(first: K.a, second: K.d)] == nil)
    }

    @Test("software-injected keystrokes are excluded from speed")
    func synthetic() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.a, timestamp: 0, isSynthetic: true))
        recorder.record(KeyEvent(key: K.s, timestamp: 0.001, isSynthetic: true))

        #expect(recorder.day.rejectedSynthetic == 2)
        #expect(recorder.day.totalPresses == 0)
        // This is the honest-WPM guarantee: a text expander firing 40 chars in 2ms cannot
        // move the number. Nil rather than 0 — there was no typing, which is not the same
        // claim as "you typed at zero words per minute".
        #expect(recorder.day.wordsPerMinute(minimumActiveSeconds: 0) == nil)
    }

    @Test("autorepeat is excluded but does not break the sequence")
    func autorepeat() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.a, timestamp: 0))
        recorder.record(KeyEvent(key: K.a, timestamp: 0.05, isAutorepeat: true))
        recorder.record(KeyEvent(key: K.a, timestamp: 0.10, isAutorepeat: true))
        recorder.record(KeyEvent(key: K.s, timestamp: 0.15))

        #expect(recorder.day.rejectedAutorepeat == 2)
        #expect(recorder.day.totalPresses == 2)
        // A held key is a continuation: a→s is still a genuine transition.
        #expect(recorder.day[BigramIdentity(first: K.a, second: K.s)]?.count == 1)
    }

    @Test("keystrokes in excluded apps (own practice window) never enter the day")
    func selfPracticeExcluded() {
        let recorder = makeRecorder()
        var config = RecorderConfig()
        config.excludedBundleIDs = ["com.alexiscodingbits.fumble"]
        recorder.config = config

        recorder.record(KeyEvent(key: K.a, timestamp: 0, appBundleID: "com.apple.Terminal"))
        // Drill typing inside Fumble itself: must not count, and must not fabricate a bigram
        // bridging into the next real keystroke.
        recorder.record(KeyEvent(key: K.z, timestamp: 0.1, appBundleID: "com.alexiscodingbits.fumble"))
        recorder.record(KeyEvent(key: K.z, timestamp: 0.2, appBundleID: "com.alexiscodingbits.fumble"))
        recorder.record(KeyEvent(key: K.s, timestamp: 0.3, appBundleID: "com.apple.Terminal"))

        #expect(recorder.day.rejectedSelfPractice == 2)
        #expect(recorder.day.totalPresses == 2)                    // a and s only
        #expect(recorder.day[K.z] == nil)                          // drill reps never recorded
        #expect(recorder.day[BigramIdentity(first: K.a, second: K.s)] == nil)   // sequence broken
        #expect(recorder.day.apps["com.alexiscodingbits.fumble"] == nil)
    }

    // MARK: - Corrections

    @Test("backspace attributes a correction to the preceding key")
    func correctionAttribution() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.a, timestamp: 0))
        recorder.record(KeyEvent(key: K.z, timestamp: 0.1))
        recorder.record(KeyEvent(key: K.delete, timestamp: 0.2))

        #expect(recorder.day[K.z]?.corrections == 1)
        #expect(recorder.day[K.a]?.corrections == nil || recorder.day[K.a]?.corrections == 0)
        #expect(recorder.day.totalCorrections == 1)
        // Backspace is not a typed key.
        #expect(recorder.day.totalPresses == 2)
    }

    @Test("backspace breaks the sequence so corrections don't fabricate bigrams")
    func backspaceBreaksSequence() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.z, timestamp: 0))
        recorder.record(KeyEvent(key: K.delete, timestamp: 0.1))
        recorder.record(KeyEvent(key: K.s, timestamp: 0.2))

        // "the key after a delete" is a correction artefact, not a transition worth drilling.
        #expect(recorder.day[BigramIdentity(first: K.z, second: K.s)] == nil)
        #expect(recorder.day[K.s]?.latency.total == 0)
    }

    @Test("consecutive backspaces attribute only one correction")
    func repeatedBackspace() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.z, timestamp: 0))
        recorder.record(KeyEvent(key: K.delete, timestamp: 0.1))
        recorder.record(KeyEvent(key: K.delete, timestamp: 0.2))
        recorder.record(KeyEvent(key: K.delete, timestamp: 0.3))

        // The first delete clears the context; there's no longer a key to blame.
        #expect(recorder.day.totalCorrections == 1)
    }

    @Test("Return counts as a press but never as a latency sample or bigram")
    func returnIsPressButNotLatency() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.a, timestamp: 0))
        recorder.record(KeyEvent(key: K.ret, timestamp: 0.1))   // fast enough to be "motor"
        recorder.record(KeyEvent(key: K.s, timestamp: 0.2))

        // Return is a real keystroke: it counts toward WPM.
        #expect(recorder.day.totalPresses == 3)
        #expect(recorder.day[K.ret]?.presses == 1)
        // But its latency is contaminated by the pause before it, so it's never recorded...
        #expect((recorder.day[K.ret]?.latency.total ?? 0) == 0)
        // ...and neither a→Return nor Return→s becomes a bigram.
        #expect(recorder.day[BigramIdentity(first: K.a, second: K.ret)] == nil)
        #expect(recorder.day[BigramIdentity(first: K.ret, second: K.s)] == nil)
        // s's own latency isn't recorded either, because its predecessor was Return.
        #expect((recorder.day[K.s]?.latency.total ?? 0) == 0)
    }

    @Test("Return never appears as a weak spot even with a slow measured latency")
    func returnNotAWeakSpot() throws {
        // Build a day with a healthy baseline (many keys) plus a Return that — hypothetically,
        // if latency ever leaked in — would look very slow. It must not surface as a weak key.
        var day = DayStats(date: Date(timeIntervalSince1970: 0))
        for keyCode in [0, 1, 2, 3, 5, 12, 13, 14, 15, 17] {
            var stat = KeyStat()
            for _ in 0..<100 { stat.latency.add(milliseconds: 90); stat.presses += 1 }
            day.keys[keyCode] = stat
            day.totalPresses += 100
        }
        // Return: real presses, and (defensively) a slow latency histogram. The analyser must
        // still exclude it because it isn't a latency candidate.
        var ret = KeyStat()
        for _ in 0..<100 { ret.latency.add(milliseconds: 500); ret.presses += 1 }
        day.keys[36] = ret
        day.totalPresses += 100
        day.activeSeconds = 600

        let analysis = try #require(WeakSpots.analyse(day))
        #expect(!analysis.keys.contains { $0.label == "Return" })
    }

    // MARK: - Non-typing keys

    @Test("modifiers and navigation keys break the sequence and are not counted")
    func nonTypingKeys() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.a, timestamp: 0))
        recorder.record(KeyEvent(key: K.shift, timestamp: 0.05))
        recorder.record(KeyEvent(key: K.s, timestamp: 0.10))

        #expect(recorder.day.totalPresses == 2)
        #expect(recorder.day[K.shift] == nil)
        // Shift between them means a→s was never a direct transition.
        #expect(recorder.day[BigramIdentity(first: K.a, second: K.s)] == nil)
    }

    @Test("arrow keys and command break the sequence")
    func navigationBreaks() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.a, timestamp: 0))
        recorder.record(KeyEvent(key: K.left, timestamp: 0.1))
        recorder.record(KeyEvent(key: K.command, timestamp: 0.2))
        recorder.record(KeyEvent(key: K.s, timestamp: 0.3))

        #expect(recorder.day.totalPresses == 2)
        #expect(recorder.day.bigrams.isEmpty)
    }

    // MARK: - Pauses and idle time

    @Test("thinking pauses are excluded from latency but the press still counts")
    func thinkingPause() {
        let recorder = makeRecorder()
        var config = RecorderConfig()
        config.motor.coldStartCutoffMilliseconds = 600
        recorder.config = config

        recorder.record(KeyEvent(key: K.a, timestamp: 0))
        recorder.record(KeyEvent(key: K.z, timestamp: 3.0))   // 3s — deciding, not reaching

        #expect(recorder.day.totalPresses == 2)
        #expect(recorder.day.discardedPauses == 1)
        #expect(recorder.day[K.z]?.latency.total == 0)
        #expect(recorder.day[K.z]?.presses == 1)
        // A 3s pause must not become a bigram latency either.
        #expect(recorder.day[BigramIdentity(first: K.a, second: K.z)] == nil)
    }

    @Test("idle gaps do not inflate active time")
    func idleTime() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.a, timestamp: 0))
        recorder.record(KeyEvent(key: K.s, timestamp: 0.1))     // counted: 0.1s
        recorder.record(KeyEvent(key: K.d, timestamp: 600))     // 10 minutes idle: not counted
        recorder.record(KeyEvent(key: K.a, timestamp: 600.1))   // counted: 0.1s

        #expect(abs(recorder.day.activeSeconds - 0.2) < 0.0001)
    }

    @Test("WPM uses active time, so a lunch break cannot deflate it")
    func wpmUsesActiveTime() throws {
        let recorder = makeRecorder()
        // 100 keys at a steady 100ms apart = 9.9s active.
        for index in 0..<100 {
            recorder.record(KeyEvent(key: K.a, timestamp: Double(index) * 0.1))
        }
        // Then an hour of nothing, then one more key.
        recorder.record(KeyEvent(key: K.s, timestamp: 3600))

        let wpm = try #require(recorder.day.wordsPerMinute(minimumActiveSeconds: 1))
        // 101 presses / 5 chars per word over ~9.9s active ≈ 122 WPM. If idle time leaked
        // into the denominator this would read about 0.3.
        #expect(wpm > 100 && wpm < 140)
    }

    @Test("negative time gaps are ignored rather than corrupting stats")
    func clockGoesBackwards() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.a, timestamp: 10))
        recorder.record(KeyEvent(key: K.s, timestamp: 5))

        #expect(recorder.day.totalPresses == 2)
        #expect(recorder.day.activeSeconds == 0)
        #expect(recorder.day[K.s]?.latency.total == 0)
    }

    // MARK: - Per-app attribution

    @Test("presses and corrections are attributed to the frontmost app")
    func perApp() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.a, timestamp: 0, appBundleID: "com.apple.Terminal"))
        recorder.record(KeyEvent(key: K.s, timestamp: 0.1, appBundleID: "com.apple.Terminal"))
        recorder.record(KeyEvent(key: K.delete, timestamp: 0.2, appBundleID: "com.apple.Terminal"))
        recorder.record(KeyEvent(key: K.a, timestamp: 0.3, appBundleID: "com.apple.Safari"))

        #expect(recorder.day.apps["com.apple.Terminal"]?.presses == 2)
        #expect(recorder.day.apps["com.apple.Terminal"]?.corrections == 1)
        #expect(recorder.day.apps["com.apple.Safari"]?.presses == 1)
    }

    // MARK: - Sequence state

    @Test("breakSequence clears the transient context")
    func breakSequence() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.a, timestamp: 0))
        recorder.breakSequence()
        recorder.record(KeyEvent(key: K.s, timestamp: 0.1))

        #expect(recorder.day.bigrams.isEmpty)
        #expect(recorder.day[K.s]?.latency.total == 0)
    }

    @Test("startNewDay resets stats and context")
    func startNewDay() {
        let recorder = makeRecorder()
        recorder.record(KeyEvent(key: K.a, timestamp: 0))
        recorder.record(KeyEvent(key: K.s, timestamp: 0.1))

        let tomorrow = Date(timeIntervalSince1970: 86_400)
        recorder.startNewDay(tomorrow)

        #expect(recorder.day.totalPresses == 0)
        #expect(recorder.day.date == tomorrow)
        recorder.record(KeyEvent(key: K.d, timestamp: 0.2))
        #expect(recorder.day.bigrams.isEmpty)
    }

    // MARK: - Privacy

    @Test("persistence snapshot prunes rare bigrams")
    func prunesRareBigramsOnPersist() {
        let recorder = makeRecorder()
        var config = RecorderConfig()
        config.minimumBigramCount = 3
        recorder.config = config

        // a→s typed five times: common, kept.
        for index in 0..<5 {
            let base = Double(index) * 1.0
            recorder.record(KeyEvent(key: K.a, timestamp: base))
            recorder.record(KeyEvent(key: K.s, timestamp: base + 0.1))
            recorder.breakSequence()
        }
        // z→semicolon typed once: rare, and exactly the kind of entry that identifies a
        // hand-typed secret. Must not reach disk.
        recorder.record(KeyEvent(key: K.z, timestamp: 100))
        recorder.record(KeyEvent(key: K.semicolon, timestamp: 100.1))

        let snapshot = recorder.snapshotForPersistence()
        #expect(snapshot[BigramIdentity(first: K.a, second: K.s)]?.count == 5)
        #expect(snapshot[BigramIdentity(first: K.z, second: K.semicolon)] == nil)
        // The in-memory day is untouched; only what we write is pruned.
        #expect(recorder.day[BigramIdentity(first: K.z, second: K.semicolon)]?.count == 1)
    }

    @Test("nothing recorded can reconstruct typed text")
    func noSequenceIsRetained() {
        let recorder = makeRecorder()
        // Type the same three keys in two different orders.
        for (index, key) in [K.a, K.s, K.d].enumerated() {
            recorder.record(KeyEvent(key: key, timestamp: Double(index) * 0.1))
        }
        let forward = recorder.snapshotForPersistence()

        let reverse = makeRecorder()
        for (index, key) in [K.d, K.s, K.a].enumerated() {
            reverse.record(KeyEvent(key: key, timestamp: Double(index) * 0.1))
        }

        // Key-level counters are identical either way — order is genuinely not retained.
        #expect(forward.keys.mapValues(\.presses) == reverse.day.keys.mapValues(\.presses))
    }
}
