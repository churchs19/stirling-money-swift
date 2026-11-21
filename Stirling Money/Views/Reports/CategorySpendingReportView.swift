import Charts
import SwiftData
import SwiftUI

/// A donut of spending by category over the chosen months.
struct CategorySpendingReportView: View {
    @Query private var transactions: [AccountTransaction]

    init(book: Book) {
        _transactions = Query(filter: AccountTransaction.inBook(book))
    }
    @AppStorage("reportRange") private var range: ReportRange = .sixMonths
    @State private var selectedAngle: Double?

    var body: some View {
        let interval = Reports.monthRange(count: range.rawValue, endingAt: .now)
        let slices = Reports.spendingByCategory(transactions, in: interval)
        let total = slices.reduce(Decimal(0)) { $0 + $1.amount }
        let selected = slice(at: selectedAngle, in: slices)

        List {
            Section {
                ReportRangePicker(range: $range)
                if slices.isEmpty {
                    ContentUnavailableView(
                        "No Spending",
                        systemImage: "chart.pie",
                        description: Text("There's no spending in this range.")
                    )
                } else {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Spent", slice.amount.chartValue),
                            innerRadius: .ratio(0.6),
                            angularInset: 1
                        )
                        .cornerRadius(3)
                        .foregroundStyle(by: .value("Category", name(of: slice)))
                        .opacity(selected == nil || selected == slice ? 1 : 0.4)
                    }
                    .chartForegroundStyleScale(
                        domain: slices.map { name(of: $0) },
                        range: slices.map { ChartPalette.color(slot: $0.colorSlot) }
                    )
                    .chartAngleSelection(value: $selectedAngle)
                    .chartLegend(position: .bottom, alignment: .center, spacing: 12)
                    .chartBackground { proxy in
                        GeometryReader { geometry in
                            if let plotFrame = proxy.plotFrame {
                                let frame = geometry[plotFrame]
                                VStack(spacing: 2) {
                                    Text(selected.map { name(of: $0) } ?? String(localized: "Total"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(selected?.amount ?? total, format: .localCurrency)
                                        .font(.headline)
                                        .monospacedDigit()
                                }
                                .frame(maxWidth: frame.width * 0.5)
                                .position(x: frame.midX, y: frame.midY)
                            }
                        }
                    }
                    .frame(height: 300)
                    .padding(.vertical, 8)
                }
            } footer: {
                Text("Spending less refunds, \(interval.formattedMonths()). The seven biggest categories get their own color; the rest are grouped as Other.")
            }

            if !slices.isEmpty {
                Section("By Category") {
                    ForEach(slices) { slice in
                        HStack {
                            Circle()
                                .fill(ChartPalette.color(slot: slice.colorSlot))
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text(name(of: slice))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                AmountText(slice.amount)
                                Text(percent(slice.amount, of: total))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle("Spending by Category")
    }

    private func name(of slice: CategorySlice) -> String {
        if slice.isOther { return String(localized: "Other") }
        return slice.categoryName ?? String(localized: "Uncategorized")
    }

    private func percent(_ amount: Decimal, of total: Decimal) -> String {
        guard total > 0 else { return "" }
        return (amount / total).chartValue.formatted(.percent.precision(.fractionLength(0)))
    }

    /// The slice under a selected angle, which runs from 0 to the total of all slices.
    private func slice(at angle: Double?, in slices: [CategorySlice]) -> CategorySlice? {
        guard let angle else { return nil }
        var running = 0.0
        for slice in slices {
            running += slice.amount.chartValue
            if angle <= running { return slice }
        }
        return nil
    }
}

extension DateInterval {
    /// "Jun – Nov 2026", for an interval of whole months. The end is exclusive.
    func formattedMonths(calendar: Calendar = .current) -> String {
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: end) ?? end
        guard lastMonth > start else { return start.formatted(.dateTime.month(.wide).year()) }
        return (start ..< lastMonth).formatted(.interval.month(.abbreviated).year())
    }
}

#Preview {
    NavigationStack {
        CategorySpendingReportView(book: ModelContainer.preview.firstBook)
    }
    .modelContainer(.preview)
}
