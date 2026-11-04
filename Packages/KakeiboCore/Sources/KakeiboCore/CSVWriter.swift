import Foundation

/// Writes CSV per RFC 4180, in the shape Excel on Windows opens correctly:
/// UTF-8 with a byte order mark, CRLF line endings, fields quoted when needed.
public enum CSVWriter {
    /// UTF-8 byte order mark. Without it Excel reads the file as Shift-JIS and Japanese is garbled.
    static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// One field. Quoted when it holds a comma, quote, CR or LF; quotes are doubled.
    public static func field(_ value: String) -> String {
        let needsQuotes = value.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
            || value.unicodeScalars.contains { $0 == "\n" || $0 == "\r" }
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// A text field that a spreadsheet must never run as a formula.
    ///
    /// Store names, item names and notes come from OCR or the user. One starting with
    /// `=`, `+`, `-`, `@`, tab or CR would be evaluated by Excel (CSV injection), so it gets a
    /// leading apostrophe, which spreadsheets show as plain text.
    public static func textField(_ value: String) -> String {
        guard let first = value.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) else {
            return field(value)
        }
        return field("'" + value)
    }

    /// One row of already-escaped fields.
    public static func row(_ fields: [String]) -> String {
        fields.joined(separator: ",")
    }

    /// The whole file: BOM, header, rows, each line ending in CRLF.
    public static func document(header: [String], rows: [[String]]) -> Data {
        let lines = [row(header.map(field))] + rows.map(row)
        var data = Data(byteOrderMark)
        data.append(Data(lines.map { $0 + "\r\n" }.joined().utf8))
        return data
    }
}

/// One expense as a CSV row.
public struct CSVExpense: Sendable, Equatable {
    public var dayKey: String
    public var storeName: String
    public var category: ExpenseCategory
    public var payment: PaymentMethod
    public var totalYen: Int
    public var tax10Yen: Int?
    public var tax8Yen: Int?
    public var invoiceNumber: String?
    public var items: [LineItemDraft]
    public var note: String

    public init(dayKey: String, storeName: String, category: ExpenseCategory, payment: PaymentMethod,
                totalYen: Int, tax10Yen: Int?, tax8Yen: Int?, invoiceNumber: String?,
                items: [LineItemDraft], note: String) {
        self.dayKey = dayKey
        self.storeName = storeName
        self.category = category
        self.payment = payment
        self.totalYen = totalYen
        self.tax10Yen = tax10Yen
        self.tax8Yen = tax8Yen
        self.invoiceNumber = invoiceNumber
        self.items = items
        self.note = note
    }
}

/// The ledger's CSV export.
///
/// Columns: date, store, category, payment, total_yen, tax10_yen, tax8_yen, invoice_no, items, note.
/// Rows run oldest first, as an accountant reads them. Category and payment are written in
/// Japanese (食料品, 現金), the language of the receipts and of 確定申告. Amounts are plain
/// integers with no ¥ or comma, so spreadsheets treat them as numbers.
public enum ExpenseCSV {
    public static let header = [
        "date", "store", "category", "payment", "total_yen", "tax10_yen", "tax8_yen", "invoice_no", "items", "note",
    ]

    public static func document(_ expenses: [CSVExpense]) -> Data {
        let sorted = expenses.enumerated().sorted { a, b in
            a.element.dayKey != b.element.dayKey ? a.element.dayKey < b.element.dayKey : a.offset < b.offset
        }.map(\.element)
        return CSVWriter.document(header: header, rows: sorted.map(row))
    }

    static func row(_ e: CSVExpense) -> [String] {
        [
            CSVWriter.field(e.dayKey),
            CSVWriter.textField(e.storeName),
            CSVWriter.field(e.category.japaneseName),
            CSVWriter.field(paymentName(e.payment)),
            String(e.totalYen),
            e.tax10Yen.map(String.init) ?? "",
            e.tax8Yen.map(String.init) ?? "",
            CSVWriter.field(e.invoiceNumber ?? ""),
            CSVWriter.textField(itemsText(e.items)),
            CSVWriter.textField(e.note),
        ]
    }

    /// `牛乳 198 ※; 値引 -100 ※; 洗剤 398`: name, price, ※ for the 8% rate, separated by "; ".
    static func itemsText(_ items: [LineItemDraft]) -> String {
        items.map { "\($0.name) \($0.priceYen)\($0.isReducedRate ? " ※" : "")" }.joined(separator: "; ")
    }

    static func paymentName(_ payment: PaymentMethod) -> String {
        switch payment {
        case .cash: "現金"
        case .credit: "クレジット"
        case .icCard: "交通系IC・電子マネー"
        case .qrPay: "QR決済"
        case .other: "その他"
        }
    }

    /// `kakeibo-2026-11.csv`
    public static func fileName(month: LedgerMonth) -> String { "kakeibo-\(month.key).csv" }

    /// `kakeibo-2026.csv`
    public static func fileName(year: Int) -> String { String(format: "kakeibo-%04d.csv", year) }
}
