import CloudKit
import CoreTransferable
import SwiftData
import SwiftUI

extension View {
    /// Adds the book menu to the toolbar (switch, new, rename, share, delete or leave), and the book's name under the
    /// title when there's more than one book or it's shared.
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
    @State private var isConfirmingStopSharing = false
    @State private var sharingError: String?

    private enum Naming {
        case new, rename
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func body(content: Content) -> some View {
        content
            // An empty subtitle shows nothing.
            .navigationSubtitle(subtitle)
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
                book.isOwnedByMe ? "Delete \(book.name)?" : "Leave \(book.name)?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button(book.isOwnedByMe ? "Delete Book" : "Leave Book", role: .destructive, action: deleteBook)
            } message: {
                if book.isOwnedByMe {
                    if book.isShared {
                        Text("This deletes its ^[\(book.accounts?.count ?? 0) account](inflect: true) and everything in them, its categories, budgets and goals, for everyone it's shared with. This can't be undone.")
                    } else {
                        Text("This deletes its ^[\(book.accounts?.count ?? 0) account](inflect: true) and everything in them, its categories, budgets and goals. This can't be undone.")
                    }
                } else {
                    Text("It's removed from your devices. \(book.ownerName ?? "The owner") would have to share it again.")
                }
            }
            .confirmationDialog(
                "Stop sharing \(book.name)?",
                isPresented: $isConfirmingStopSharing,
                titleVisibility: .visible
            ) {
                Button("Stop Sharing", role: .destructive, action: stopSharing)
            } message: {
                Text("Everyone you shared it with loses it. It stays on your devices.")
            }
            .alert("Sharing Didn't Work", isPresented: Binding { sharingError != nil } set: { if !$0 { sharingError = nil } }) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sharingError ?? "")
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
            .disabled(!book.canEdit)

            if book.isOwnedByMe, SyncCoordinator.shared != nil {
                // The system's sharing sheet: invite people (by Apple ID, Messages, Mail…) and set each one to
                // Can Make Changes or View Only; for a shared book, it manages who has it.
                ShareLink(item: BookShare(syncID: book.syncID, name: book.name), preview: SharePreview(book.name)) {
                    Label(book.isShared ? "Manage Sharing…" : "Share \(book.name)…", systemImage: "person.crop.circle.badge.plus")
                }
                .accessibilityIdentifier("shareBook")
                if book.isShared {
                    Button("Stop Sharing…", systemImage: "person.crop.circle.badge.xmark") {
                        afterMenuCloses { isConfirmingStopSharing = true }
                    }
                }
            }

            if book.isOwnedByMe {
                Button("Delete \(book.name)…", systemImage: "trash", role: .destructive) {
                    afterMenuCloses { isConfirmingDelete = true }
                }
                .disabled(books.count < 2)
            } else {
                Button("Leave \(book.name)…", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    afterMenuCloses { isConfirmingDelete = true }
                }
                .disabled(books.count < 2)
            }
        } label: {
            Label("Books", systemImage: "books.vertical")
        }
        .accessibilityIdentifier("bookMenu")
    }

    /// The book's name when there's more than one book or it's shared, with its owner's name if it isn't the user's.
    private var subtitle: String {
        guard books.count > 1 || book.isShared else { return "" }
        guard !book.isOwnedByMe else { return book.name }
        if let owner = book.ownerName {
            return String(localized: "\(book.name), shared by \(owner)")
        }
        return String(localized: "\(book.name), shared with you")
    }

    private func stopSharing() {
        Task {
            do {
                try await SyncCoordinator.shared?.stopSharing(book)
            } catch {
                sharingError = error.localizedDescription
            }
        }
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

/// A book to share, for the system's sharing sheet. Makes the book's zone-wide share when the sheet asks for it,
/// or hands over the one it has.
private struct BookShare: Transferable {
    let syncID: String
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            .prepareShare(container: CKContainer(identifier: SyncCoordinator.containerIdentifier)) {
                try await SyncCoordinator.share(bookWithID: item.syncID)
            }
        }
    }
}
