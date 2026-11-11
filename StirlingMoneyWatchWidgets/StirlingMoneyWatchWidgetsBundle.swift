import SwiftUI
import WidgetKit

/// Watch complications (watch faces and the Smart Stack), drawn from the summary the Watch app
/// saves to the App Group folder.
@main
struct StirlingMoneyWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BalanceComplication()
        GoalComplication()
    }
}

/// The custom accent color chosen on the iPhone, or Stirling Money's purple. Named directly, since
/// `Color.accentColor` is the system color inside a widget.
func complicationAccent(_ snapshot: WidgetSnapshot?) -> Color {
    snapshot?.accentColor.map { Color($0) } ?? Color("AccentColor")
}
