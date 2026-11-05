#if DEBUG
    import Foundation
    import SwiftData

    @MainActor
    extension ModelContainer {
        /// An in-memory store with a few accounts and transactions, for SwiftUI previews.
        static let preview: ModelContainer = {
            let container = try! ModelContainer(
                for: Schema(AppSchema.models),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = container.mainContext

            let checking = Account(name: "Checking", initialBalance: 1250.75)
            let savings = Account(name: "Savings", initialBalance: 8000)
            let creditCard = Account(name: "Credit Card", initialBalance: -342.18)
            [checking, savings, creditCard].forEach(context.insert)

            let groceries = try! Ledger.category(named: "Groceries", in: context)
            let housing = try! Ledger.category(named: "Housing", in: context)
            let dining = try! Ledger.category(named: "Dining", in: context)

            func daysAgo(_ days: Int) -> Date {
                Calendar.current.date(byAdding: .day, value: -days, to: .now)!
            }

            Ledger.addTransaction(.deposit, amount: 2100, to: checking, date: daysAgo(12), payee: "Employer", isPosted: true, in: context)
            Ledger.addTransaction(.check, amount: 1450, to: checking, date: daysAgo(10), payee: "Landlord", isPosted: true, checkNumber: 1001, category: housing, in: context)
            Ledger.addTransaction(.withdrawal, amount: 82.14, to: checking, date: daysAgo(6), payee: "Corner Grocer", note: "Weekly shop", isPosted: true, category: groceries, in: context)
            Ledger.addTransfer(amount: 500, from: checking, to: savings, date: daysAgo(4), in: context)
            Ledger.addTransaction(.withdrawal, amount: 4.50, to: checking, date: daysAgo(1), payee: "Coffee Cart", category: dining, in: context)
            Ledger.addTransaction(.withdrawal, amount: 61.20, to: creditCard, date: daysAgo(3), payee: "Bistro", category: dining, in: context)

            return container
        }()
    }
#endif
