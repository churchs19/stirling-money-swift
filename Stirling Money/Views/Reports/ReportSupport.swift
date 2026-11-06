import Charts
import SwiftUI

/// How many months a monthly report covers. Shared by every report and remembered between launches.
enum ReportRange: Int, CaseIterable, Identifiable {
    case threeMonths = 3
    case sixMonths = 6
    case twelveMonths = 12

    var id: Self {
        self
    }

    var title: String {
        String(localized: "\(rawValue) Months")
    }
}

/// A segmented 3 / 6 / 12 months picker.
struct ReportRangePicker: View {
    @Binding var range: ReportRange

    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(ReportRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// The small card shown above the selected bar or slice.
struct ChartCallout<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    /// A y-axis labeled in whole currency units, with a light grid.
    func currencyYAxis() -> some View {
        chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(Decimal(amount), format: .localCurrency.precision(.fractionLength(0)))
                    }
                }
            }
        }
    }

    /// An x-axis with one abbreviated month label per month.
    func monthXAxis() -> some View {
        chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
            }
        }
    }
}

extension Date {
    /// "November 2026"
    var monthAndYear: String {
        formatted(.dateTime.month(.wide).year())
    }
}
