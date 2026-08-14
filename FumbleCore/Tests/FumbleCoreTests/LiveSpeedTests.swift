import Foundation
import Testing
@testable import FumbleCore

@Suite("LiveSpeed")
struct LiveSpeedTests {

    @Test("reports nil until there are enough recent keys")
    func needsSamples() {
        var live = LiveSpeed()
        live.record(timestamp: 0)
        live.record(timestamp: 0.1)
        // Two keys isn't enough to call a rate.
        #expect(live.wordsPerMinute(now: 0.1) == nil)
    }

    @Test("computes a plausible rate across the typed span")
    func plausibleRate() throws {
        var live = LiveSpeed()
        // 9 keystrokes at a steady 100ms apart = 8 intervals over 0.8s.
        for i in 0..<9 { live.record(timestamp: Double(i) * 0.1) }
        let wpm = try #require(live.wordsPerMinute(now: 0.8))
        // 8 intervals / 5 chars-per-word over 0.8s ≈ 120 WPM.
        #expect(wpm > 110 && wpm < 130)
    }

    @Test("goes idle when typing stops")
    func idle() {
        var live = LiveSpeed(windowSeconds: 8, idleGapSeconds: 2)
        for i in 0..<5 { live.record(timestamp: Double(i) * 0.1) }
        // Last key at 0.4s; three seconds later you've clearly stopped.
        #expect(live.wordsPerMinute(now: 3.5) == nil)
        // But right after the last key, it still reports.
        #expect(live.wordsPerMinute(now: 0.5) != nil)
    }

    @Test("old keystrokes fall out of the window")
    func windowTrims() throws {
        var live = LiveSpeed(windowSeconds: 8, idleGapSeconds: 2)
        // A burst long ago, then a fresh burst — only the fresh one should count.
        for i in 0..<20 { live.record(timestamp: Double(i) * 0.05) }   // ends at 0.95s
        for i in 0..<4 { live.record(timestamp: 100 + Double(i) * 0.2) }   // 100.0–100.6s

        let wpm = try #require(live.wordsPerMinute(now: 100.6))
        // 4 keys at 200ms apart = 3 intervals over 0.6s ≈ 60 WPM. If the old 50ms burst leaked
        // in, this would read far higher.
        #expect(wpm > 50 && wpm < 70)
    }

    @Test("the gap to the refresh tick doesn't deflate the number")
    func spanIsTypedNotToNow() throws {
        var live = LiveSpeed(windowSeconds: 8, idleGapSeconds: 2)
        for i in 0..<5 { live.record(timestamp: Double(i) * 0.1) }   // 5 keys, span 0.4s
        // Refresh fires 1.5s after the last key (still within idle gap): rate is measured over
        // the 0.4s of typing, not stretched to 1.9s.
        let atLastKey = try #require(live.wordsPerMinute(now: 0.4))
        let laterTick = try #require(live.wordsPerMinute(now: 1.9))
        #expect(abs(atLastKey - laterTick) < 0.001)
    }
}

@Suite("Timeframe")
struct TimeframeTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test("today is a single day")
    func today() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let range = Timeframe.today.range(now: now, calendar: calendar)
        #expect(range.start == range.end)
        #expect(range.end == calendar.startOfDay(for: now))
    }

    @Test("week spans seven inclusive days")
    func week() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let range = Timeframe.week.range(now: now, calendar: calendar)
        let days = calendar.dateComponents([.day], from: range.start, to: range.end).day
        #expect(days == 6)   // start..end inclusive = 7 days
    }

    @Test("all time reaches back to the distant past")
    func all() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(Timeframe.all.range(now: now, calendar: calendar).start == .distantPast)
    }

    @Test("every case has a label")
    func labels() {
        #expect(Timeframe.allCases.allSatisfy { !$0.label.isEmpty })
    }
}
