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

            let checking = Account(name: "Checking", initialBalance: 1250.75, iconName: "building.columns")
            let savings = Account(name: "Savings", initialBalance: 8000, iconName: "banknote")
            let creditCard = Account(name: "Credit Card", initialBalance: -342.18, iconName: "pf-visa")
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

            // Five earlier months of history, so reports have something to show.
            let utilities = try! Ledger.category(named: "Utilities", in: context)
            let fuel = try! Ledger.category(named: "Fuel", in: context)
            for monthsBack in 1 ... 5 {
                let base = Calendar.current.date(byAdding: .month, value: -monthsBack, to: .now)!
                func on(_ day: Int) -> Date {
                    let start = Calendar.current.dateInterval(of: .month, for: base)!.start
                    return Calendar.current.date(byAdding: .day, value: day - 1, to: start)!
                }
                let wiggle = Decimal(monthsBack * 7)
                Ledger.addTransaction(.deposit, amount: 2100, to: checking, date: on(1), payee: "Employer", isPosted: true, in: context)
                Ledger.addTransaction(.deposit, amount: 2100, to: checking, date: on(15), payee: "Employer", isPosted: true, in: context)
                Ledger.addTransaction(.check, amount: 1450, to: checking, date: on(2), payee: "Landlord", isPosted: true, checkNumber: 1001 - monthsBack, category: housing, in: context)
                Ledger.addTransaction(.withdrawal, amount: 310 + wiggle, to: checking, date: on(8), payee: "Corner Grocer", isPosted: true, category: groceries, in: context)
                Ledger.addTransaction(.withdrawal, amount: 95 - wiggle, to: checking, date: on(21), payee: "Corner Grocer", isPosted: true, category: groceries, in: context)
                Ledger.addTransaction(.withdrawal, amount: 120 + wiggle * 2, to: checking, date: on(12), payee: "Power & Light", isPosted: true, category: utilities, in: context)
                Ledger.addTransaction(.withdrawal, amount: 48 + wiggle, to: creditCard, date: on(10), payee: "Gas Station", isPosted: true, category: fuel, in: context)
                Ledger.addTransaction(.withdrawal, amount: 85 - wiggle, to: creditCard, date: on(18), payee: "Bistro", isPosted: true, category: dining, in: context)
                Ledger.addTransfer(amount: 400, from: checking, to: savings, date: on(16), isPosted: true, in: context)
            }

            let monthStart = Calendar.current.dateInterval(of: .month, for: .now)!.start
            let historyStart = Calendar.current.date(byAdding: .month, value: -5, to: monthStart)!
            let groceryBudget = Budget(name: "Groceries", amount: 400, startDate: historyStart)
            // Started eight weeks before this week's period, so the current week begins 6 days ago.
            let diningBudget = Budget(name: "Eating Out", amount: 50, period: .weekly, startDate: daysAgo(62))
            let everything = Budget(name: "Everything", amount: 3000, startDate: historyStart)
            [groceryBudget, diningBudget, everything].forEach(context.insert)
            groceryBudget.category = groceries
            diningBudget.category = dining

            let inAYear = Calendar.current.date(byAdding: .year, value: 1, to: .now)!
            let emergencyFund = Goal(name: "Emergency Fund", targetAmount: 15000, targetDate: inAYear, initialBalance: 8000, startDate: daysAgo(30))
            let vacation = Goal(name: "Vacation", targetAmount: 8200, targetDate: daysAgo(-60), initialBalance: 6000, startDate: daysAgo(90))
            [emergencyFund, vacation].forEach(context.insert)
            emergencyFund.account = savings
            vacation.account = savings

            // Recurring transactions: rent and pay on Checking, a transfer to Savings and a yearly subscription.
            // They start in the future, so the sample balances don't change by date.
            let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: monthStart)!
            let rent = RecurringTransaction(kind: .check, amount: 1450, payee: "Landlord", frequency: .monthly, startDate: Calendar.current.date(byAdding: .day, value: 1, to: nextMonth)!)
            let pay = RecurringTransaction(kind: .deposit, amount: 2100, payee: "Employer", frequency: .twiceMonthly, startDate: nextMonth)
            let toSavings = RecurringTransaction(kind: .transfer, amount: 400, frequency: .monthly, startDate: Calendar.current.date(byAdding: .day, value: 15, to: nextMonth)!)
            let subscription = RecurringTransaction(kind: .withdrawal, amount: 99, payee: "Cloud Storage", frequency: .yearly, startDate: daysAgo(-40))
            [rent, pay, toSavings, subscription].forEach(context.insert)
            rent.account = checking
            rent.category = housing
            pay.account = checking
            toSavings.account = checking
            toSavings.otherAccount = savings
            subscription.account = creditCard

            // Everything above goes into the first book. A second, smaller book to switch to.
            try! Books.prepare(in: context)
            let household = Book(name: "Household", createdAt: .now.addingTimeInterval(1))
            context.insert(household)
            let joint = Account(name: "Joint Checking", initialBalance: 640, iconName: "house")
            context.insert(joint)
            joint.book = household
            let essentials = try! Ledger.category(named: "Essentials", book: household, in: context)
            Ledger.addTransaction(.withdrawal, amount: 120, to: joint, date: daysAgo(2), payee: "Hardware Store", category: essentials, in: context)
            try! context.save()

            return container
        }()

        /// An in-memory store with one empty book, for previews of empty screens.
        static var emptyPreview: ModelContainer {
            let container = try! ModelContainer(
                for: Schema(AppSchema.models),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            try! Books.prepare(in: container.mainContext)
            return container
        }

        /// The first book, for previews of screens that show one book.
        var firstBook: Book {
            try! mainContext.fetch(FetchDescriptor<Book>(sortBy: Book.order)).first!
        }
    }
#endif
