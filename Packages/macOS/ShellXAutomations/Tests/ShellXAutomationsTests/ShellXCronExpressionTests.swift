import Foundation
import Testing
@testable import ShellXAutomations

struct ShellXCronExpressionTests {
    @Test func dailyAtEight() throws {
        #expect(try ShellXCronExpression("0 8 * * *").launchdCalendarIntervals() == [["Minute": 0, "Hour": 8]])
    }

    @Test func everyFifteenMinutesWeekdays() throws {
        let entries = try ShellXCronExpression("*/15 9-10 * * 1-5").launchdCalendarIntervals()
        #expect(entries.count == 4 * 2 * 5)
        #expect(entries.contains(["Minute": 45, "Hour": 10, "Weekday": 5]))
    }

    @Test func sundayAsSeven() throws {
        #expect(try ShellXCronExpression("0 0 * * 7").launchdCalendarIntervals() == [["Minute": 0, "Hour": 0, "Weekday": 0]])
    }

    @Test func sundayZeroAndSevenDedupe() throws {
        #expect(try ShellXCronExpression("0 0 * * 0,7").launchdCalendarIntervals().count == 1)
    }

    @Test func everyFifteenMinutesAllDayIsAllowed() throws {
        #expect(try ShellXCronExpression("*/15 * * * *").launchdCalendarIntervals().count == 4)
    }

    @Test(arguments: ["@daily", "0 8 * * MON", "61 * * * *", "0 9 1 * 1", "* * *", "*/7 * * * *"])
    func rejected(_ text: String) {
        #expect(throws: ShellXCronError.self) { try ShellXCronExpression(text).launchdCalendarIntervals() }
    }

    @Test func unevenStepIsSpecific() {
        #expect(throws: ShellXCronError.unevenStep(field: "Minute")) { try ShellXCronExpression("*/7 * * * *") }
    }

    @Test func tooManyEntriesIsSpecific() {
        #expect(throws: ShellXCronError.tooManyEntries) {
            try ShellXCronExpression("*/2 */2 * * *").launchdCalendarIntervals(limit: 100)
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    @Test func nextFireDailyRollsToTomorrow() throws {
        let next = try ShellXCronExpression("0 8 * * *").nextFireDate(after: date(2026, 11, 3, 9, 0), calendar: calendar)
        #expect(next == date(2026, 11, 4, 8, 0))
    }

    @Test func nextFireIsStrictlyAfter() throws {
        let next = try ShellXCronExpression("0 8 * * *").nextFireDate(after: date(2026, 11, 3, 8, 0), calendar: calendar)
        #expect(next == date(2026, 11, 4, 8, 0))
    }

    @Test func nextFireWeekday() throws {
        // 2026-11-03 is a Tuesday; next Monday is 2026-11-09.
        let next = try ShellXCronExpression("30 7 * * 1").nextFireDate(after: date(2026, 11, 3, 9, 0), calendar: calendar)
        #expect(next == date(2026, 11, 9, 7, 30))
    }

    @Test func nextFireStepsWithinDay() throws {
        let next = try ShellXCronExpression("*/15 * * * *").nextFireDate(after: date(2026, 11, 3, 9, 7), calendar: calendar)
        #expect(next == date(2026, 11, 3, 9, 15))
    }
}
