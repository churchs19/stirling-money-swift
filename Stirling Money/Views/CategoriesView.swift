import SwiftData
import SwiftUI

/// Lists categories with how many transactions use each; add, rename and delete.
struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var categories: [Category]

    /// The category being renamed, or nil while adding a new one.
    @State private var renaming: Category?
    @State private var isNaming = false
    @State private var name = ""
    @State private var pendingDeletion: Category?

    private var sortedCategories: [Category] {
        categories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Two categories with the same name would be indistinguishable in pickers.
    private var nameIsTaken: Bool {
        (try? Ledger.existingCategory(named: trimmedName, excluding: renaming, in: modelContext)) != nil
    }

    var body: some View {
        List {
            ForEach(sortedCategories) { category in
                Button {
                    startRenaming(category)
                } label: {
                    LabeledContent(category.name) {
                        Text("^[\(category.transactions?.count ?? 0) transaction](inflect: true)")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        pendingDeletion = category
                    }
                }
                .contextMenu {
                    Button("Rename…", systemImage: "pencil") {
                        startRenaming(category)
                    }
                    Button("Delete…", systemImage: "trash", role: .destructive) {
                        pendingDeletion = category
                    }
                }
            }
        }
        .overlay {
            if categories.isEmpty {
                ContentUnavailableView(
                    "No Categories",
                    systemImage: "tag",
                    description: Text("Add categories here, or while entering a transaction.")
                )
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Category", systemImage: "plus") {
                    renaming = nil
                    name = ""
                    isNaming = true
                }
            }
        }
        .alert(renaming == nil ? "New Category" : "Rename Category", isPresented: $isNaming) {
            TextField("Name", text: $name)
                .capitalizesWords()
            Button("Cancel", role: .cancel) {}
            Button("Save", action: saveName)
                .disabled(trimmedName.isEmpty || nameIsTaken)
        } message: {
            if nameIsTaken {
                Text("A category named \(trimmedName) already exists.")
            }
        }
        .confirmationDialog(
            pendingDeletion.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: {
                    if !$0 {
                        pendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { category in
            Button("Delete Category", role: .destructive) {
                withAnimation {
                    modelContext.delete(category)
                }
            }
        } message: { category in
            deletionMessage(for: category)
        }
    }

    private func startRenaming(_ category: Category) {
        renaming = category
        name = category.name
        isNaming = true
    }

    private func saveName() {
        guard !trimmedName.isEmpty, !nameIsTaken else { return }
        if let renaming {
            renaming.name = trimmedName
        } else {
            withAnimation {
                modelContext.insert(Category(name: trimmedName))
            }
        }
    }

    private func deletionMessage(for category: Category) -> Text {
        let transactions = category.transactions?.count ?? 0
        let budgets = category.budgets?.count ?? 0
        if budgets > 0 {
            return Text("^[\(transactions) transaction](inflect: true) will have no category, and ^[\(budgets) budget](inflect: true) for it will be deleted.")
        }
        return Text("^[\(transactions) transaction](inflect: true) will have no category.")
    }
}

#Preview("With Categories") {
    NavigationStack {
        CategoriesView()
    }
    .modelContainer(.preview)
}

#Preview("Empty") {
    NavigationStack {
        CategoriesView()
    }
    .modelContainer(for: AppSchema.models, inMemory: true)
}
