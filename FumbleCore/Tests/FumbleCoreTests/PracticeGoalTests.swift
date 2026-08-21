import Foundation
import Testing
@testable import FumbleCore

@Suite("PracticeGoal")
struct PracticeGoalTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ offset: Int, from today: Date) -> Date {
        calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: today))!
    }

    @Test("progress clamps and a disabled goal reports nil")
    func progress() {
        #expect(PracticeGoal.progress(practicedSeconds: 0, goalSeconds: 600) == 0)
        #expect(PracticeGoal.progress(practicedSeconds: 300, goalSeconds: 600) == 0.5)
        #expect(PracticeGoal.progress(practicedSeconds: 900, goalSeconds: 600) == 1)
        // Goal off → nil, not 100%: a full ring for "no goal" would be a lie.
        #expect(PracticeGoal.progress(practicedSeconds: 300, goalSeconds: 0) == nil)
    }

    @Test("no history means no streak")
    func empty() {
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(PracticeGoal.streak(practicedSecondsByDay: [:], goalSeconds: 600, today: today, calendar: calendar) == 0)
    }

    @Test("meeting the goal today starts a streak of 1")
    func todayMet() {
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        let history = [day(0, from: today): 700.0]
        #expect(PracticeGoal.streak(practicedSecondsByDay: history, goalSeconds: 600, today: today, calendar: calendar) == 1)
    }

    @Test("an in-progress today does not break yesterday's chain")
    func todayInProgress() {
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        // Yesterday and the day before met; today only partial so far.
        let history = [
            day(0, from: today): 120.0,
            day(1, from: today): 700.0,
            day(2, from: today): 900.0,
        ]
        // The morning-zero problem: this must be 2, not 0.
        #expect(PracticeGoal.streak(practicedSecondsByDay: history, goalSeconds: 600, today: today, calendar: calendar) == 2)
    }

    @Test("a fully missed day breaks the chain")
    func gapBreaks() {
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        let history = [
            day(0, from: today): 700.0,
            // day 1 missed entirely
            day(2, from: today): 700.0,
            day(3, from: today): 700.0,
        ]
        #expect(PracticeGoal.streak(practicedSecondsByDay: history, goalSeconds: 600, today: today, calendar: calendar) == 1)
    }

    @Test("long unbroken chains count fully")
    func longChain() {
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        var history: [Date: Double] = [:]
        for offset in 0..<14 { history[day(offset, from: today)] = 601 }
        #expect(PracticeGoal.streak(practicedSecondsByDay: history, goalSeconds: 600, today: today, calendar: calendar) == 14)
    }

    @Test("goal off means streak 0")
    func goalOff() {
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        let history = [day(0, from: today): 700.0]
        #expect(PracticeGoal.streak(practicedSecondsByDay: history, goalSeconds: 0, today: today, calendar: calendar) == 0)
    }
}
