import KakeiboCore
import KakeiboStore
import SwiftUI

/// "Check and save": the same screen for a fresh scan, a manual entry and editing.
struct ReviewView: View {
    enum Outcome {
        case saved(totalYen: Int)
        case deleted
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
    @State private var duplicate: ExpenseRepository.PossibleDuplicate?
    #if DEBUG
    @State private var fixtureFiles: FixtureFiles?
    struct FixtureFiles: Identifiable { let id = UUID(); let urls: [URL] }
    #endif
    @FocusState private var amountFocused: Bool

    enum ConfirmKind { case discard, delete }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    if form.hasPhoto { photoCard }
                    else if let text = form.ocrText, !text.isEmpty { ocrCard(text) }
                    amountCard
                    detailsCard
                    categoryCard
                    taxAndItemsCard
                    noteCard
                    if form.isEditing { deleteButton }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            saveBar
        }
        .background(Theme.groundLight.ignoresSafeArea())
        .overlay {
            if let confirm { confirmPanel(confirm) }
            if let duplicate { duplicatePanel(duplicate) }
        }
        .fullScreenCover(isPresented: $showPhoto) {
            PhotoZoomView(image: photoImage)
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
        ZStack {
            Text(title).font(.screenTitle).foregroundStyle(Theme.text)
            HStack {
                Button("review.cancel", action: cancel)
                    .font(.body.weight(.medium))
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("review.cancel")
                Spacer()
                #if DEBUG
                if form.ocrText?.isEmpty == false {
                    Button {
                        if let urls = try? FixtureCapture.makeFiles(from: form) { fixtureFiles = FixtureFiles(urls: urls) }
                    } label: {
                        Image(systemName: "ladybug").frame(minWidth: 44, minHeight: 44)
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityLabel(Text(verbatim: "Save as fixture"))
                    .accessibilityIdentifier("review.fixture")
                }
                #endif
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var title: LocalizedStringKey {
        switch form.mode {
        case .scan: "review.title.scan"
        case .manual: "review.title.manual"
        case .edit: "review.title.edit"
        }
    }

    // MARK: Photo and OCR text

    private var photoCard: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Button { showPhoto = true } label: {
                    Group {
                        if let photoImage {
                            Image(uiImage: photoImage).resizable().scaledToFill()
                        } else {
                            Theme.field
                        }
                    }
                    .frame(width: 58, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
                }
                .accessibilityLabel(Text("review.photo.view"))
                .accessibilityIdentifier("review.photo")

                VStack(alignment: .leading, spacing: 6) {
                    if !form.fieldsToCheck.isEmpty {
                        Text("review.check.count \(form.fieldsToCheck.count)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.warningFill, in: Capsule())
                            .foregroundStyle(Theme.warningText)
                            .accessibilityIdentifier("review.check.count")
                    }
                    if form.isScan {
                        Text("review.photo.caption").font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    if form.isRefining {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("review.refining").font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let text = form.ocrText, !text.isEmpty { ocrDisclosure(text) }
        }
    }

    private func ocrCard(_ text: String) -> some View {
        Card { ocrDisclosure(text) }
    }

    private func ocrDisclosure(_ text: String) -> some View {
        DisclosureGroup {
            Text(verbatim: text)
                .font(.code)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.top, 6)
                .accessibilityIdentifier("review.ocrText")
        } label: {
            Text("review.ocr.show").font(.subheadline.weight(.medium)).foregroundStyle(Theme.accent)
        }
        .tint(Theme.accent)
    }

    private var photoImage: UIImage? {
        if let pending = form.pendingPhoto {
            switch pending {
            case .image(let image): return UIImage(cgImage: image)
            case .data(let data): return UIImage(data: data)
            }
        }
        // UIImage applies the saved EXIF orientation.
        if let name = form.storedPhotoName, let url = try? services.photoStore?.url(for: name) {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }

    // MARK: Amount

    private var amountCard: some View {
        Card(highlight: form.needsCheck(.totalYen)) {
            VStack(alignment: .leading, spacing: 4) {
                Text("review.amount.label")
                    .font(.caption).tracking(0.6)
                    .foregroundStyle(Theme.secondaryText)
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
                    .accessibilityIdentifier("review.amount")
                    if !symbol.isPrefix { Text(verbatim: symbol.symbol).font(.title.weight(.semibold)) }
                }
                .foregroundStyle(Theme.text)
                if form.needsCheck(.totalYen) {
                    Hint("review.hint.amount")
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
                FieldLabel("review.store")
                TextField(text: Binding(
                    get: { form.draft.storeName ?? "" },
                    set: { form.draft.storeName = $0.isEmpty ? nil : $0 }
                ), prompt: Text("review.store.placeholder")) { Text("review.store") }
                    .inputStyle(highlight: form.needsCheck(.storeName))
                    .accessibilityIdentifier("review.store")
                if form.needsCheck(.storeName) { Hint("review.hint.store") }
                if let english = form.draft.storeNameEn {
                    Text("review.store.english \(english)").font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.vertical, 4)

            Divider().overlay(Theme.divider)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("review.date")
                    if let date = form.date {
                        DatePicker(
                            selection: Binding(get: { date }, set: { form.date = $0 }),
                            displayedComponents: .date
                        ) { Text("review.date") }
                            .labelsHidden()
                            .environment(\.timeZone, KakeiboCore.timeZone)
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
                    if form.needsCheck(.dayKey) { Hint("review.hint.date") }
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
                Picker(selection: Binding(
                    get: { form.draft.payment ?? .cash },
                    set: { form.draft.payment = $0 }
                )) {
                    ForEach(PaymentMethod.allCases, id: \.self) { method in
                        Text(verbatim: method.label).tag(method)
                    }
                } label: { Text("review.payment") }
                    .pickerStyle(.menu)
                    .tint(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .inputStyle(highlight: form.needsCheck(.payment))
                    .accessibilityIdentifier("review.payment")
                if form.needsCheck(.payment) { Hint("review.hint.payment") }
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

    // MARK: Tax, invoice, items

    private var taxAndItemsCard: some View {
        Card {
            YenRow(label: "review.tax8", value: taxBinding(\.tax8Yen), id: "review.tax8")
            Divider().overlay(Theme.divider)
            YenRow(label: "review.tax10", value: taxBinding(\.tax10Yen), id: "review.tax10")
            if let invoice = form.draft.invoiceNumber {
                Divider().overlay(Theme.divider)
                HStack {
                    Text("review.invoice").font(.subheadline)
                    Spacer()
                    Text(verbatim: invoice).font(.code)
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
                ForEach(Array(form.draft.items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Divider().overlay(Theme.divider) }
                    ItemRow(item: item)
                }
            }
        }
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

    // MARK: Note and delete

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

    private var deleteButton: some View {
        Button(role: .destructive) { confirm = .delete } label: {
            Text("review.delete").frame(maxWidth: .infinity, minHeight: 44)
        }
        .foregroundStyle(Theme.destructive)
        .accessibilityIdentifier("review.delete")
        .padding(.top, 8)
    }

    // MARK: Save bar

    private var saveBar: some View {
        VStack(spacing: 6) {
            if let problem = form.problems.first {
                Text(problem == .missingAmount ? "review.problem.amount" : "review.problem.date")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            if saveFailed {
                Text("review.saveFailed").font(.caption).foregroundStyle(Theme.destructive)
            }
            Button(action: save) {
                Group {
                    if let total = form.draft.totalYen, total > 0 {
                        Text("review.save \(LedgerFormat.yen(total))")
                    } else {
                        Text("review.save.plain")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle())
            .disabled(!form.canSave)
            .opacity(form.canSave ? 1 : 0.5)
            .accessibilityIdentifier("review.save")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.groundLight)
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
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
        guard form.canSave else { return }
        // A failed check must not stop the save; the warning is only a help.
        if let match = try? form.possibleDuplicates(repository: services.repository).first {
            duplicate = match
            return
        }
        saveNow()
    }

    private func saveNow() {
        duplicate = nil
        guard form.canSave, let total = form.draft.totalYen else { return }
        do {
            try form.save(repository: services.repository, photoStore: services.photoStore)
            onFinish(.saved(totalYen: total))
        } catch {
            saveFailed = true
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
        switch kind {
        case .discard:
            ConfirmPanel(
                title: form.isScan ? "confirm.discard.title.scan" : "confirm.discard.title.changes",
                message: "confirm.discard.message",
                confirmTitle: "confirm.discard.action",
                onConfirm: { onFinish(.discarded) },
                onCancel: { confirm = nil }
            )
        case .delete:
            ConfirmPanel(
                title: "confirm.delete.title",
                message: "confirm.delete.message",
                confirmTitle: "confirm.delete.action",
                onConfirm: {
                    do {
                        try form.delete(repository: services.repository)
                        onFinish(.deleted)
                    } catch {
                        confirm = nil
                        saveFailed = true
                    }
                },
                onCancel: { confirm = nil }
            )
        }
    }
}
