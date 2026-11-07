import CoreGraphics
import Foundation
import KakeiboCore
import Observation

/// The "Check and save" form: one model for a fresh scan, a manual entry and editing a saved expense.
///
/// The view binds to `draft` and `note`. Everything the screen decides (which fields to check,
/// whether Save is allowed, what Cancel must confirm) lives here so it is tested with `swift test`.
@MainActor
@Observable
public final class ReviewForm {
    public enum Mode {
        /// A scan that has not been saved yet.
        case scan
        /// Typed in by the user, no photo.
        case manual
        /// A saved expense.
        case edit(Expense)
    }

    /// The receipt photo to save with a new scan.
    public enum PendingPhoto: Sendable {
        /// From the document camera.
        case image(CGImage)
        /// From the photo library, saved with its metadata (minus GPS).
        case data(Data)
    }

    /// Why Save is not allowed yet.
    public enum Problem: Equatable, Sendable {
        case missingAmount
        case missingDate
    }

    public let mode: Mode
    public var draft: ReceiptDraft
    public var note: String
    /// Raw OCR text for the "Text read from the photo" disclosure and for `Expense.ocrText`.
    public let ocrText: String?
    public let pendingPhoto: PendingPhoto?
    /// True while the on-device model is still improving the draft in the background.
    public private(set) var isRefining = false
    /// Set once a background refinement has been applied.
    public private(set) var wasRefined = false

    /// What the form started from, to tell user edits from parser values.
    private var original: ReceiptDraft
    private let originalNote: String

    // MARK: - Init

    /// A fresh scan.
    public init(scan draft: ReceiptDraft, ocrText: String, photo: PendingPhoto?, refining: Bool) {
        mode = .scan
        self.draft = draft
        original = draft
        note = ""
        originalNote = ""
        self.ocrText = ocrText
        pendingPhoto = photo
        isRefining = refining
    }

    /// A manual entry, dated `today`, paid with `payment` (the default from Settings).
    public init(manualOn today: Date, payment: PaymentMethod = .cash) {
        mode = .manual
        let draft = ReceiptDraft(dayKey: DayKey.make(from: today), payment: payment, category: .other)
        self.draft = draft
        original = draft
        note = ""
        originalNote = ""
        ocrText = nil
        pendingPhoto = nil
    }

    /// Editing a saved expense.
    public init(editing expense: Expense) {
        mode = .edit(expense)
        let draft = ReceiptDraft(
            storeName: expense.storeName.isEmpty ? nil : expense.storeName,
            storeNameEn: expense.storeNameEn,
            dayKey: expense.dayKey,
            time: expense.time,
            totalYen: expense.totalYen,
            tax10Yen: expense.tax10Yen,
            tax8Yen: expense.tax8Yen,
            payment: expense.payment,
            category: expense.category,
            invoiceNumber: expense.invoiceNumber,
            receiptNumber: expense.receiptNumber,
            items: expense.orderedItems.map {
                LineItemDraft(name: $0.name, nameEn: $0.nameEn, priceYen: $0.priceYen, isReducedRate: $0.isReducedRate)
            }
        )
        self.draft = draft
        original = draft
        note = expense.note
        originalNote = expense.note
        ocrText = expense.ocrText
        pendingPhoto = nil
    }

    // MARK: - What the screen shows

    public var isScan: Bool { if case .scan = mode { true } else { false } }
    public var isEditing: Bool { if case .edit = mode { true } else { false } }

    /// The saved photo's file name when editing.
    public var storedPhotoName: String? {
        if case .edit(let expense) = mode { expense.photoFileName } else { nil }
    }

    /// True when there is a photo section to show.
    public var hasPhoto: Bool { pendingPhoto != nil || storedPhotoName != nil }

    /// Fields the user should look at: low confidence (or not found) on a scan, and not yet
    /// changed by the user. Manual entries and saved expenses have none.
    public var fieldsToCheck: [ReceiptField] {
        guard isScan else { return [] }
        return Self.checkedFields.filter { field in
            !isEdited(field) && draft.confidence(for: field) == .low
        }
    }

    public func needsCheck(_ field: ReceiptField) -> Bool { fieldsToCheck.contains(field) }

    /// Fields that get a "check" hint when uncertain.
    static let checkedFields: [ReceiptField] = [.totalYen, .storeName, .dayKey, .payment, .category]

    /// True when the total was confirmed by arithmetic (change, subtotal + tax, or items).
    public var isTotalVerified: Bool {
        isScan && !isEdited(.totalYen) && draft.confidence(for: .totalYen) == .high
    }

    public var problems: [Problem] {
        var problems: [Problem] = []
        if (draft.totalYen ?? 0) <= 0 { problems.append(.missingAmount) }
        if draft.dayKey.map(DayKey.isValid) != true { problems.append(.missingDate) }
        return problems
    }

    public var canSave: Bool { problems.isEmpty }

    /// True when leaving would lose something: always for an unsaved scan, otherwise after an edit.
    public var hasUnsavedChanges: Bool {
        if isScan { return true }
        return draft != original || note != originalNote
    }

    // MARK: - Editing helpers

    /// The amount as typed: digits only.
    public var amountText: String {
        get { draft.totalYen.map(String.init) ?? "" }
        set {
            let digits = newValue.filter(\.isASCIIDigit).prefix(9)
            draft.totalYen = digits.isEmpty ? nil : Int(digits)
        }
    }

    /// The date as a `Date` for the date picker (noon, Tokyo). Setting it updates `dayKey`.
    public var date: Date? {
        get { draft.dayKey.flatMap(DayKey.date(from:)) }
        set { draft.dayKey = newValue.map(DayKey.make(from:)) }
    }

    private func isEdited(_ field: ReceiptField) -> Bool {
        switch field {
        case .storeName: draft.storeName != original.storeName
        case .dayKey: draft.dayKey != original.dayKey
        case .time: draft.time != original.time
        case .totalYen: draft.totalYen != original.totalYen
        case .tax10Yen: draft.tax10Yen != original.tax10Yen
        case .tax8Yen: draft.tax8Yen != original.tax8Yen
        case .payment: draft.payment != original.payment
        case .category: draft.category != original.category
        case .invoiceNumber: draft.invoiceNumber != original.invoiceNumber
        case .items: draft.items != original.items
        case .receiptNumber: draft.receiptNumber != original.receiptNumber
        }
    }

    // MARK: - Background refinement

    /// Applies what the on-device model found, keeping every field the user already changed.
    public func applyRefinement(_ refined: ReceiptDraft) {
        let edited = draft
        draft = BackgroundRefinement.apply(refined: refined, original: original, current: edited)
        // From now on, "edited" means changed from the refined values.
        original = refined
        isRefining = false
        wasRefined = true
    }

    /// The refinement finished without changes, failed or was cancelled.
    public func endRefinement() {
        isRefining = false
    }

    // MARK: - Duplicates

    /// Saved expenses this form may duplicate; check before `save`. Scans, manual entries and
    /// edits are all checked, and an edited expense never matches itself.
    public func possibleDuplicates(repository: ExpenseRepository) throws -> [ExpenseRepository.PossibleDuplicate] {
        guard canSave else { return [] }
        var excluded: UUID?
        if case .edit(let expense) = mode { excluded = expense.id }
        return try repository.possibleDuplicates(of: draft, excluding: excluded)
    }

    // MARK: - Save and delete

    /// Saves the form: a new expense (with its photo, for a scan) or the edited one.
    ///
    /// The photo is encoded off the main actor: a full-size JPEG takes a tenth of a second
    /// or more on an iPhone, which froze the screen when it ran on tap.
    @discardableResult
    public func save(repository: ExpenseRepository, photoStore: PhotoStore?, now: Date = .now) async throws -> Expense {
        switch mode {
        case .edit(let expense):
            try repository.update(expense, from: draft, note: note, now: now)
            return expense
        case .manual:
            return try repository.create(from: draft, source: .manual, note: note, now: now)
        case .scan:
            var photoName: String?
            if let pendingPhoto, let photoStore {
                photoName = try await Task.detached(priority: .userInitiated) {
                    try pendingPhoto.save(to: photoStore)
                }.value
            }
            do {
                return try repository.create(from: draft, source: .scan, note: note, ocrText: ocrText,
                                             photoFileName: photoName, now: now)
            } catch {
                // No expense, so no photo: keep the folder free of orphans.
                if let photoName { try? photoStore?.delete(photoName) }
                throw error
            }
        }
    }

    /// Deletes the expense being edited, with its photo. Does nothing for a new entry.
    public func delete(repository: ExpenseRepository) throws {
        guard case .edit(let expense) = mode else { return }
        try repository.delete(expense)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
