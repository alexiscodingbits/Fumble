import Foundation
import Testing
@testable import FumbleCore
@testable import FumbleUI

@Suite("MenuViewState")
struct MenuViewStateTests {

    @Test("no permission takes precedence over everything else")
    func needsPermission() {
        var day = DayStats(date: Date(timeIntervalSince1970: 0))
        day.totalPresses = 5_000
        let state = MenuViewState.build(day: day, hasPermission: false)
        #expect(state.readiness == .needsPermission)
        #expect(state.barText == "—")
    }

    @Test("fresh install shows a dash, never a zero")
    func noData() {
        let state = MenuViewState.build(day: nil, hasPermission: true)
        #expect(state.readiness == .noData)
        // A brand-new install reading "0 wpm" looks like a broken app.
        #expect(state.barText == "—")
        #expect(state.wpm == "—")
    }

    @Test("a little typing shows the learning state, not an empty weak-spot list")
    func learning() throws {
        var day = DayStats(date: Date(timeIntervalSince1970: 0))
        day.totalPresses = 200
        day.activeSeconds = 30
        var stat = KeyStat()
        for _ in 0..<200 { stat.latency.add(milliseconds: 100); stat.presses += 1 }
        day.keys[0] = stat

        let state = MenuViewState.build(day: day, hasPermission: true)
        guard case .learning(let active, let required) = state.readiness else {
            Issue.record("expected .learning, got \(state.readiness)")
            return
        }
        #expect(active == 30)
        #expect(required > active)
        #expect(state.weakKeys.isEmpty)
        // The summary still populates — the user should see progress immediately.
        #expect(state.totalPresses == "200")
    }

    @Test("ready state populates rows and the bar")
    func ready() throws {
        var day = DayStats(date: Date(timeIntervalSince1970: 0))
        for keyCode in [0, 1, 2, 3, 5, 12, 13, 14] {
            var stat = KeyStat()
            for _ in 0..<200 { stat.latency.add(milliseconds: 90); stat.presses += 1 }
            day.keys[keyCode] = stat
            day.totalPresses += 200
        }
        var slow = KeyStat()
        for _ in 0..<200 { slow.latency.add(milliseconds: 300); slow.presses += 1 }
        day.keys[6] = slow
        day.totalPresses += 200
        day.activeSeconds = 900

        let state = MenuViewState.build(day: day, hasPermission: true)
        #expect(state.readiness == .ready)
        #expect(state.barText.hasSuffix("wpm"))
        #expect(state.weakKeys.first?.label == "Z")
        #expect(state.weakKeys.first?.excess.hasPrefix("+") == true)
        #expect(state.weakKeys.first?.finger == "L pinky")
    }

    @Test("row limit is respected")
    func rowLimit() {
        var day = DayStats(date: Date(timeIntervalSince1970: 0))
        // Baseline keys. These must be the majority: the baseline is the median per-key p95,
        // so a day where most keys are slow has no meaningful "relative to yourself" at all.
        for keyCode in [0, 1, 2, 3, 5, 12, 13, 14, 15, 37, 38, 40] {
            var stat = KeyStat()
            for _ in 0..<500 { stat.latency.add(milliseconds: 80); stat.presses += 1 }
            day.keys[keyCode] = stat
            day.totalPresses += 500
        }
        // Eight slow keys — more than the row limit, which is the point of the test.
        for keyCode in [6, 7, 8, 9, 11, 16, 17, 31] {
            var stat = KeyStat()
            for _ in 0..<200 { stat.latency.add(milliseconds: 320); stat.presses += 1 }
            day.keys[keyCode] = stat
            day.totalPresses += 200
        }
        day.activeSeconds = 3_600

        let state = MenuViewState.build(day: day, hasPermission: true, rowLimit: 3)
        #expect(state.weakKeys.count == 3)
    }

    @Test("diagnostics are hidden only when genuinely empty")
    func diagnostics() {
        var day = DayStats(date: Date(timeIntervalSince1970: 0))
        day.totalPresses = 100
        #expect(MenuViewState.build(day: day, hasPermission: true).diagnostics.hasAnything == false)

        day.rejectedSynthetic = 42
        let state = MenuViewState.build(day: day, hasPermission: true)
        #expect(state.diagnostics.hasAnything)
        #expect(state.diagnostics.rejectedSynthetic == "42")
    }

    @Test("app rows are ordered by volume and carry a share")
    func appRows() throws {
        var day = DayStats(date: Date(timeIntervalSince1970: 0))
        day.totalPresses = 1_000
        day.apps["com.apple.Terminal"] = { var stat = AppStat(); stat.presses = 700; return stat }()
        day.apps["com.apple.Safari"] = { var stat = AppStat(); stat.presses = 300; return stat }()

        let state = MenuViewState.build(day: day, hasPermission: true)
        #expect(state.topApps.map(\.name) == ["Terminal", "Safari"])
        #expect(abs((state.topApps.first?.share ?? 0) - 0.7) < 0.001)
    }
}

@Suite("Format")
struct FormatTests {

    @Test("nil renders as a dash across the board")
    func nilHandling() {
        #expect(Format.wpm(nil) == "—")
        #expect(Format.accuracy(nil) == "—")
        #expect(Format.milliseconds(nil) == "—")
        #expect(Format.percentage(nil) == "—")
    }

    @Test("non-finite values do not leak into the UI")
    func nonFinite() {
        #expect(Format.wpm(.nan) == "—")
        #expect(Format.wpm(.infinity) == "—")
        #expect(Format.duration(seconds: .nan) == "—")
    }

    @Test("duration switches units to stay legible")
    func duration() {
        #expect(Format.duration(seconds: 0.34) == "340ms")
        #expect(Format.duration(seconds: 1.44) == "1.4s")
        #expect(Format.duration(seconds: 125) == "2m 05s")
    }

    @Test("counts abbreviate above a thousand")
    func counts() {
        #expect(Format.count(999) == "999")
        #expect(Format.count(1_500) == "1.5k")
        #expect(Format.count(2_500_000) == "2.5M")
    }

    @Test("app names come from the last bundle-ID component")
    func appName() {
        #expect(Format.appName(bundleID: "com.apple.Terminal") == "Terminal")
        #expect(Format.appName(bundleID: "Xcode") == "Xcode")
    }
}
