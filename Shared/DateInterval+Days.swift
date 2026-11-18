import Foundation

nonisolated extension DateInterval {
    /// The interval's days as text, such as "Nov 1 – 30, 2026", or "Nov 1 – 30" without the year for small spaces.
    /// The end is exclusive (the start of the day after), so the last day shown is the day before. A one-day interval
    /// shows just that day. Used by the Budgets screen, the budget history report, the widgets and the Watch.
    func formattedDays(withYear: Bool = true, calendar: Calendar = .current) -> String {
        let lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        guard lastDay > start else { return start.formatted(.dateTime.month(.abbreviated).day()) }
        let style = Date.IntervalFormatStyle.interval.month(.abbreviated).day()
        return (start ..< lastDay).formatted(withYear ? style.year() : style)
    }
}
