import Foundation

nonisolated enum BudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case weekly
    case monthly
    case yearly
    case custom

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .weekly: String(localized: "Weekly")
        case .monthly: String(localized: "Monthly")
        case .yearly: String(localized: "Yearly")
        case .custom: String(localized: "Custom")
        }
    }

    /// The period that contains `date`, shifted by `offset` periods (-1 is the previous period).
    ///
    /// Recurring periods repeat from `start`. Monthly and yearly periods keep the start's day,
    /// clamped to shorter months: a budget starting Jan 31 runs Jan 31, Feb 28 (or 29), Mar 31, Apr 30...
    /// A custom period runs from `start` through the whole of `end`'s day, ignores `offset`,
    /// and is nil when `end` is missing or before `start`.
    func interval(
        start: Date,
        end: Date?,
        containing date: Date,
        offset: Int = 0,
        calendar: Calendar = .current
    ) -> DateInterval? {
        let anchor = calendar.startOfDay(for: start)

        let component: Calendar.Component
        let step: Int
        switch self {
        case .custom:
            guard let end,
                  let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)),
                  endExclusive > anchor
            else { return nil }
            return DateInterval(start: anchor, end: endExclusive)
        case .weekly:
            component = .day
            step = 7
        case .monthly:
            component = .month
            step = 1
        case .yearly:
            component = .year
            step = 1
        }

        // Always step from the anchor rather than from the previous period,
        // so a clamped Feb 28 doesn't drag later months to the 28th.
        func periodStart(_ index: Int) -> Date {
            calendar.date(byAdding: component, value: index * step, to: anchor) ?? anchor
        }

        let elapsed = calendar.dateComponents([component], from: anchor, to: date).value(for: component) ?? 0
        var index = Int((Double(elapsed) / Double(step)).rounded(.down))
        while periodStart(index) > date {
            index -= 1
        }
        while periodStart(index + 1) <= date {
            index += 1
        }

        index += offset
        return DateInterval(start: periodStart(index), end: periodStart(index + 1))
    }
}
