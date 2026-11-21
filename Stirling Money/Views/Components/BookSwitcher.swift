import SwiftData
import SwiftUI

extension View {
    /// Adds the book menu to the toolbar (switch, new, rename, delete), and the book's name under the title when
    /// there's more than one book.
    func bookSwitcher(_ book: Book) -> some View {
        modifier(BookSwitcher(book: book))
    }
}

/// The book menu. Choosing a book saves its `syncID` as the current one; `RootView` shows it.
private struct BookSwitcher: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: Book.order) private var books: [Book]
    @AppStorage(Books.currentKey) private var currentBookID = ""

    let book: Book

    @State private var naming: Naming?
    @State private var name = ""
    @State private var isConfirmingDelete = false

    private enum Naming {
        case new, rename
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func body(content: Content) -> some View {
        content
            // An empty subtitle shows nothing.
            .navigationSubtitle(books.count > 1 ? book.name : "")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    menu
                }
            }
            .alert(naming == .rename ? "Rename Book" : "New Book", isPresented: isNaming) {
                TextField("Name", text: $name)
                    .capitalizesWords()
                Button("Cancel", role: .cancel) {}
                Button(naming == .rename ? "Save" : "Add", action: saveName)
                    .disabled(trimmedName.isEmpty)
            } message: {
                if naming == .new {
                    Text("A book keeps its own accounts, categories, budgets and goals.")
                }
            }
            .confirmationDialog(
                "Delete \(book.name)?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Book", role: .destructive, action: deleteBook)
            } message: {
                Text("This deletes its ^[\(book.accounts?.count ?? 0) account](inflect: true) and everything in them, its categories, budgets and goals. This can't be undone.")
            }
    }

    private var menu: some View {
        Menu {
            Picker("Book", selection: selection) {
                ForEach(books) { book in
                    Text(book.name).tag(book.syncID)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Button("New Book…", systemImage: "plus") {
                afterMenuCloses { startNaming(.new) }
            }
            .accessibilityIdentifier("newBook")
            Button("Rename \(book.name)…", systemImage: "pencil") {
                afterMenuCloses { startNaming(.rename) }
            }
            Button("Delete \(book.name)…", systemImage: "trash", role: .destructive) {
                afterMenuCloses { isConfirmingDelete = true }
            }
            .disabled(books.count < 2)
        } label: {
            Label("Books", systemImage: "books.vertical")
        }
        .accessibilityIdentifier("bookMenu")
    }

    /// The current book's ID; picking one switches to it.
    private var selection: Binding<String> {
        Binding {
            book.syncID
        } set: { id in
            currentBookID = id
        }
    }

    private var isNaming: Binding<Bool> {
        Binding {
            naming != nil
        } set: { isShown in
            if !isShown {
                naming = nil
            }
        }
    }

    private func startNaming(_ kind: Naming) {
        name = kind == .rename ? book.name : ""
        naming = kind
    }

    private func saveName() {
        guard !trimmedName.isEmpty else { return }
        switch naming {
        case .rename:
            book.name = trimmedName
        case .new:
            if let newBook = Books.create(named: trimmedName, in: modelContext) {
                // Saved first so the switch finds it in the store.
                try? modelContext.save()
                currentBookID = newBook.syncID
            }
        case nil:
            break
        }
    }

    private func deleteBook() {
        let remaining = books.first { $0 !== book }
        guard (try? Books.delete(book, in: modelContext)) == true else { return }
        currentBookID = remaining?.syncID ?? ""
    }
}
