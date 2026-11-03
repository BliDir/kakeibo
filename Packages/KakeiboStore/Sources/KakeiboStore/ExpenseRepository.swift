import Foundation
import KakeiboCore
import SwiftData

/// Reads and writes expenses. Runs on the main actor with the container's main context,
/// because `ModelContext` must not cross threads.
@MainActor
public final class ExpenseRepository {
    public enum Error: Swift.Error, Equatable {
        /// The draft has no date; the review screen must ask for one.
        case missingDayKey
        /// The draft has no total; the review screen must ask for one.
        case missingTotal
        /// `dayKey` is not a real `yyyy-MM-dd` date.
        case invalidDayKey(String)
        /// A month is not `yyyy-MM`.
        case invalidMonth(String)
    }

    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public convenience init(container: ModelContainer) {
        self.init(context: container.mainContext)
    }

    // MARK: - Create

    /// Saves a confirmed draft as a new expense.
    ///
    /// The expense's overall confidence is the lowest of its store, date and total confidences;
    /// a manual entry is always `high`.
    @discardableResult
    public func create(
        from draft: ReceiptDraft,
        source: ExpenseSource,
        note: String = "",
        ocrText: String? = nil,
        photoFileName: String? = nil,
        now: Date = .now
    ) throws -> Expense {
        let (dayKey, totalYen) = try Self.validate(draft)
        let expense = Expense(
            dayKey: dayKey,
            time: draft.time,
            storeName: draft.storeName ?? "",
            storeNameEn: draft.storeNameEn,
            totalYen: totalYen,
            tax10Yen: draft.tax10Yen,
            tax8Yen: draft.tax8Yen,
            payment: draft.payment ?? .cash,
            category: draft.category ?? .other,
            invoiceNumber: draft.invoiceNumber,
            note: note,
            photoFileName: photoFileName,
            ocrText: ocrText,
            source: source,
            confidence: Self.overallConfidence(of: draft, source: source),
            createdAt: now,
            updatedAt: now
        )
        context.insert(expense)
        expense.items = Self.makeItems(draft.items)
        try context.save()
        return expense
    }

    // MARK: - Update

    /// Replaces an expense's fields and items with a corrected draft.
    /// Source, photo, OCR text and creation date are kept.
    public func update(_ expense: Expense, from draft: ReceiptDraft, note: String? = nil, now: Date = .now) throws {
        let (dayKey, totalYen) = try Self.validate(draft)
        expense.dayKey = dayKey
        expense.time = draft.time
        expense.storeName = draft.storeName ?? ""
        expense.storeNameEn = draft.storeNameEn
        expense.totalYen = totalYen
        expense.tax10Yen = draft.tax10Yen
        expense.tax8Yen = draft.tax8Yen
        expense.payment = draft.payment ?? .cash
        expense.category = draft.category ?? .other
        expense.invoiceNumber = draft.invoiceNumber
        if let note { expense.note = note }

        for item in expense.items { context.delete(item) }
        expense.items = Self.makeItems(draft.items)
        // The user has confirmed every field.
        expense.confidence = .high
        expense.updatedAt = now
        try context.save()
    }

    /// Applies a change made directly to the model and saves it, bumping `updatedAt`.
    public func update(_ expense: Expense, now: Date = .now, _ change: (Expense) -> Void) throws {
        change(expense)
        _ = try Self.validDayKey(expense.dayKey)
        expense.updatedAt = now
        try context.save()
    }

    // MARK: - Delete

    /// Deletes an expense and its items. The photo file is removed separately by `PhotoStore`.
    public func delete(_ expense: Expense) throws {
        context.delete(expense)
        try context.save()
    }

    // MARK: - Fetch

    /// Expenses in a month (`yyyy-MM`), newest day first.
    public func expenses(inMonth month: String) throws -> [Expense] {
        guard Self.isValidMonth(month) else { throw Error.invalidMonth(month) }
        return try fetch(prefix: month + "-")
    }

    /// Expenses in a year, newest day first.
    public func expenses(inYear year: Int) throws -> [Expense] {
        try fetch(prefix: String(format: "%04d-", year))
    }

    public func expense(id: UUID) throws -> Expense? {
        var descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetch(prefix: String) throws -> [Expense] {
        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.dayKey.starts(with: prefix) },
            sortBy: [SortDescriptor(\.dayKey, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Helpers

    private static func makeItems(_ drafts: [LineItemDraft]) -> [LineItem] {
        drafts.enumerated().map { index, item in
            LineItem(
                name: item.name,
                nameEn: item.nameEn,
                priceYen: item.priceYen,
                isReducedRate: item.isReducedRate,
                position: index
            )
        }
    }

    private static func validate(_ draft: ReceiptDraft) throws -> (dayKey: String, totalYen: Int) {
        guard let dayKey = draft.dayKey else { throw Error.missingDayKey }
        guard let totalYen = draft.totalYen else { throw Error.missingTotal }
        return (try validDayKey(dayKey), totalYen)
    }

    private static func validDayKey(_ dayKey: String) throws -> String {
        let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard dayKey.count == 10, parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2
        else { throw Error.invalidDayKey(dayKey) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = KakeiboCore.timeZone
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar) else { throw Error.invalidDayKey(dayKey) }
        return dayKey
    }

    private static func isValidMonth(_ month: String) -> Bool {
        let parts = month.split(separator: "-", omittingEmptySubsequences: false)
        guard month.count == 7, parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              Int(parts[0]) != nil, let m = Int(parts[1]) else { return false }
        return (1...12).contains(m)
    }

    private static func overallConfidence(of draft: ReceiptDraft, source: ExpenseSource) -> Confidence {
        guard source == .scan else { return .high }
        return [ReceiptField.storeName, .dayKey, .totalYen].map(draft.confidence(for:)).min() ?? .low
    }
}
