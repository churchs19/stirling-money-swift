import Foundation
import Testing
@testable import Stirling_Money

/// When recurring transactions fall due (`RecurrenceSchedule`), in a fixed UTC calendar.
struct RecurrenceScheduleTests {
    private func schedule(_ frequency: RecurrenceFrequency, every interval: Int = 1, from start: Date, secondDay: Int = 15) -> RecurrenceSchedule {
        RecurrenceSchedule(frequency: frequency, interval: interval, start: start, secondDay: secondDay)
    }

    private func dates(_ schedule: RecurrenceSchedule, from: Date, through: Date) -> [Date] {
        schedule.occurrences(from: from, through: through, calendar: utc)
    }

    // MARK: Weekly

    @Test func weeklyRepeatsOnTheStartsWeekday() {
        // Fri Nov 6, 2026.
        let weekly = schedule(.weekly, from: day(2026, 11, 6))
        #expect(dates(weekly, from: day(2026, 11, 1), through: day(2026, 11, 30))
            == [day(2026, 11, 6), day(2026, 11, 13), day(2026, 11, 20), day(2026, 11, 27)])
    }

    @Test func everyOtherWeekSkipsAWeek() {
        let payday = schedule(.weekly, every: 2, from: day(2026, 11, 6))
        #expect(dates(payday, from: day(2026, 11, 1), through: day(2026, 12, 31))
            == [day(2026, 11, 6), day(2026, 11, 20), day(2026, 12, 4), day(2026, 12, 18)])
        // Counting from the start, not from the asked-for date.
        #expect(payday.next(onOrAfter: day(2026, 11, 10), calendar: utc) == day(2026, 11, 20))
    }

    // MARK: Monthly

    @Test func monthlyKeepsTheDayAndClampsShortMonths() {
        let rent = schedule(.monthly, from: day(2026, 1, 31))
        #expect(dates(rent, from: day(2026, 1, 1), through: day(2026, 5, 31))
            == [day(2026, 1, 31), day(2026, 2, 28), day(2026, 3, 31), day(2026, 4, 30), day(2026, 5, 31)])
    }

    @Test func monthlyInALeapYearUsesFebruary29() {
        let rent = schedule(.monthly, from: day(2028, 1, 30))
        #expect(rent.next(after: day(2028, 1, 30), calendar: utc) == day(2028, 2, 29))
        #expect(rent.next(after: day(2028, 2, 29), calendar: utc) == day(2028, 3, 30))
    }

    @Test func everyThreeMonths() {
        let quarterly = schedule(.monthly, every: 3, from: day(2026, 1, 15))
        #expect(dates(quarterly, from: day(2026, 1, 1), through: day(2026, 12, 31))
            == [day(2026, 1, 15), day(2026, 4, 15), day(2026, 7, 15), day(2026, 10, 15)])
    }

    // MARK: Twice a month

    @Test func twiceAMonthOnTheFirstAndFifteenth() {
        let pay = schedule(.twiceMonthly, from: day(2026, 11, 1), secondDay: 15)
        #expect(dates(pay, from: day(2026, 11, 1), through: day(2026, 12, 31))
            == [day(2026, 11, 1), day(2026, 11, 15), day(2026, 12, 1), day(2026, 12, 15)])
    }

    @Test func twiceAMonthStartingAfterTheEarlierDay() {
        // Starts on the 15th with the 1st as the other day: the first occurrence is the 15th, then the 1st.
        let pay = schedule(.twiceMonthly, from: day(2026, 11, 15), secondDay: 1)
        #expect(dates(pay, from: day(2026, 11, 1), through: day(2026, 12, 20))
            == [day(2026, 11, 15), day(2026, 12, 1), day(2026, 12, 15)])
    }

    @Test func twiceAMonthOnTheLastDayClamps() {
        let pay = schedule(.twiceMonthly, from: day(2027, 1, 15), secondDay: 31)
        #expect(dates(pay, from: day(2027, 1, 1), through: day(2027, 3, 1))
            == [day(2027, 1, 15), day(2027, 1, 31), day(2027, 2, 15), day(2027, 2, 28)])
    }

    // MARK: Yearly

    @Test func yearlyRepeatsOnTheDate() {
        let insurance = schedule(.yearly, from: day(2026, 3, 4))
        #expect(dates(insurance, from: day(2026, 1, 1), through: day(2028, 12, 31))
            == [day(2026, 3, 4), day(2027, 3, 4), day(2028, 3, 4)])
    }

    @Test func yearlyFromFebruary29FallsOnFebruary28() {
        let leap = schedule(.yearly, from: day(2028, 2, 29))
        #expect(dates(leap, from: day(2028, 1, 1), through: day(2032, 12, 31))
            == [day(2028, 2, 29), day(2029, 2, 28), day(2030, 2, 28), day(2031, 2, 28), day(2032, 2, 29)])
    }

    // MARK: Next and ranges

    @Test func nextOnOrAfterIncludesTheDayItselfAndAfterDoesNot() {
        let monthly = schedule(.monthly, from: day(2026, 11, 1))
        #expect(monthly.next(onOrAfter: day(2026, 12, 1), calendar: utc) == day(2026, 12, 1))
        #expect(monthly.next(after: day(2026, 12, 1), calendar: utc) == day(2027, 1, 1))
        // A time later in the day still counts as that day.
        #expect(monthly.next(onOrAfter: day(2026, 12, 1).addingTimeInterval(15 * 3600), calendar: utc) == day(2026, 12, 1))
    }

    @Test(arguments: RecurrenceFrequency.allCases)
    func beforeTheStartTheNextOccurrenceIsTheStart(_ frequency: RecurrenceFrequency) {
        let rule = schedule(frequency, from: day(2026, 11, 20), secondDay: 5)
        #expect(rule.next(onOrAfter: day(2026, 1, 1), calendar: utc) == day(2026, 11, 20))
    }

    @Test func rangesAreCappedAtTheLimit() {
        let weekly = schedule(.weekly, from: day(2020, 1, 6))
        #expect(weekly.occurrences(from: day(2020, 1, 1), through: day(2030, 1, 1), limit: 10, calendar: utc).count == 10)
        #expect(dates(weekly, from: day(2026, 11, 7), through: day(2026, 11, 8)).isEmpty, "none in a weekend")
    }

    // MARK: Summary

    @Test func summariesDescribeTheSchedule() {
        let us = Locale(identifier: "en_US")
        #expect(schedule(.weekly, from: day(2026, 11, 6)).summary(calendar: utc, locale: us) == "Weekly on Friday")
        #expect(schedule(.weekly, every: 2, from: day(2026, 11, 6)).summary(calendar: utc, locale: us) == "Every 2 weeks on Friday")
        #expect(schedule(.monthly, from: day(2026, 11, 1)).summary(calendar: utc, locale: us) == "Monthly on the 1st")
        #expect(schedule(.monthly, every: 3, from: day(2026, 11, 22)).summary(calendar: utc, locale: us) == "Every 3 months on the 22nd")
        #expect(schedule(.twiceMonthly, from: day(2026, 11, 15), secondDay: 1).summary(calendar: utc, locale: us)
            == "Twice a month on the 1st and 15th")
        #expect(schedule(.yearly, from: day(2026, 3, 4)).summary(calendar: utc, locale: us) == "Yearly on Mar 4")
    }

    @Test func frequenciesKeepTheirStoredNames() {
        // Saved in the store; renaming a case would break existing rules.
        #expect(RecurrenceFrequency.allCases.map(\.rawValue) == ["weekly", "monthly", "twiceMonthly", "yearly"])
    }
}
