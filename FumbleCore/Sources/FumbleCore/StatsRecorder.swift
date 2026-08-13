import Foundation

/// One keystroke, as handed to the recorder. Carries no character — only which physical key,
/// when, and enough provenance to decide whether it counts.
public struct KeyEvent: Equatable, Sendable {
    public let key: KeyIdentity
    /// Monotonic seconds. Must not jump backwards; the recorder ignores negative gaps.
    public let timestamp: Double
    /// OS autorepeat from a held-down key. Not typing.
    public let isAutorepeat: Bool
    /// Injected by software (`CGEventPost`) rather than a human on a keyboard.
    public let isSynthetic: Bool
    /// True while a password field has focus — the event is counted as rejected and dropped.
    public let isSecureInput: Bool
    public let appBundleID: String?

    public init(
        key: KeyIdentity,
        timestamp: Double,
        isAutorepeat: Bool = false,
        isSynthetic: Bool = false,
        isSecureInput: Bool = false,
        appBundleID: String? = nil
    ) {
        self.key = key
        self.timestamp = timestamp
        self.isAutorepeat = isAutorepeat
        self.isSynthetic = isSynthetic
        self.isSecureInput = isSecureInput
        self.appBundleID = appBundleID
    }
}

public struct RecorderConfig: Sendable {
    /// How the motor-vs-think split is decided. See `MotorFilter` — the threshold is learned
    /// per transition, per person, rather than being one global cutoff for everyone.
    public var motor = MotorFilter.Config()
    /// A gap longer than this ends the active-typing session, so idle time never inflates
    /// the WPM denominator. Distinct from the motor filter: a 2s think still counts as active
    /// typing time (it's part of your rhythm) but its latency is not a reach.
    public var idleThresholdSeconds: Double = 5
    /// Bigrams below this count are dropped on persist. See `DayStats.pruneRareBigrams`.
    public var minimumBigramCount: UInt64 = 3

    public init() {}
}

/// The heart of Fumble: a pure state machine from keystrokes to aggregates.
///
/// It holds exactly two things about the past — the previous key and its timestamp — and
/// both live in memory only. That is the whole reason the design is defensible: there is no
/// buffer, no sequence, nothing to flush. What persists is `day`, which is counters.
public final class StatsRecorder {

    public private(set) var day: DayStats
    public var config: RecorderConfig

    /// Transient: needed to compute one latency and attribute one correction. Never written.
    private var previousKey: KeyIdentity?
    private var previousTimestamp: Double?

    public init(day: DayStats, config: RecorderConfig = RecorderConfig()) {
        self.day = day
        self.config = config
    }

    /// Clears the transient bigram/latency context.
    ///
    /// Call on any discontinuity — app switch, wake from sleep, secure input beginning or
    /// ending. Without it, the pair straddling the gap would be recorded as a bigram that
    /// the user never typed, and the intervening seconds as its latency.
    public func breakSequence() {
        previousKey = nil
        previousTimestamp = nil
    }

    public func startNewDay(_ date: Date) {
        day = DayStats(date: date)
        breakSequence()
    }

    public func record(_ event: KeyEvent) {
        // --- Rejections, counted for auditability rather than silently dropped. ---

        if event.isSecureInput {
            day.rejectedSecureInput += 1
            // Sequence break: the keys either side of a password are not a real bigram.
            breakSequence()
            return
        }
        if event.isSynthetic {
            day.rejectedSynthetic += 1
            breakSequence()
            return
        }
        if event.isAutorepeat {
            day.rejectedAutorepeat += 1
            // Deliberately no sequence break — a held key is a continuation, and the next
            // real keystroke's latency from it is still meaningful.
            return
        }

        // --- Corrections. ---

        // A backspace implies the key before it was wrong. This is a proxy, not truth: it
        // also fires when you rewrite a correctly-typed word. It holds up in aggregate
        // because deliberate rewrites are spread across keys while genuine fumbles
        // concentrate on the same few, which is exactly the signal we rank on.
        if event.key.isBackspace {
            if let previous = previousKey, previous.isTypingKey {
                day.keys[previous.keyCode, default: KeyStat()].corrections += 1
                day.totalCorrections += 1
                if let bundleID = event.appBundleID {
                    day.apps[bundleID, default: AppStat()].corrections += 1
                }
            }
            // Backspace is not itself a typed key, and it must not become the first half of
            // a bigram — "the key after a delete" is a correction artefact, not a transition.
            breakSequence()
            return
        }

        // Modifiers, arrows and function keys are real presses but not typing. They break the
        // sequence so that e.g. Cmd+Tab away and back doesn't fabricate a bigram.
        guard event.key.isTypingKey else {
            breakSequence()
            return
        }

        // --- The typing path. ---

        let gapSeconds = previousTimestamp.map { event.timestamp - $0 }

        day.totalPresses += 1
        day.keys[event.key.keyCode, default: KeyStat()].presses += 1
        if let bundleID = event.appBundleID {
            day.apps[bundleID, default: AppStat()].presses += 1
        }

        if let gap = gapSeconds, gap >= 0, let previous = previousKey {
            let milliseconds = gap * 1000

            // Active time: only gaps below the idle threshold count toward the WPM denominator.
            if gap <= config.idleThresholdSeconds {
                day.activeSeconds += gap
                if let bundleID = event.appBundleID {
                    day.apps[bundleID, default: AppStat()].activeSeconds += gap
                }
            }

            // Classify the gap against the user's own history before recording it as a reach.
            // The decision reads only already-accepted samples, so it's computed before we add
            // this one — no self-reference.
            let decision = MotorFilter(config: config.motor).classify(
                gapMilliseconds: milliseconds,
                previous: previous,
                current: event.key,
                day: day
            )

            switch decision {
            case .motor(let tier):
                day.keys[event.key.keyCode, default: KeyStat()].latency.add(milliseconds: milliseconds)
                day.motorLatency.add(milliseconds: milliseconds)
                day.motorClassification.record(tier)

                let bigram = BigramIdentity(first: previous, second: event.key)
                day.bigrams[bigram.storageKey, default: BigramStat()].count += 1
                day.bigrams[bigram.storageKey]?.latency.add(milliseconds: milliseconds)

            case .think:
                day.discardedPauses += 1
            }
        }

        previousKey = event.key
        previousTimestamp = event.timestamp
    }

    /// The day, pruned and ready to write.
    public func snapshotForPersistence() -> DayStats {
        var snapshot = day
        snapshot.pruneRareBigrams(minimumCount: config.minimumBigramCount)
        return snapshot
    }
}
