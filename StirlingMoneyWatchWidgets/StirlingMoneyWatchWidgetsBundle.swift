import SwiftUI
import WidgetKit

/// Watch complications (watch faces and the Smart Stack), drawn from the summary the Watch app
/// saves to the App Group folder.
@main
struct StirlingMoneyWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BalanceComplication()
        GoalComplication()
        BudgetComplication()
    }
}

/// The custom accent color chosen on the iPhone, or Stirling Money's purple. Named directly, since
/// `Color.accentColor` is the system color inside a widget.
func complicationAccent(_ snapshot: WidgetSnapshot?) -> Color {
    snapshot?.accentColor.map { Color($0) } ?? Color("AccentColor")
}

/// Why a complication has nothing to show. Mirrors the messages of the iPhone widgets.
enum ComplicationEmptyState {
    /// The Watch hasn't received a summary from the iPhone yet.
    case noSummary
    /// There are no goals (or budgets) yet.
    case noneExist
    /// The chosen account, goal or budget was deleted (or, for a budget, its period ended and the iPhone left it out).
    case missing

    init<Item>(_ choice: WidgetChoice<Item>) {
        switch choice {
        case .noneExist: self = .noneExist
        case .missing: self = .missing
        case .item, .noSummary: self = .noSummary
        }
    }
}

/// A complication's message when it has nothing to show: a short line for inline, a sentence for rectangular,
/// and the complication's symbol (with the sentence for VoiceOver) for circular and corner.
struct ComplicationMessage: View {
    @Environment(\.widgetFamily) private var family
    let inline: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inline)
        case .accessoryRectangular:
            Text(message)
                .font(.footnote)
                .minimumScaleFactor(0.8)
        default:
            Image(systemName: systemImage)
                .font(.title3)
                .widgetAccentable()
                .accessibilityLabel(Text(message))
        }
    }
}
