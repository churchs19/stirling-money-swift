import Foundation

extension AccountTransaction {
    /// Whether the register search text matches the payee, note, category or check number.
    func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let fields = [displayPayee, note, category?.name ?? "", checkNumber.map(String.init) ?? ""]
        return fields.contains { $0.localizedStandardContains(query) }
    }
}
