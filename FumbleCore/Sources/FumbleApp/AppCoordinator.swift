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

    public private(set) var viewState: MenuViewState
    public private(set) var hasPermission: Bool
    public private(set) var tapFailedToStart = false

    private let store: StatsStore
    private let recorder: StatsRecorder
    private var tap: EventTap?

    private var flushTimer: Timer?
    private var refreshTimer: Timer?

    /// Persist cadence. Frequent enough that a crash costs little, rare enough that we aren't
    /// writing a JSON file on every keystroke.
    private let flushInterval: TimeInterval = 30
    /// The dropdown is only visible when open, but the menu-bar WPM figure is always on screen.
    private let refreshInterval: TimeInterval = 5

    /// True when the recorder has data that isn't on disk yet.
    private var isDirty = false

    public init(store: StatsStore = .default()) {
        self.store = store

        let today = Calendar.current.startOfDay(for: Date())
        // Resume today's file if the app was restarted mid-day, so a relaunch doesn't reset
        // the numbers and make the app look like it lost the morning.
        let existing = (try? store.load(today)) ?? nil
        self.recorder = StatsRecorder(day: existing ?? DayStats(date: today))

        self.hasPermission = EventTap.hasPermission
        self.viewState = MenuViewState.build(
            day: existing,
            hasPermission: EventTap.hasPermission
        )
    }

    // MARK: - Lifecycle

    public func start() {
        hasPermission = EventTap.hasPermission
        guard hasPermission else {
            rebuildViewState()
            return
        }

        let tap = EventTap { [weak self] event in
            self?.ingest(event)
        }
        if tap.start() {
            self.tap = tap
            tapFailedToStart = false
        } else {
            tapFailedToStart = true
        }

        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildViewState() }
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
            MainActor.assumeIsolated { self?.recorder.breakSequence() }
        }

        rebuildViewState()
    }

    /// Called from `applicationWillTerminate`. Without this the last flush interval is lost.
    public func shutDown() {
        flush()
        tap?.stop()
        flushTimer?.invalidate()
        refreshTimer?.invalidate()
    }

    public func requestPermission() {
        EventTap.requestPermission()
        // The grant lands asynchronously and macOS shows the prompt only once per app
        // identity, so poll briefly rather than assuming the user acted immediately.
        Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(for: .seconds(1))
                if EventTap.hasPermission {
                    hasPermission = true
                    start()
                    return
                }
            }
        }
    }

    public func openPrivacySettings() {
        EventTap.openPrivacySettings()
    }

    // MARK: - Ingest

    private func ingest(_ event: KeyEvent) {
        rollDayIfNeeded()
        recorder.record(event)
        isDirty = true
    }

    /// Rolls over at local midnight. Checked on ingest rather than by timer so it can't be
    /// missed while the machine is asleep.
    private func rollDayIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        guard today != recorder.day.date else { return }
        flush()
        recorder.startNewDay(today)
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
        viewState = MenuViewState.build(day: recorder.day, hasPermission: hasPermission)
    }

    // MARK: - Data controls

    public var dataDirectory: URL { store.directory }
    public var bytesOnDisk: UInt64 { store.totalBytesOnDisk }

    public func revealDataInFinder() {
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: store.directory.path)
    }

    public func deleteAllData() {
        try? store.deleteAllData()
        recorder.startNewDay(Calendar.current.startOfDay(for: Date()))
        isDirty = false
        rebuildViewState()
    }
}
