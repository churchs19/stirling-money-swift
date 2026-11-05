import SwiftData

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        Account.self,
        AccountTransaction.self,
        Category.self,
        Budget.self,
        Goal.self,
    ]
}
