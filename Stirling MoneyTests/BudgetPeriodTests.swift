import Foundation
import Testing
@testable import Stirling_Money

struct BudgetPeriodTests {
    private func interval(
        _ period: BudgetPeriod,
        start: Date,
        end: Date? = nil,
        on date: Date,
        offset: Int = 0
    ) -> DateInterval? {
        period.interval(start: start, end: end, containing: date, offset: offset, calendar: utc)
    }

    @Test func monthlyKeepsStartDayAndClampsInLeapYear() {
        let start = day(2028, 1, 31)
        #expect(interval(.monthly, start: start, on: day(2028, 2, 15)) == DateInterval(start: day(2028, 1, 31), end: day(2028, 2, 29)))
        #expect(interval(.monthly, start: start, on: day(2028, 2, 29)) == DateInterval(start: day(2028, 2, 29), end: day(2028, 3, 31)))
        // Clamping February doesn't drag later months to the 29th.
        #expect(interval(.monthly, start: start, on: day(2028, 4, 1)) == DateInterval(start: day(2028, 3, 31), end: day(2028, 4, 30)))
        #expect(interval(.monthly, start: start, on: day(2028, 5, 10)) == DateInterval(start: day(2028, 4, 30), end: day(2028, 5, 31)))
    }

    @Test func monthlyClampsToFebruary28InNonLeapYear() {
        #expect(
            interval(.monthly, start: day(2027, 1, 31), on: day(2027, 3, 1))
                == DateInterval(start: day(2027, 2, 28), end: day(2027, 3, 31))
        )
    }

    @Test func monthlyOffsetGivesPreviousPeriods() {
        let start = day(2026, 1, 15)
        #expect(interval(.monthly, start: start, on: day(2026, 3, 20), offset: -1) == DateInterval(start: day(2026, 2, 15), end: day(2026, 3, 15)))
        #expect(interval(.monthly, start: start, on: day(2026, 3, 20), offset: -2) == DateInterval(start: day(2026, 1, 15), end: day(2026, 2, 15)))
    }

    @Test func weeklyRepeatsEverySevenDays() {
        let start = day(2026, 11, 2)
        #expect(interval(.weekly, start: start, on: day(2026, 11, 20)) == DateInterval(start: day(2026, 11, 16), end: day(2026, 11, 23)))
        // A period boundary belongs to the period it starts.
        #expect(interval(.weekly, start: start, on: day(2026, 11, 9)) == DateInterval(start: day(2026, 11, 9), end: day(2026, 11, 16)))
    }

    @Test func weeklyBeforeStartStepsBackwards() {
        #expect(
            interval(.weekly, start: day(2026, 11, 2), on: day(2026, 10, 30))
                == DateInterval(start: day(2026, 10, 26), end: day(2026, 11, 2))
        )
    }

    @Test func yearlyFromLeapDayClampsToFebruary28() {
        #expect(
            interval(.yearly, start: day(2028, 2, 29), on: day(2029, 3, 1))
                == DateInterval(start: day(2029, 2, 28), end: day(2030, 2, 28))
        )
    }

    @Test func customRunsThroughEndOfEndDay() {
        #expect(
            interval(.custom, start: day(2026, 11, 1), end: day(2026, 11, 30), on: day(2026, 11, 4))
                == DateInterval(start: day(2026, 11, 1), end: day(2026, 12, 1))
        )
    }

    @Test func customWithoutValidEndIsNil() {
        #expect(interval(.custom, start: day(2026, 11, 1), on: day(2026, 11, 4)) == nil)
        #expect(interval(.custom, start: day(2026, 11, 10), end: day(2026, 11, 1), on: day(2026, 11, 4)) == nil)
    }

    /// Local midnight, since the text is formatted in the current time zone.
    private func localDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func periodDaysShowTheLastDayNotTheExclusiveEnd() {
        let november = DateInterval(start: localDay(2026, 11, 1), end: localDay(2026, 12, 1))
        let withYear = november.formattedDays()
        let withoutYear = november.formattedDays(withYear: false)
        #expect(withYear.contains("2026"))
        #expect(!withoutYear.contains("2026"))
        #expect(withoutYear.contains("30"), "the last day is Nov 30")
        #expect(!withoutYear.contains("Dec"))
    }

    @Test func aOneDayPeriodShowsJustThatDay() {
        let oneDay = DateInterval(start: localDay(2026, 11, 5), end: localDay(2026, 11, 6))
        #expect(oneDay.formattedDays() == localDay(2026, 11, 5).formatted(.dateTime.month(.abbreviated).day()))
    }

    @Test func widgetsAndTheBudgetsScreenFormatPeriodsTheSameWay() {
        let budget = WidgetSnapshot.BudgetSummary(
            id: "b", name: "Food", amount: 400, spent: 0,
            periodStart: localDay(2026, 11, 1), periodEnd: localDay(2026, 12, 1), periodTitle: "Monthly"
        )
        let interval = DateInterval(start: budget.periodStart, end: budget.periodEnd)
        #expect(budget.periodText(withYear: true) == "Monthly · \(interval.formattedDays())")
        #expect(budget.periodText(withYear: false) == "Monthly · \(interval.formattedDays(withYear: false))")
    }
}
