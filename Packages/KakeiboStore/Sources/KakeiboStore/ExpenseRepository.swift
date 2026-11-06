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
    /// Where receipt photos live. When set, deleting an expense also deletes its photo.
    public let photoStore: PhotoStore?

    /// Held so the container outlives its context: SwiftData traps if a context's container is freed.
    private let container: ModelContainer?
    /// Tests: runs right before each save; throwing simulates a failed save.
    var beforeSave: (() throws -> Void)?

    /// - Parameter context: a context whose container the caller keeps alive.
    public init(context: ModelContext, photoStore: PhotoStore? = nil) {
        self.context = context
        self.photoStore = photoStore
        self.container = nil
    }

    /// Uses the container's main context and keeps the container alive.
    public init(container: ModelContainer, photoStore: PhotoStore? = nil) {
        self.context = container.mainContext
        self.photoStore = photoStore
        self.container = container
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
            receiptNumber: draft.receiptNumber,
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
        try save()
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
        expense.receiptNumber = draft.receiptNumber
        if let note { expense.note = note }

        for item in expense.items { context.delete(item) }
        expense.items = Self.makeItems(draft.items)
        // The user has confirmed every field.
        expense.confidence = .high
        expense.updatedAt = now
        try save()
    }

    /// Applies a change made directly to the model and saves it, bumping `updatedAt`.
    public func update(_ expense: Expense, now: Date = .now, _ change: (Expense) -> Void) throws {
        change(expense)
        _ = try Self.validDayKey(expense.dayKey)
        expense.updatedAt = now
        try save()
    }

    // MARK: - Delete

    /// Deletes an expense, its items and its photo file.
    ///
    /// The record is deleted first: if removing the file then fails, the file is an orphan
    /// that `removeOrphanPhotos()` cleans up, rather than an expense pointing at a missing photo.
    public func delete(_ expense: Expense) throws {
        let photo = expense.photoFileName
        context.delete(expense)
        try save()
        if let photo, let photoStore {
            try photoStore.delete(photo)
        }
    }

    /// Saves the context; on failure rolls back the unsaved change and rethrows, so a failed
    /// save leaves nothing half-done in memory (and posts no `ModelContext.didSave`).
    private func save() throws {
        do {
            try beforeSave?()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Deletes photo files that no expense refers to, and returns how many were deleted.
    /// Run at launch or from Settings.
    @discardableResult
    public func removeOrphanPhotos() throws -> Int {
        guard let photoStore else { return 0 }
        var descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.photoFileName != nil })
        descriptor.propertiesToFetch = [\.photoFileName]
        let names = Set(try context.fetch(descriptor).compactMap(\.photoFileName))
        return try photoStore.removeOrphans(keeping: names)
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

    // MARK: - Duplicates

    /// A saved expense that looks like the draft being saved.
    public struct PossibleDuplicate {
        public enum Strength: Comparable, Sendable {
            /// Same store, day, total and time (or a time missing on one side).
            case likely
            /// Same receipt number, store and day: almost certainly the same receipt.
            case strong
        }

        public let expense: Expense
        public let strength: Strength
    }

    /// Saved expenses the draft may duplicate, strong matches first, then newest first.
    ///
    /// - **Strong:** same receipt number (leading zeros ignored), same store, same day.
    /// - **Likely:** same store, same day, same total, and the same time or a time missing on one side.
    ///
    /// "Same store" compares invoice numbers when both sides have one, otherwise the normalized
    /// store names (exact, no fuzzy matching; an empty name matches nothing). The invoice number
    /// alone is never enough: it is the same on every receipt from a shop.
    ///
    /// - Parameter id: an expense to leave out, so editing an expense never matches itself.
    public func possibleDuplicates(of draft: ReceiptDraft, excluding id: UUID? = nil) throws -> [PossibleDuplicate] {
        guard let dayKey = draft.dayKey else { return [] }
        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.dayKey == dayKey },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
            .filter { $0.id != id }
            .compactMap { expense in
                Self.duplicateStrength(of: draft, against: expense).map { PossibleDuplicate(expense: expense, strength: $0) }
            }
            .sorted { $0.strength > $1.strength }   // stable: keeps newest first within a strength
    }

    static func duplicateStrength(of draft: ReceiptDraft, against expense: Expense) -> PossibleDuplicate.Strength? {
        guard draft.dayKey == expense.dayKey,
              isSameStore(draft.invoiceNumber, draft.storeName, expense.invoiceNumber, expense.storeName)
        else { return nil }

        if let a = draft.receiptNumber.flatMap(ReceiptNumberParser.comparisonKey),
           let b = expense.receiptNumber.flatMap(ReceiptNumberParser.comparisonKey), a == b {
            return .strong
        }
        let sameTime = draft.time == nil || expense.time == nil || draft.time == expense.time
        if draft.totalYen == expense.totalYen, sameTime {
            return .likely
        }
        return nil
    }

    private static func isSameStore(_ invoiceA: String?, _ nameA: String?, _ invoiceB: String?, _ nameB: String?) -> Bool {
        if let invoiceA, let invoiceB, !invoiceA.isEmpty, !invoiceB.isEmpty {
            return invoiceA == invoiceB
        }
        let a = TextNormalizer.normalizeLine(nameA ?? "")
        let b = TextNormalizer.normalizeLine(nameB ?? "")
        return !a.isEmpty && a.unicodeScalars.elementsEqual(b.unicodeScalars)
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
