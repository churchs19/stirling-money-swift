import Foundation
import SwiftData
@testable import Stirling_Money

/// An in-memory store. Keep the container alive for as long as you use its context.
@MainActor
func makeInMemoryContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Schema(AppSchema.models),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

/// A fixed Gregorian UTC calendar so date math doesn't depend on the test machine.
let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day))!
}
