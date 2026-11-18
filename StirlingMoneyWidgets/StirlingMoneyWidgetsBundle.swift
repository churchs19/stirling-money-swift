import SwiftUI
import WidgetKit

@main
struct StirlingMoneyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
        GoalWidget()
        BudgetWidget()
    }
}
