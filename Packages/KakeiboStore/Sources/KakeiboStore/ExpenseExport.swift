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

    /// A written file and what is in it, for the export screen's choices.
    public struct PreparedFile: Equatable, Sendable {
        public let url: URL
        /// Expenses in the file.
        public let count: Int
        /// Their total, as the ledger adds it (`MonthSpend.total`); nil if it overflows.
        public let totalYen: Int?

        /// Nothing to share: the file holds only the header.
        public var isEmpty: Bool { count == 0 }
    }

    /// Writes the month's file and returns it with its count and total, from one read.
    public func prepare(month: LedgerMonth) throws -> PreparedFile {
        let expenses = try repository.expenses(inMonth: month.key)
        let url = try write(expenses, name: ExpenseCSV.fileName(month: month))
        return PreparedFile(url: url, count: expenses.count, totalYen: MonthSpend.total(expenses))
    }

    /// Writes the year's file and returns it with its count and total, from one read.
    public func prepare(year: Int) throws -> PreparedFile {
        let expenses = try repository.expenses(inYear: year)
        let url = try write(expenses, name: ExpenseCSV.fileName(year: year))
        return PreparedFile(url: url, count: expenses.count, totalYen: MonthSpend.total(expenses))
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

extension Expense {
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
