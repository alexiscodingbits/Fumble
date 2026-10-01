import AppKit
import FumbleCore
import FumbleUI
import Foundation
import Observation

/// Owns the tap, the recorder, persistence, and the day boundary. The single place where the
/// app's moving parts are wired together.
@MainActor
@Observable
public final class AppCoordinator {

    /// The app's single coordinator. A shared instance (rather than view-owned state) lets the
    /// app delegate start capture at launch even if the menu-bar label's onAppear never fires
    /// (crowded menu bars on notched MacBooks can keep the item off-screen).
    public static let shared = AppCoordinator()

    public private(set) var viewState: MenuViewState
    public private(set) var hasPermission: Bool
    public private(set) var tapFailedToStart = false

    /// Instantaneous typing speed, WPM, or nil when idle. Updated on a fast tick.
    public private(set) var liveWPM: Double?

    /// Which window the aggregate stats cover. Persisted, applied live.
    public var selectedTimeframe: Timeframe {
        didSet {
            UserDefaults.standard.set(selectedTimeframe.rawValue, forKey: Self.timeframeKey)
            rebuildViewState()
        }
    }
    private static let timeframeKey = "selectedTimeframe"

    /// The trainer's mastery target, in WPM. keybr's default is 35.
    public var targetWPM: Double {
        didSet {
            UserDefaults.standard.set(targetWPM, forKey: Self.targetWPMKey)
            // Settings promises this applies live; the cached trainer must hear about it or
            // mastery/unlock keeps using the stale target until relaunch.
            cachedTrainer?.updateTarget(wpm: targetWPM)
        }
    }
    private static let targetWPMKey = "targetWPM"

    /// keybr's "unlock a next key only when the previous keys are also above the target speed".
    public var strictUnlock: Bool {
        didSet {
            UserDefaults.standard.set(strictUnlock, forKey: "strictUnlock")
            cachedTrainer?.updateStrictUnlock(strictUnlock)
        }
    }

    // MARK: Practice preferences (all persisted, applied live)

    /// How mistakes behave in practice: advance-through (fix with backspace) or keybr-style
    /// stop-until-correct. Stored as the DrillState.ErrorHandling raw value.
    public var typingAssistRaw: String {
        didSet { UserDefaults.standard.set(typingAssistRaw, forKey: "typingAssist") }
    }
    /// Whether the first-run practice intro has been shown (and dismissed) once.
    public var hasSeenPracticeIntro: Bool {
        didSet { UserDefaults.standard.set(hasSeenPracticeIntro, forKey: "hasSeenPracticeIntro") }
    }
    var soundMode: SoundMode {
        didSet { UserDefaults.standard.set(soundMode.rawValue, forKey: "soundMode") }
    }
    public var soundVolume: Double {
        didSet { UserDefaults.standard.set(soundVolume, forKey: "soundVolume") }
    }
    public var showWhitespaceDots: Bool {
        didSet { UserDefaults.standard.set(showWhitespaceDots, forKey: "showWhitespaceDots") }
    }
    var cursorStyle: CursorStyle {
        didSet { UserDefaults.standard.set(cursorStyle.rawValue, forKey: "cursorStyle") }
    }
    var appearance: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            appearance.apply()
        }
    }
    /// Daily practice goal in minutes; 0 = off. A reminder, never a limit.
    /// US or UK spellings in the word pool. Persisted; read when the next lesson is generated.
    public var spelling: WordList.Spelling {
        didSet { UserDefaults.standard.set(spelling.rawValue, forKey: "spelling") }
    }

    /// Words per lesson for the word-based modes (trainer, weak spots, custom text). Read when
    /// the next passage is generated, so a change lands on the next lesson.
    public var lessonWordCount: Int {
        didSet { UserDefaults.standard.set(lessonWordCount, forKey: "lessonWordCount") }
    }

    public var dailyGoalMinutes: Int {
        didSet { UserDefaults.standard.set(dailyGoalMinutes, forKey: "dailyGoalMinutes") }
    }
    /// The user's custom practice text (Custom text mode). Persisted as a plain file in the
    /// documented data directory — NOT in UserDefaults — so it is visible via "Show data",
    /// removed by "Delete all data", and disclosed in PRIVACY.md. This is content the user
    /// chose to store; it must live where the privacy story says data lives.
    public var customPracticeText: String {
        didSet {
            let url = customTextURL
            if customPracticeText.isEmpty {
                try? FileManager.default.removeItem(at: url)
            } else {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try? customPracticeText.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
    private var customTextURL: URL {
        store.directory.deletingLastPathComponent().appendingPathComponent("custom-text.txt")
    }

    let sounds = SoundPlayer()

    /// Play feedback for a practice keystroke, honouring the sound settings. Every physical
    /// press clicks (you did press a key); mistakes are signalled visually only.
    public func practiceKeystrokeFeedback() {
        if soundMode.playsKeys { sounds.key(volume: soundVolume) }
    }

    private let store: StatsStore
    private let recorder: StatsRecorder
    private var tap: EventTap?

    private var flushTimer: Timer?
    private var refreshTimer: Timer?
    private var liveTimer: Timer?

    /// Rolling buffer of recent keystroke timestamps for the live-speed readout. In memory only.
    private var liveSpeed = LiveSpeed()

    /// Persist cadence. Frequent enough that a crash costs little, rare enough that we aren't
    /// writing a JSON file on every keystroke.
    private let flushInterval: TimeInterval = 30
    /// The dropdown is only visible when open, but the menu-bar WPM figure is always on screen.
    private let refreshInterval: TimeInterval = 5
    /// Live WPM has to feel live, so it ticks fast — but it only touches the in-memory buffer,
    /// not the full aggregate rebuild.
    private let liveInterval: TimeInterval = 1

    /// True when the recorder has data that isn't on disk yet.
    private var isDirty = false

    public init(store: StatsStore = .default()) {
        self.store = store

        self.selectedTimeframe = UserDefaults.standard.string(forKey: Self.timeframeKey)
            .flatMap(Timeframe.init(rawValue:)) ?? .today
        let storedTarget = UserDefaults.standard.double(forKey: Self.targetWPMKey)
        self.targetWPM = storedTarget > 0 ? storedTarget : 35
        self.strictUnlock = UserDefaults.standard.object(forKey: "strictUnlock") != nil
            ? UserDefaults.standard.bool(forKey: "strictUnlock") : true

        let defaults = UserDefaults.standard
        // Stop-until-correct by default: it's the keybr behaviour that actually retrains a
        // finger, and new users expect a coach to hold the line rather than autocorrect past it.
        self.typingAssistRaw = defaults.string(forKey: "typingAssist") ?? "stopUntilCorrect"
        self.hasSeenPracticeIntro = defaults.bool(forKey: "hasSeenPracticeIntro")
        self.soundMode = defaults.string(forKey: "soundMode").flatMap(SoundMode.init(rawValue:)) ?? .off
        self.soundVolume = defaults.object(forKey: "soundVolume") != nil ? defaults.double(forKey: "soundVolume") : 0.5
        self.showWhitespaceDots = defaults.object(forKey: "showWhitespaceDots") != nil
            ? defaults.bool(forKey: "showWhitespaceDots") : true
        self.cursorStyle = defaults.string(forKey: "cursorStyle").flatMap(CursorStyle.init(rawValue:)) ?? .line
        self.appearance = defaults.string(forKey: "appearance").flatMap(AppearanceMode.init(rawValue:)) ?? .system
        // Default spelling from the system region: UK-style for the UK, Ireland, Australia and
        // New Zealand; US otherwise. Overridable in Settings.
        self.spelling = defaults.string(forKey: "spelling").flatMap(WordList.Spelling.init(rawValue:))
            ?? (["GB", "IE", "AU", "NZ"].contains(Locale.current.region?.identifier ?? "") ? .uk : .us)
        self.lessonWordCount = defaults.object(forKey: "lessonWordCount") != nil
            ? defaults.integer(forKey: "lessonWordCount") : 25
        self.dailyGoalMinutes = defaults.object(forKey: "dailyGoalMinutes") != nil
            ? defaults.integer(forKey: "dailyGoalMinutes") : 15
        // Custom text lives as a file in the data directory (see customPracticeText). A one-time
        // migration rescues any text stored by the brief UserDefaults-backed version.
        let customTextFile = store.directory.deletingLastPathComponent()
            .appendingPathComponent("custom-text.txt")
        if let migrated = defaults.string(forKey: "customPracticeText"), !migrated.isEmpty {
            self.customPracticeText = migrated
            defaults.removeObject(forKey: "customPracticeText")
            try? FileManager.default.createDirectory(
                at: customTextFile.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? migrated.write(to: customTextFile, atomically: true, encoding: .utf8)
        } else {
            self.customPracticeText = (try? String(contentsOf: customTextFile, encoding: .utf8)) ?? ""
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Resume today's data if the app was restarted mid-day, so a relaunch doesn't reset the
        // numbers and make the app look like it lost the morning. Matching is by LOCAL calendar
        // day of the embedded date — not filename or exact midnight equality — so a timezone
        // change between sessions (travel) still resumes rather than silently overwriting the
        // day's file with a fresh empty one. Duplicates from mixed-timezone history merge.
        let todaysFiles = store.loadAll().filter { calendar.isDate($0.date, inSameDayAs: today) }
        let existing: DayStats? = todaysFiles.isEmpty ? nil
            : (todaysFiles.count == 1 ? todaysFiles[0] : DayStats.merging(todaysFiles, date: today))
        self.recorder = StatsRecorder(day: existing.map { day in
            var normalized = day
            normalized.date = today   // re-anchor to the current zone's midnight
            return normalized
        } ?? DayStats(date: today))

        // Exclude our own practice window from capture: drill text is synthetic and aimed at
        // your weak keys, so counting it would corrupt the very model that generated it — and
        // make the "practice doesn't affect your daily stats" promise false.
        if let ownBundleID = Bundle.main.bundleIdentifier {
            recorder.config.excludedBundleIDs = [ownBundleID]
        }

        self.hasPermission = EventTap.hasPermission
        self.viewState = MenuViewState.build(
            day: existing,
            hasPermission: EventTap.hasPermission
        )
    }

    private var permissionTimer: Timer?

    // MARK: - Lifecycle

    /// Entry point. Either begins capture (if already permitted) or starts watching for the
    /// permission to be granted. Idempotent.
    public func start() {
        appearance.apply()   // NSApp exists by now; init may run before the app object does
        hasPermission = EventTap.hasPermission
        if hasPermission {
            beginCapture()
        } else {
            // Trigger the system prompt on first ever launch, then watch for the grant. macOS
            // shows the dialog only once per app identity; after that the user must use Settings.
            EventTap.requestPermission()
            beginPermissionWatch()
        }
        rebuildViewState()
    }

    /// Polls for the permission and self-starts the moment it appears.
    ///
    /// This is the fix for Input Monitoring's worst UX trap: granting in System Settings does
    /// not notify a running app, and `CGPreflightListenEventAccess` can keep returning the
    /// cached answer, so a naive "check once on launch" app looks permanently locked out even
    /// after the user has said yes. Polling on a timer means the app notices within a couple of
    /// seconds however the grant was made — button, Settings toggle, or `tccutil`.
    private func beginPermissionWatch() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard EventTap.hasPermission else { return }
                self.hasPermission = true
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
                self.beginCapture()
                self.rebuildViewState()
            }
        }
    }

    /// Creates the tap and the flush/refresh timers. Only called once we have permission.
    private func beginCapture() {
        guard tap == nil else { return }   // idempotent — don't stack taps

        let tap = EventTap { [weak self] event in
            self?.ingest(event)
        }
        tap.onDisabled = { [weak self] in
            // The OS disabled the tap and we re-armed it; whatever was typed in the gap is
            // lost, so the pair spanning it must not become a bigram.
            self?.recorder.breakSequence()
        }
        if tap.start() {
            self.tap = tap
            tapFailedToStart = false
        } else {
            // Preflight said yes but the tap wouldn't start — usually the grant needs a
            // relaunch to take effect. Keep watching; a restart or re-grant will recover.
            tapFailedToStart = true
            beginPermissionWatch()
            return
        }

        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildViewState() }
        }
        liveTimer = Timer.scheduledTimer(withTimeInterval: liveInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLiveWPM() }
        }

        // Sleep/wake are discontinuities: the gap across them is not a typing latency.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flush()
                self?.recorder.breakSequence()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recorder.breakSequence()
                // Belt and braces: macOS sometimes disables taps across sleep without ever
                // delivering tapDisabledByTimeout. Re-arming on wake is idempotent and free.
                self?.tap?.reenable()
            }
        }

        // An app switch is a typing discontinuity even when no key is pressed during it —
        // Cmd-Tab by mouse, or clicking another window. Without this, the last key in app A and
        // the first key in app B fabricate a bigram that was never typed.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recorder.breakSequence() }
        }
    }

    /// Called from `applicationWillTerminate`. Without this the last flush interval is lost.
    public func shutDown() {
        flush()
        tap?.stop()
        flushTimer?.invalidate()
        refreshTimer?.invalidate()
        liveTimer?.invalidate()
        permissionTimer?.invalidate()
    }

    public func requestPermission() {
        EventTap.requestPermission()
        beginPermissionWatch()
    }

    public func openPrivacySettings() {
        EventTap.openPrivacySettings()
    }

    // MARK: - Ingest

    private func ingest(_ event: KeyEvent) {
        rollDayIfNeeded()
        recorder.record(event)
        isDirty = true

        // Feed the live-speed buffer with the same events that count as real typing — so the
        // live readout is honest for the same reasons the average is (no pastes, no autorepeat,
        // and no drill keystrokes: the menu-bar number is your real-world speed, and practice
        // is excluded from the day for the same reason).
        let isSelfPractice = event.appBundleID.map { recorder.config.excludedBundleIDs.contains($0) } ?? false
        if event.key.isTypingKey, !event.isSynthetic, !event.isSecureInput, !event.isAutorepeat,
           !isSelfPractice {
            liveSpeed.record(timestamp: event.timestamp)
        }
    }

    private func updateLiveWPM() {
        let now = ProcessInfo.processInfo.systemUptime
        let value = liveSpeed.wordsPerMinute(now: now)
        // Only publish on change, so the menu bar isn't redrawn every second while idle.
        if value != liveWPM { liveWPM = value }
    }

    /// Rolls over at local midnight. Checked on ingest AND on the refresh timer (so the menu
    /// bar doesn't show yesterday as "today" until the first post-midnight keystroke).
    ///
    /// Same-day is judged with `isDate(_:inSameDayAs:)`, NOT exact midnight equality: two
    /// midnights of the same local day in different timezones are different Dates, and exact
    /// comparison made a mere timezone change trigger a spurious rollover that discarded the
    /// day's in-memory stats and overwrote its file.
    private func rollDayIfNeeded() {
        let calendar = Calendar.current
        guard !calendar.isDate(Date(), inSameDayAs: recorder.day.date) else { return }
        flush()
        recorder.startNewDay(calendar.startOfDay(for: Date()))
        isDirty = false
    }

    private func flush() {
        guard isDirty else { return }
        do {
            try store.save(recorder.snapshotForPersistence())
            isDirty = false
        } catch {
            // Persistence failure must not kill capture; the in-memory day survives and the
            // next flush retries. Logged rather than surfaced — a transient write error is not
            // worth a modal.
            NSLog("Fumble: failed to persist day stats: \(error.localizedDescription)")
        }
    }

    private func rebuildViewState() {
        rollDayIfNeeded()   // timer-driven too, so midnight flips "Today" without a keystroke
        viewState = MenuViewState.build(day: aggregateForSelectedTimeframe(), hasPermission: hasPermission)
        refreshTrendIfStale()
    }

    /// Daily WPM over the recent past, for the dropdown's trend chart. Oldest first, today last.
    private(set) var wpmTrend: [TrendPoint] = []
    private var trendRefreshedAt: Date = .distantPast

    /// Recomputed at most once a minute — it reads every day file, and the 5s view refresh
    /// doesn't need day-granularity data that fresh.
    private func refreshTrendIfStale() {
        guard Date().timeIntervalSince(trendRefreshedAt) > 60 else { return }
        trendRefreshedAt = Date()
        flush()
        // Group by calendar day and merge before charting: a timezone change (travel) can leave
        // two day files whose dates land on the same local day, and duplicate x-values render
        // as a vertical smear with doubled "today" points.
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.loadAll()) { calendar.startOfDay(for: $0.date) }
        wpmTrend = grouped.keys.sorted().suffix(14).compactMap { day in
            guard let days = grouped[day] else { return nil }
            let merged = days.count == 1 ? days[0] : DayStats.merging(days, date: day)
            return merged.wordsPerMinute().map { TrendPoint(date: day, wpm: $0) }
        }
    }

    /// The `DayStats` the aggregate view should reflect, per the selected timeframe.
    ///
    /// "Today" uses the live in-memory recorder so the numbers move as you type. Longer windows
    /// flush first (so today's in-progress data is included), then merge the day files in range.
    /// Reloading from disk on each 5s refresh is fine — it's a handful of small files.
    private func aggregateForSelectedTimeframe() -> DayStats? {
        switch selectedTimeframe {
        case .today:
            return recorder.day
        default:
            flush()
            let (start, end) = selectedTimeframe.range(now: Date())
            let days = store.load(from: start, to: end)
            guard !days.isEmpty else { return nil }
            return DayStats.merging(days, date: end)
        }
    }

    // MARK: - Daily goal

    private static let practiceLogKey = "practicedSecondsByDay"

    /// Day keys from calendar components at call time — a cached formatter freezes its timezone
    /// and mis-credits practice minutes after a zone change (same bug as the day files had).
    private static func dayKey(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
        return Calendar.current.date(from: components)
    }

    /// Practice seconds per day, persisted as ["yyyy-MM-dd": seconds]. Small forever: one entry
    /// per practised day.
    private var practiceLog: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: Self.practiceLogKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.practiceLogKey) }
    }

    /// Called by practice surfaces as time accrues (per completed passage).
    public func recordPracticeTime(seconds: Double) {
        guard seconds > 0, seconds.isFinite else { return }
        let key = Self.dayKey(for: Date())
        var log = practiceLog
        log[key, default: 0] += seconds
        practiceLog = log
        goalVersion += 1   // poke observers; UserDefaults isn't @Observable
    }

    /// Bumped on every practice-time write so SwiftUI re-reads the derived goal values.
    public private(set) var goalVersion = 0

    /// Bumped by deleteAllData; practice surfaces re-key on it so in-flight drills reset rather
    /// than folding pre-deletion samples back into a fresh trainer/practice log.
    public private(set) var dataEpoch = 0

    public var todayPracticeSeconds: Double {
        practiceLog[Self.dayKey(for: Date())] ?? 0
    }

    /// 0…1 toward today's goal; nil when the goal is off.
    public var goalProgress: Double? {
        PracticeGoal.progress(practicedSeconds: todayPracticeSeconds,
                              goalSeconds: Double(dailyGoalMinutes) * 60)
    }

    public var currentStreak: Int {
        let calendar = Calendar.current
        var byDay: [Date: Double] = [:]
        for (key, seconds) in practiceLog {
            if let date = Self.date(fromDayKey: key) {
                byDay[calendar.startOfDay(for: date)] = seconds
            }
        }
        return PracticeGoal.streak(practicedSecondsByDay: byDay,
                                   goalSeconds: Double(dailyGoalMinutes) * 60,
                                   today: Date(), calendar: calendar)
    }

    // MARK: - Drills

    /// Build a drill targeting the user's current weak spots, using the richest data available:
    /// today if it's substantial, otherwise the merged history. Falls back to an unweighted
    /// warm-up when there isn't enough data to rank anything yet.
    ///
    /// Targets combine BOTH weakness signals from real typing: slow keys/transitions (latency)
    /// and mistype-prone keys (the ones you backspace most). A key can be fast but sloppy —
    /// accuracy problems deserve drilling as much as speed problems.
    public func makeDrill(wordCount: Int? = nil) -> DrillPlan {
        let wordCount = wordCount ?? lessonWordCount
        let best = bestAnalysis()
        var targets = best.map { DrillGenerator.Targets(analysis: $0.analysis) } ?? DrillGenerator.Targets()

        var correctedLabels: [String] = []
        if let (analysis, day) = best {
            let corrected = analysis.mostCorrected(in: day, limit: 3)
            targets.keyCodes.formUnion(corrected.map { $0.0.keyCode })
            correctedLabels = corrected.map { $0.0.label }
        }

        var rng = SystemRandomNumberGenerator()
        // The drill pool merges both lists: `common` carries the programmer-ish words (commit,
        // struct, rebase), `english` the breadth. Order-preserving dedup keeps generation stable.
        var seen = Set<String>()
        let pool = (WordList.common + WordList.english(spelling: spelling)).filter { seen.insert($0).inserted }
        let text = DrillGenerator(words: pool).generate(targets: targets, wordCount: wordCount, using: &rng)

        // Focus labels: the weak keys and transitions this drill leans on, for display.
        var focus: [String] = []
        if let (analysis, _) = best {
            focus += analysis.keys.prefix(5).map(\.label)
            focus += correctedLabels.filter { !focus.contains($0) }
            focus += analysis.drillable.compactMap { spot -> String? in
                if case .bigram = spot.target { return spot.label }
                return nil
            }.prefix(3)
        }
        return DrillPlan(text: text, focus: focus)
    }

    /// The best weak-spot analysis we can produce right now — with the day it was computed
    /// from, so callers can pull correction stats from the same data.
    private func bestAnalysis() -> (analysis: WeakSpots.Analysis, day: DayStats)? {
        if let today = WeakSpots.analyse(recorder.day) { return (today, recorder.day) }
        flush()
        let all = store.loadAll()
        guard !all.isEmpty else { return nil }
        let merged = DayStats.merging(all, date: recorder.day.date)
        guard let analysis = WeakSpots.analyse(merged) else { return nil }
        return (analysis, merged)
    }

    /// The one trainer instance for this session. Living here (not in view @State) means pane
    /// and mode switches can't wipe lesson progress, and the expensive seed computation runs
    /// once instead of on every parent re-render.
    @ObservationIgnored private var cachedTrainer: KeyboardTrainer?

    /// URL for the persisted trainer snapshot — alongside the day files, so "show data" and
    /// "delete all" naturally cover it.
    private var trainerSnapshotURL: URL {
        store.directory.deletingLastPathComponent().appendingPathComponent("trainer.json")
    }

    /// The session trainer: restored from disk if a snapshot exists (folding in a fresh capture
    /// seed for never-drilled keys), else seeded from captured typing alone. Progress must come
    /// from the snapshot because practice keystrokes are deliberately excluded from capture.
    public func trainer() -> KeyboardTrainer {
        if let cachedTrainer { return cachedTrainer }

        var seed: [Int: Double] = [:]
        if let day = richestDay() {
            for key in KeyIdentity.alphabetByFrequency {
                if let stat = day.keys[key.keyCode], let wpm = stat.estimatedWPM() {
                    seed[key.keyCode] = wpm
                }
            }
        }
        var config = KeyboardTrainer.Config()
        config.targetWPM = targetWPM
        config.strictUnlock = strictUnlock

        let trainer: KeyboardTrainer
        if let data = try? Data(contentsOf: trainerSnapshotURL),
           let snapshot = try? JSONDecoder().decode(KeyboardTrainer.Snapshot.self, from: data) {
            trainer = KeyboardTrainer(snapshot: snapshot, seed: seed, config: config)
        } else {
            trainer = KeyboardTrainer(seed: seed, config: config)
        }
        cachedTrainer = trainer
        return trainer
    }

    /// Persist the trainer's lesson-earned state. Called after each completed lesson — the
    /// snapshot is a few KB, and losing at most one lesson to a crash is acceptable.
    public func saveTrainer() {
        guard let cachedTrainer else { return }
        do {
            try FileManager.default.createDirectory(
                at: trainerSnapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(cachedTrainer.snapshot())
            try data.write(to: trainerSnapshotURL, options: .atomic)
        } catch {
            NSLog("Fumble: failed to persist trainer snapshot: \(error.localizedDescription)")
        }
    }

    /// Today merged with all history — the widest per-key sample for seeding the trainer.
    private func richestDay() -> DayStats? {
        flush()
        let all = store.loadAll()
        if all.isEmpty { return recorder.day.totalPresses > 0 ? recorder.day : nil }
        return DayStats.merging(all, date: recorder.day.date)
    }

    /// The richest merged day, exposed for the stats pane (heatmap, weak-spot tables). Cached
    /// for 30s: SwiftUI re-evaluates the pane's body on every observed change (each keystroke
    /// while it's visible), and recomputing meant a disk flush plus a full-history decode per
    /// keystroke on the main thread.
    public func statsSnapshot() -> DayStats? {
        if let cachedStats, Date().timeIntervalSince(statsCachedAt) < 30 { return cachedStats }
        let fresh = richestDay()
        cachedStats = fresh
        statsCachedAt = Date()
        return fresh
    }
    // @ObservationIgnored: these are memoization caches written while SwiftUI evaluates a view
    // body (trainer()/statsSnapshot() are called from body) — tracking them would be
    // modify-during-update. Consumers get change signals from the underlying data instead.
    @ObservationIgnored private var cachedStats: DayStats?
    @ObservationIgnored private var statsCachedAt: Date = .distantPast

    // MARK: - Data controls

    public var dataDirectory: URL { store.directory }
    public var bytesOnDisk: UInt64 { store.totalBytesOnDisk }

    public func revealDataInFinder() {
        // The parent Fumble directory, not days/: trainer.json and custom-text.txt live beside
        // the day files, and an audit affordance that hides data would undercut its own point.
        let root = store.directory.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: root.path)
    }

    /// Deletes EVERYTHING Fumble knows: day files, the trainer snapshot, the custom practice
    /// text, and the practice-time log. "Delete all data" that quietly kept some of the data
    /// would be worse than not offering the button.
    public func deleteAllData() {
        try? store.deleteAllData()
        try? FileManager.default.removeItem(at: trainerSnapshotURL)
        try? FileManager.default.removeItem(at: customTextURL)
        customPracticeText = ""
        UserDefaults.standard.removeObject(forKey: Self.practiceLogKey)
        cachedTrainer = nil
        cachedStats = nil
        statsCachedAt = .distantPast
        dataEpoch += 1   // practice views re-key on this, so an in-flight drill can't resurrect data
        goalVersion += 1
        recorder.startNewDay(Calendar.current.startOfDay(for: Date()))
        isDirty = false
        rebuildViewState()
    }
}
