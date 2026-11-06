import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Every transaction as CSV (RFC 4180), for backup or a spreadsheet.
enum TransactionCSV {
    static let header = ["Date", "Account", "Type", "Payee", "Category", "Amount", "Posted", "Check Number", "Note"]

    /// Oldest first. Dates are local calendar days ("2026-11-05"); amounts are signed with a "." decimal
    /// point whatever the locale, so spreadsheets read them as numbers. A transfer appears once in each
    /// account, with "Transfer to/from …" as the payee.
    static func make(_ transactions: [AccountTransaction], timeZone: TimeZone = .current) -> String {
        let dateStyle = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day()
        let sorted = transactions.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return ($0.account?.name ?? "").localizedStandardCompare($1.account?.name ?? "") == .orderedAscending
        }
        let rows = sorted.map { transaction in
            [
                transaction.date.formatted(dateStyle),
                text(transaction.account?.name ?? ""),
                transaction.kind.title,
                text(transaction.displayPayee),
                text(transaction.category?.name ?? ""),
                "\(transaction.amount)",
                transaction.isPosted ? "Yes" : "No",
                transaction.checkNumber.map(String.init) ?? "",
                text(transaction.note),
            ]
        }
        return ([header] + rows)
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes a field if it contains a comma, quote or line break, doubling any quotes.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Free text typed by the user. Text starting with =, +, - or @ gets a leading apostrophe so a
    /// spreadsheet shows it as text instead of running it as a formula.
    static func text(_ value: String) -> String {
        guard let first = value.first, "=+-@".contains(first) else { return value }
        return "'" + value
    }
}

/// A CSV file to share or save, written to a temporary file when it's shared.
struct CSVExportFile: Transferable {
    let text: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appending(path: file.filename)
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
        .suggestedFileName { $0.filename }
    }
}
