import KakeiboCore
import KakeiboStore
import SwiftUI

/// "Export expenses" (visual refresh, UI-05): choose the shown month or its whole year, then
/// hand the CSV to the iOS share sheet. Both files are written when the sheet opens (they are
/// small); the CSV format itself is `ExpenseCSV`'s and does not change here.
///
/// B-12: the files are protected while they exist (`ScratchFiles`). A file is deleted when its
/// share sheet finishes (shared, saved or cancelled) and written again if Share is tapped once
/// more; all of them are deleted when this screen closes.
struct ExportSheet: View {
    let month: LedgerMonth
    let repository: ExpenseRepository
    @Environment(\.dismiss) private var dismiss

    enum Period: Hashable { case month, year }

    private enum Load {
        case loading
        case ready(month: ExpenseExport.PreparedFile, year: ExpenseExport.PreparedFile)
        case failed
    }

    @State private var load: Load = .loading
    @State private var period: Period = .month
    /// The file in the open share sheet.
    @State private var sharing: SharedFile?
    /// The last file handed to the share sheet, deleted when the sheet has gone.
    @State private var sharedURL: URL?

    struct SharedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(title: "export.title") {
                Button("export.close") { dismiss() }
                    .buttonStyle(TextButtonStyle())
                    .accessibilityIdentifier("export.close")
            } trailing: {
                EmptyView()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("export.headline")
                            .font(.title.weight(.bold))
                            .foregroundStyle(Theme.text)
                            .accessibilityAddTraits(.isHeader)
                        Text("export.subtitle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    content
                    Label("export.note", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .screenInset()
                .padding(.vertical, Spacing.s)
            }
            .scrollBounceBehavior(.basedOnSize)
            shareBar
        }
        .background(Theme.groundLight.ignoresSafeArea())
        .task { prepare() }
        .sheet(item: $sharing, onDismiss: removeShared) { file in
            ActivityShareSheet(url: file.url) { sharing = nil }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        // Nothing is left behind once the screen has gone, whatever was or was not shared.
        .onDisappear {
            AppServices.logProtection("exports on close", ScratchFiles.exportDirectory)
            try? makeExport().removeAll()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export")
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch load {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityLabel(Text("export.preparing"))
        case .failed:
            failure
        case .ready(let monthFile, let yearFile):
            VStack(spacing: 0) {
                ChoiceRow(
                    title: Text(verbatim: LedgerFormat.monthTitle(month)),
                    file: monthFile,
                    selected: period == .month,
                    id: "export.choice.month"
                ) { period = .month }
                Divider().overlay(Theme.divider)
                ChoiceRow(
                    title: Text("export.year \(String(month.year))"),
                    file: yearFile,
                    selected: period == .year,
                    id: "export.choice.year"
                ) { period = .year }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityElement(children: .contain)

            formatCard(selectedFile(monthFile, yearFile))
        }
    }

    /// "CSV spreadsheet  .csv", what is in it, and the file name.
    private func formatCard(_ file: ExpenseExport.PreparedFile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            AdaptiveStack(spacing: Spacing.xs) {
                Text("export.csv.title")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                Tag(verbatim: ".csv")
            }
            Text("export.csv.body")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: file.url.lastPathComponent)
                .font(.code)
                .foregroundStyle(Theme.text)
        }
        .card()
        // Read as one sentence; a file name alone is not readable text for VoiceOver.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("export.format")
    }

    /// The file could not be written: say so, and offer to try again. Nothing to share.
    private var failure: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label {
                Text("export.failed")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.warningText)
            .accessibilityIdentifier("export.failed")
            Button("export.retry") { prepare() }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("export.retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(Theme.warningFill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: Share

    /// "Share CSV" opens the iOS share sheet with the chosen file. Disabled with nothing to share.
    private var shareBar: some View {
        Group {
            if case .ready(let monthFile, let yearFile) = load, !selectedFile(monthFile, yearFile).isEmpty {
                Button(action: share) {
                    Label("export.share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            } else {
                Button {} label: { Label("export.share", systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(true)
            }
        }
        .accessibilityIdentifier("export.share")
        .screenInset()
        .padding(.top, 10)
        .padding(.bottom, Spacing.xs)
        .background(Theme.groundLight)
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
    }

    private func selectedFile(_ monthFile: ExpenseExport.PreparedFile,
                              _ yearFile: ExpenseExport.PreparedFile) -> ExpenseExport.PreparedFile {
        period == .month ? monthFile : yearFile
    }

    // MARK: Files

    /// Opens the share sheet with the chosen file, writing it again if an earlier share
    /// sheet has already removed it.
    private func share() {
        guard case .ready(let monthFile, let yearFile) = load else { return }
        var file = selectedFile(monthFile, yearFile)
        if !FileManager.default.fileExists(atPath: file.url.path) {
            let export = makeExport()
            do {
                if period == .month {
                    file = try export.prepare(month: month)
                    load = .ready(month: file, year: yearFile)
                } else {
                    file = try export.prepare(year: month.year)
                    load = .ready(month: monthFile, year: file)
                }
            } catch {
                load = .failed
                return
            }
        }
        sharedURL = file.url
        sharing = SharedFile(url: file.url)
    }

    /// The share sheet has gone: the file was shared, saved or cancelled, so it goes too.
    private func removeShared() {
        guard let sharedURL else { return }
        self.sharedURL = nil
        AppServices.logProtection("export", sharedURL.deletingLastPathComponent())
        try? makeExport().remove(sharedURL)
    }

    private func prepare() {
        load = .loading
        let export = makeExport()
        do {
            load = .ready(month: try export.prepare(month: month), year: try export.prepare(year: month.year))
        } catch {
            load = .failed
        }
    }

    private func makeExport() -> ExpenseExport {
        #if DEBUG
        // UI tests: `KAKEIBO_FAIL_EXPORT=1` writes into a folder that cannot exist, so the export fails.
        if ProcessInfo.processInfo.environment["KAKEIBO_FAIL_EXPORT"] == "1" {
            return ExpenseExport(repository: repository, directory: URL(fileURLWithPath: "/dev/null/Export"))
        }
        #endif
        return ExpenseExport(repository: repository)
    }
}

/// One period to export: a radio mark, its name, and "4 receipts · ¥5,198" (or "Nothing to
/// export"). Selected is said by VoiceOver, not shown by color alone.
private struct ChoiceRow: View {
    let title: Text
    let file: ExpenseExport.PreparedFile
    let selected: Bool
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    title.font(.bodyEmphasis).foregroundStyle(Theme.text)
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Spacing.s)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // "November 2026, 4 receipts, 5,198 yen, selected".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Text(verbatim: spokenDetail))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier(id)
    }

    /// "4 receipts · ¥5,198", or "Nothing to export".
    private var detail: String {
        guard !file.isEmpty else { return String(localized: "export.empty") }
        let receipts = String(localized: "ledger.receipts \(file.count)")
        guard let total = file.totalYen else { return receipts }
        return "\(receipts) · \(LedgerFormat.yen(total))"
    }

    private var spokenDetail: String {
        guard !file.isEmpty else { return String(localized: "export.empty") }
        let receipts = String(localized: "ledger.receipts \(file.count)")
        guard let total = file.totalYen else { return receipts }
        return "\(receipts), \(LedgerFormat.spokenYen(total))"
    }
}
