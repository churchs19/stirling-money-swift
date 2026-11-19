import Foundation

/// How often a recurring transaction repeats. Stored by its raw value, like `BudgetPeriod`.
nonisolated enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    /// Every N weeks on the start date's weekday.
    case weekly
    /// Every N months on the start date's day of the month (clamped to shorter months).
    case monthly
    /// Every month on two days: the start date's day and a second day.
    case twiceMonthly
    /// Every N years on the start date's month and day (Feb 29 falls on Feb 28 in other years).
    case yearly

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .weekly: String(localized: "Weekly")
        case .monthly: String(localized: "Monthly")
        case .twiceMonthly: String(localized: "Twice a Month")
        case .yearly: String(localized: "Yearly")
        }
    }
}

/// When a recurring transaction falls due: pure date math, in local calendar days.
///
/// Occurrences are counted from the start date rather than from the one before, so a rule starting Jan 31 falls on
/// Feb 28 (or 29) and then back on Mar 31, not on the 28th from then on.
nonisolated struct RecurrenceSchedule: Equatable {
    var frequency: RecurrenceFrequency
    /// Every N weeks, months or years (at least 1). Ignored for twice a month.
    var interval: Int = 1
    /// The first occurrence. Its weekday, day of month or date sets the pattern.
    var start: Date
    /// For twice a month: the other day of the month (1–31; past the month's end means its last day).
    var secondDay: Int = 15

    /// The first occurrence on or after `date`'s day. Before the start, that's the start.
    func next(onOrAfter date: Date, calendar: Calendar = .current) -> Date {
        let anchor = calendar.startOfDay(for: start)
        let day = max(calendar.startOfDay(for: date), anchor)

        switch frequency {
        case .twiceMonthly:
            let anchorMonth = calendar.dateInterval(of: .month, for: anchor)?.start ?? anchor
            let months = max(calendar.dateComponents([.month], from: anchorMonth, to: day).month ?? 0, 0)
            // This month or the next always has one; a few more for safety.
            for offset in months ... months + 3 {
                if let found = twiceMonthlyDays(monthOffset: offset, calendar: calendar).first(where: { $0 >= day }) {
                    return found
                }
            }
            return day
        case .weekly, .monthly, .yearly:
            let (component, step) = stepping
            let elapsed = calendar.dateComponents([component], from: anchor, to: day).value(for: component) ?? 0
            var index = max(elapsed / step, 0)
            while index > 0, occurrence(index - 1, calendar: calendar) >= day {
                index -= 1
            }
            while occurrence(index, calendar: calendar) < day {
                index += 1
            }
            return occurrence(index, calendar: calendar)
        }
    }

    /// The first occurrence on a later day than `date`.
    func next(after date: Date, calendar: Calendar = .current) -> Date {
        let following = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        return next(onOrAfter: following, calendar: calendar)
    }

    /// The occurrences from `from`'s day through `through`'s day, oldest first, at most `limit` of them.
    func occurrences(from: Date, through: Date, limit: Int = 400, calendar: Calendar = .current) -> [Date] {
        let last = calendar.startOfDay(for: through)
        var dates: [Date] = []
        var current = next(onOrAfter: from, calendar: calendar)
        while current <= last, dates.count < limit {
            dates.append(current)
            current = next(after: current, calendar: calendar)
        }
        return dates
    }

    // MARK: Stepping

    private var stepping: (Calendar.Component, Int) {
        let every = max(interval, 1)
        switch frequency {
        case .weekly: return (.day, 7 * every)
        case .monthly, .twiceMonthly: return (.month, every)
        case .yearly: return (.year, every)
        }
    }

    /// The `index`th occurrence of a weekly, monthly or yearly schedule (0 is the start).
    private func occurrence(_ index: Int, calendar: Calendar) -> Date {
        let anchor = calendar.startOfDay(for: start)
        let (component, step) = stepping
        // Calendar clamps a month or year step to the end of a shorter month.
        return calendar.date(byAdding: component, value: index * step, to: anchor) ?? anchor
    }

    /// Both days of a twice-a-month schedule in the month `monthOffset` months after the start's, oldest first,
    /// leaving out any before the start.
    private func twiceMonthlyDays(monthOffset: Int, calendar: Calendar) -> [Date] {
        let anchor = calendar.startOfDay(for: start)
        guard let anchorMonth = calendar.dateInterval(of: .month, for: anchor)?.start,
              let month = calendar.date(byAdding: .month, value: monthOffset, to: anchorMonth),
              let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }
        let firstDay = calendar.component(.day, from: anchor)
        let days = Set([firstDay, secondDay].map { min(max($0, 1), daysInMonth) })
        return days.sorted()
            .compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
            .filter { $0 >= anchor }
    }
}

nonisolated extension RecurrenceSchedule {
    /// "Weekly on Friday", "Every 2 weeks on Friday", "Monthly on the 1st", "Twice a month on the 1st and 15th",
    /// "Yearly on Mar 4".
    func summary(calendar: Calendar = .current, locale: Locale = .current) -> String {
        let every = max(interval, 1)
        switch frequency {
        case .weekly:
            let weekday = start.formatted(Self.style(.dateTime.weekday(.wide), calendar: calendar, locale: locale))
            return every == 1
                ? String(localized: "Weekly on \(weekday)")
                : String(localized: "Every \(every) weeks on \(weekday)")
        case .monthly:
            let day = Self.ordinal(calendar.component(.day, from: start), locale: locale)
            return every == 1
                ? String(localized: "Monthly on the \(day)")
                : String(localized: "Every \(every) months on the \(day)")
        case .twiceMonthly:
            let days = [calendar.component(.day, from: start), secondDay].sorted().map { Self.ordinal($0, locale: locale) }
            return String(localized: "Twice a month on the \(days[0]) and \(days[1])")
        case .yearly:
            let date = start.formatted(Self.style(.dateTime.month(.abbreviated).day(), calendar: calendar, locale: locale))
            return every == 1
                ? String(localized: "Yearly on \(date)")
                : String(localized: "Every \(every) years on \(date)")
        }
    }

    /// `style` in the calendar's time zone, so a day is named as the schedule counts it.
    private static func style(_ style: Date.FormatStyle, calendar: Calendar, locale: Locale) -> Date.FormatStyle {
        var style = style.locale(locale)
        style.timeZone = calendar.timeZone
        style.calendar = calendar
        return style
    }

    /// "1st", "22nd", in `locale`.
    private static func ordinal(_ number: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = locale
        return formatter.string(from: number as NSNumber) ?? "\(number)"
    }
}
