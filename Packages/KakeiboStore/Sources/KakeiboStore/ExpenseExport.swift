import Foundation
import KakeiboCore

/// Writes the ledger's CSV files for sharing.
@MainActor
public struct ExpenseExport {
    public let repository: ExpenseRepository
    /// Where files are written. They are recreated on every export and stay on the device
    /// until the user shares them.
    public let directory: URL

    public init(repository: ExpenseRepository,
                directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)) {
        self.repository = repository
        self.directory = directory
    }

    /// `kakeibo-2026-11.csv` with the month's expenses.
    public func file(for month: LedgerMonth) throws -> URL {
        try write(try repository.expenses(inMonth: month.key), name: ExpenseCSV.fileName(month: month))
    }

    /// `kakeibo-2026.csv` with the whole year's expenses.
    public func file(forYear year: Int) throws -> URL {
        try write(try repository.expenses(inYear: year), name: ExpenseCSV.fileName(year: year))
    }

    public static func csv(_ expenses: [Expense]) -> Data {
        // The repository returns newest first; the CSV runs oldest first, and earlier saves
        // come first within a day.
        ExpenseCSV.document(expenses.reversed().map(\.csvRow))
    }

    private func write(_ expenses: [Expense], name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Self.csv(expenses).write(to: url, options: .atomic)
        return url
    }
}

extension KakeiboSchemaV1.Expense {
    var csvRow: CSVExpense {
        CSVExpense(
            dayKey: dayKey, storeName: storeName, category: category, payment: payment,
            totalYen: totalYen, tax10Yen: tax10Yen, tax8Yen: tax8Yen, invoiceNumber: invoiceNumber,
            items: orderedItems.map {
                LineItemDraft(name: $0.name, nameEn: $0.nameEn, priceYen: $0.priceYen, isReducedRate: $0.isReducedRate)
            },
            note: note
        )
    }
}
