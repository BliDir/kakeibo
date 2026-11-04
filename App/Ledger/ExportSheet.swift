import KakeiboCore
import KakeiboStore
import SwiftUI

/// "Export CSV": the shown month or its whole year, through the share sheet.
struct ExportSheet: View {
    let month: LedgerMonth
    let repository: ExpenseRepository
    @Environment(\.dismiss) private var dismiss

    @State private var monthFile: ExportFile?
    @State private var yearFile: ExportFile?
    @State private var failed = false

    struct ExportFile {
        let url: URL
        let count: Int
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                exportRow(
                    title: Text(verbatim: LedgerFormat.monthTitle(month)),
                    file: monthFile,
                    id: "export.month"
                )
                exportRow(
                    title: Text("export.year \(String(month.year))"),
                    file: yearFile,
                    id: "export.year"
                )
                if failed {
                    Text("export.failed").font(.caption).foregroundStyle(Theme.destructive)
                }
                Label("export.note", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.groundLight.ignoresSafeArea())
            .navigationTitle(Text("export.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("export.close") { dismiss() }
                    .accessibilityIdentifier("export.close")
            }
        }
        .task { prepare() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export")
    }

    private func exportRow(title: Text, file: ExportFile?, id: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tablecells")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.bodyEmphasis).foregroundStyle(Theme.text)
                Group {
                    if let file {
                        if file.count > 0 {
                            Text(verbatim: "\(file.url.lastPathComponent) · \(String(localized: "ledger.receipts \(file.count)"))")
                        } else {
                            Text("export.empty")
                        }
                    } else {
                        Text(verbatim: "…")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let file, file.count > 0 {
                ShareLink(item: file.url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(Theme.accent, in: Circle())
                        .foregroundStyle(Theme.onAccent)
                }
                .accessibilityLabel(Text("export.share"))
                .accessibilityIdentifier(id)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Writes both files when the sheet opens; they are small, and the user picks one.
    private func prepare() {
        let export = ExpenseExport(repository: repository)
        do {
            let monthURL = try export.file(for: month)
            let yearURL = try export.file(forYear: month.year)
            monthFile = ExportFile(url: monthURL, count: try repository.expenses(inMonth: month.key).count)
            yearFile = ExportFile(url: yearURL, count: try repository.expenses(inYear: month.year).count)
        } catch {
            failed = true
        }
    }
}
