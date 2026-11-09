import KakeiboCore
import KakeiboStore
import SwiftUI

/// "Check and save": the same form for a fresh scan, a manual entry and editing a saved
/// expense (visual refresh, UI-04). Deleting is on the expense details screen.
struct ReviewView: View {
    enum Outcome {
        case saved(totalYen: Int)
        case discarded
        /// The user chose "View saved entry" on the duplicate warning; nothing was saved.
        case viewSaved(Expense)
    }

    @Bindable var form: ReviewForm
    let services: AppServices
    let onFinish: (Outcome) -> Void

    @State private var confirm: ConfirmKind?
    @State private var showPhoto = false
    @State private var saveFailed = false
    /// Opens with the items when they need checking, so their hint is not hidden (B-13).
    @State private var showMore: Bool
    /// The receipt row's small preview, made in the background (see `ReceiptPhotos`).
    @State private var photoPreview: UIImage?
    /// True while Save writes the photo and the expense, so a second tap does nothing.
    @State private var isSaving = false
    @State private var duplicate: ExpenseRepository.PossibleDuplicate?

    init(form: ReviewForm, services: AppServices, onFinish: @escaping (Outcome) -> Void) {
        self.form = form
        self.services = services
        self.onFinish = onFinish
        _showMore = State(initialValue: form.needsCheck(.items))
    }

    #if DEBUG
    @State private var fixtureFiles: FixtureFiles?
    struct FixtureFiles: Identifiable { let id = UUID(); let urls: [URL] }
    #endif
    @FocusState private var amountFocused: Bool
    @Environment(\.isAccessibilityTextSize) private var isAccessibilityTextSize

    enum ConfirmKind { case discard }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    if form.hasPhoto { photoSection }
                    amountCard
                    detailsCard
                    categoryCard
                    moreCard
                    noteCard
                }
                .screenInset()
                .padding(.vertical, Spacing.xs)
            }
            .scrollDismissesKeyboard(.interactively)
            saveBar
        }
        .background(Theme.groundLight.ignoresSafeArea())
        .overlay {
            if let confirm { confirmPanel(confirm) }
            if let duplicate { duplicatePanel(duplicate) }
            if saveFailed {
                FailurePanel(kind: .save, summary: .draft(form.draft), onRetry: saveNow, onBack: { saveFailed = false })
            }
        }
        .animation(.easeOut(duration: 0.2), value: confirm != nil)
        .animation(.easeOut(duration: 0.2), value: duplicate != nil)
        .animation(.easeOut(duration: 0.2), value: saveFailed)
        .fullScreenCover(isPresented: $showPhoto) {
            PhotoZoomView { await loadPhoto(maxPixelSize: ReceiptPhotos.zoomPixelSize) }
        }
        .task {
            guard form.hasPhoto else { return }
            photoPreview = await loadPhoto(maxPixelSize: ReceiptPhotos.previewPixelSize)
        }
        #if DEBUG
        .sheet(item: $fixtureFiles) { files in
            FixtureShareSheet(urls: files.urls).presentationDetents([.medium])
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review")
    }

    // MARK: Header

    private var header: some View {
        TitleBar(title: title) {
            Button("review.cancel", action: cancel)
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("review.cancel")
        } trailing: {
            #if DEBUG
            if form.ocrText?.isEmpty == false {
                Button {
                    if let urls = try? FixtureCapture.makeFiles(from: form) { fixtureFiles = FixtureFiles(urls: urls) }
                } label: {
                    Image(systemName: "ladybug")
                }
                .buttonStyle(TextButtonStyle())
                .accessibilityLabel(Text(verbatim: "Save as fixture"))
                .accessibilityIdentifier("review.fixture")
            }
            #endif
            modeTag
        }
    }

    /// "2 to check" on a scan with uncertain fields, "Manual" or "Saved".
    @ViewBuilder private var modeTag: some View {
        switch form.mode {
        case .scan:
            if !form.fieldsToCheck.isEmpty {
                Tag("review.check.count \(form.fieldsToCheck.count)", tone: .warning)
                    .accessibilityIdentifier("review.check.count")
            }
        case .manual:
            Tag("review.tag.manual")
        case .edit:
            Tag("review.tag.saved")
        }
    }

    private var title: LocalizedStringKey {
        switch form.mode {
        case .scan: "review.title.scan"
        case .manual: "review.title.manual"
        case .edit: "review.title.edit"
        }
    }

    // MARK: Receipt photo

    /// The receipt as a row that opens it full screen, the on-device line and refinement status.
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ReceiptLink(
                image: photoPreview,
                title: form.isScan ? "review.receipt.captured" : "review.receipt.original",
                subtitle: receiptSubtitle
            ) { showPhoto = true }
            .accessibilityIdentifier("review.photo")
            if form.isScan {
                Text("review.photo.caption")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            if form.isRefining {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("review.refining").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// "サンプルマート · Thu, Nov 5 · 木 14:32", from the form as it is now.
    private var receiptSubtitle: String {
        var parts: [String] = []
        if let store = form.draft.storeName, !store.isEmpty { parts.append(store) }
        if let dayKey = form.draft.dayKey {
            parts.append([LedgerFormat.shortDay(dayKey), form.draft.time].compactMap { $0 }.joined(separator: " "))
        }
        return parts.joined(separator: " · ")
    }

    private func loadPhoto(maxPixelSize: Int) async -> UIImage? {
        await ReceiptPhotos.load(pending: form.pendingPhoto, storedName: form.storedPhotoName,
                                 photoStore: services.photoStore, maxPixelSize: maxPixelSize)
    }

    // MARK: Amount

    private var amountCard: some View {
        Card(highlight: form.needsCheck(.totalYen)) {
            VStack(alignment: .leading, spacing: 4) {
                Text("review.amount.label")
                    .font(.overline).tracking(0.6)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    // "¥ 1234" in English, "1234 円" in Japanese.
                    let symbol = Yen.fieldSymbol(for: LedgerFormat.language)
                    if symbol.isPrefix { Text(verbatim: symbol.symbol).font(.amountHero) }
                    TextField(text: $form.amountText, prompt: Text(verbatim: "0")) {
                        Text("review.amount.label")
                    }
                    .font(.amountHero)
                    .keyboardType(.numberPad)
                    .focused($amountFocused)
                    .fixedSize(horizontal: !symbol.isPrefix, vertical: false)
                    .checkHint(form.needsCheck(.totalYen), "review.hint.amount")
                    .accessibilityIdentifier("review.amount")
                    if !symbol.isPrefix { Text(verbatim: symbol.symbol).font(.title.weight(.semibold)) }
                }
                .foregroundStyle(Theme.text)
                if form.needsCheck(.totalYen) {
                    Hint("review.hint.amount", announced: false)
                } else if form.isTotalVerified {
                    Label("review.amount.verified", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(Theme.success)
                }
            }
        }
    }

    // MARK: Store, date, time, payment

    private var detailsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(form.isScan || form.isEditing ? "review.store" : "review.store.manual")
                // Single line normally; at the accessibility sizes it wraps so a long name stays readable.
                // (A multi-line field's placeholder is invisible to VoiceOver, so only there.)
                TextField(text: Binding(
                    get: { form.draft.storeName ?? "" },
                    set: { form.draft.storeName = $0.isEmpty ? nil : $0 }
                ), prompt: Text(form.isScan || form.isEditing ? "review.store.placeholder" : "review.store.manual.placeholder"),
                   axis: isAccessibilityTextSize ? .vertical : .horizontal) { Text("review.store") }
                    .lineLimit(1...4)
                    .inputStyle(highlight: form.needsCheck(.storeName))
                    .checkHint(form.needsCheck(.storeName), "review.hint.store")
                    .accessibilityIdentifier("review.store")
                if form.needsCheck(.storeName) { Hint("review.hint.store", announced: false) }
                if let english = form.draft.storeNameEn {
                    Text("review.store.english \(english)").font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.vertical, 4)

            Divider().overlay(Theme.divider)

            AdaptiveStack(verticalAlignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("review.date")
                    if let date = form.date {
                        DatePicker(
                            selection: Binding(get: { date }, set: { form.date = $0 }),
                            displayedComponents: .date
                        ) { Text("review.date") }
                            .labelsHidden()
                            .environment(\.timeZone, KakeiboCore.timeZone)
                            .checkHint(form.needsCheck(.dayKey), "review.hint.date")
                            .accessibilityIdentifier("review.date")
                    } else {
                        Button { form.date = .now } label: { Text("review.date.add") }
                            .inputStyle(highlight: true)
                            .accessibilityIdentifier("review.date.add")
                    }
                    // Receipts often print the era year, so show it beside the picker in Japanese.
                    if LedgerFormat.language == .ja, let dayKey = form.draft.dayKey,
                       let era = JapaneseEra.dateLabel(dayKey: dayKey) {
                        Text(verbatim: era)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityIdentifier("review.date.era")
                    }
                    if form.needsCheck(.dayKey) { Hint("review.hint.date", announced: false) }
                }
                if let time = form.draft.time {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel("review.time")
                        Text(verbatim: time)
                            .font(.amountSmall)
                            .foregroundStyle(Theme.text)
                            .frame(minHeight: 34)
                            .accessibilityIdentifier("review.time")
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)

            Divider().overlay(Theme.divider)

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("review.payment")
                PaymentMenu(
                    title: "review.payment",
                    selection: Binding(get: { form.draft.payment ?? .cash }, set: { form.draft.payment = $0 }),
                    highlight: form.needsCheck(.payment)
                )
                    .checkHint(form.needsCheck(.payment), "review.hint.payment")
                    .accessibilityIdentifier("review.payment")
                if form.needsCheck(.payment) { Hint("review.hint.payment", announced: false) }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Category

    private var categoryCard: some View {
        Card(highlight: form.needsCheck(.category)) {
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel("review.category")
                FlowLayout(spacing: 8) {
                    ForEach(ExpenseCategory.allCases, id: \.self) { category in
                        CategoryChip(category: category, selected: form.draft.category == category) {
                            form.draft.category = category
                        }
                    }
                }
                if form.needsCheck(.category) { Hint("review.hint.category") }
            }
        }
    }

    // MARK: Tax, invoice, items and receipt text

    /// Tax, the invoice number, the items and the text read from the photo, folded away: most
    /// receipts need none of it checked. The label says what is inside.
    private var moreCard: some View {
        Card {
            DisclosureGroup(isExpanded: $showMore) {
                VStack(alignment: .leading, spacing: 0) {
                    YenRow(label: "review.tax8", value: taxBinding(\.tax8Yen), id: "review.tax8")
                    Divider().overlay(Theme.divider)
                    YenRow(label: "review.tax10", value: taxBinding(\.tax10Yen), id: "review.tax10")
                    if let invoice = form.draft.invoiceNumber {
                        Divider().overlay(Theme.divider)
                        AdaptiveStack {
                            Text("review.invoice").font(.subheadline).foregroundStyle(Theme.text)
                            Spacer(minLength: 8)
                            Text(verbatim: invoice).font(.code).foregroundStyle(Theme.text)
                                .accessibilityIdentifier("review.invoice")
                        }
                        .padding(.vertical, 10)
                    }
                    if !form.draft.items.isEmpty {
                        Divider().overlay(Theme.divider)
                        HStack {
                            Text("review.items.count \(form.draft.items.count)")
                            Spacer()
                            if form.wasRefined, form.draft.items.contains(where: { $0.nameEn != nil }) {
                                Text("review.items.aiEnglish")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 10)
                        if form.needsCheck(.items) {
                            Hint("review.hint.items").padding(.top, 4)
                        }
                        ForEach(Array(form.draft.items.enumerated()), id: \.offset) { index, item in
                            if index > 0 { Divider().overlay(Theme.divider) }
                            ItemRow(item: item)
                        }
                    }
                    if let text = form.ocrText, !text.isEmpty {
                        Divider().overlay(Theme.divider)
                        OCRDisclosure(text: text).padding(.vertical, 10)
                    }
                }
                .padding(.top, 4)
            } label: {
                Text(moreTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: minimumTapTarget)
                    .accessibilityIdentifier("review.more")
            }
            .tint(Theme.accent)
        }
    }

    private var moreTitle: LocalizedStringKey {
        let hasText = form.ocrText?.isEmpty == false
        if hasText || !form.draft.items.isEmpty { return "review.more.all" }
        return form.draft.invoiceNumber == nil ? "review.more.tax" : "review.more.taxInvoice"
    }

    private func taxBinding(_ path: WritableKeyPath<ReceiptDraft, Int?>) -> Binding<String> {
        Binding(
            get: { form.draft[keyPath: path].map(String.init) ?? "" },
            set: { text in
                let digits = text.filter { $0.isASCII && $0.isNumber }.prefix(9)
                form.draft[keyPath: path] = digits.isEmpty ? nil : Int(digits)
            }
        )
    }

    // MARK: Note

    private var noteCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("review.note")
                TextField(text: $form.note, prompt: Text("review.note.placeholder"), axis: .vertical) {
                    Text("review.note")
                }
                .inputStyle(highlight: false)
                .accessibilityIdentifier("review.note")
            }
        }
    }

    // MARK: Save bar

    private var saveBar: some View {
        VStack(spacing: 6) {
            if let problem = form.problems.first {
                Text(problem == .missingAmount ? "review.problem.amount" : "review.problem.date")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: save) { saveLabel }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .disabled(!form.canSave)
                .accessibilityIdentifier("review.save")
        }
        .screenInset()
        .padding(.top, 10)
        .padding(.bottom, Spacing.xs)
        .background(Theme.groundLight)
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
    }

    /// "Save · ¥1,234" for a new entry, "Save changes" when editing.
    @ViewBuilder private var saveLabel: some View {
        if form.isEditing {
            Text("review.save.changes")
        } else if let total = form.draft.totalYen, total > 0 {
            Text("review.save \(LedgerFormat.yen(total))")
                .accessibilityLabel(Text("review.save \(LedgerFormat.spokenYen(total))"))
        } else {
            Text("review.save.plain")
        }
    }

    // MARK: Actions

    private func cancel() {
        if form.hasUnsavedChanges {
            confirm = .discard
        } else {
            onFinish(.discarded)
        }
    }

    /// Save button: warns first when the ledger already has an expense that looks like this one.
    private func save() {
        guard form.canSave, !isSaving else { return }
        // A failed check must not stop the save; the warning is only a help.
        if let match = try? form.possibleDuplicates(repository: services.repository).first {
            // Put the keyboard away so the whole warning is visible.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            duplicate = match
            return
        }
        saveNow()
    }

    /// Saves without the duplicate check (after "Save anyway", or "Try saving again").
    /// A failure keeps the form as it is and shows the failure panel over it.
    private func saveNow() {
        duplicate = nil
        saveFailed = false
        guard form.canSave, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let expense = try await form.save(repository: services.repository, photoStore: services.photoStore)
                onFinish(.saved(totalYen: expense.totalYen))
            } catch {
                // Put the keyboard away so the whole panel shows; the form keeps everything typed.
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                saveFailed = true
            }
        }
    }

    private func duplicatePanel(_ match: ExpenseRepository.PossibleDuplicate) -> some View {
        DuplicatePanel(
            match: match,
            onView: { onFinish(.viewSaved(match.expense)) },
            onSaveAnyway: saveNow,
            onCancel: { duplicate = nil }
        )
    }

    private func confirmPanel(_ kind: ConfirmKind) -> some View {
        ConfirmPanel(
            systemImage: "arrow.uturn.backward",
            title: form.isScan ? "confirm.discard.title.scan" : "confirm.discard.title.changes",
            message: form.isScan ? "confirm.discard.message.scan" : "confirm.discard.message",
            confirmTitle: form.isScan ? "confirm.discard.action.scan" : "confirm.discard.action",
            keepFirst: true,
            onConfirm: { onFinish(.discarded) },
            onCancel: { confirm = nil }
        )
    }
}

/// "Text read from the photo": the raw OCR text, selectable.
struct OCRDisclosure: View {
    let text: String

    var body: some View {
        DisclosureGroup {
            Text(verbatim: text)
                .font(.code)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.top, 6)
                .accessibilityIdentifier("review.ocrText")
        } label: {
            Text("review.ocr.show")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: minimumTapTarget)
        }
        .tint(Theme.accent)
    }
}
