import Foundation
import Testing
import KakeiboCore

@Suite struct CSVWriterTests {
    @Test(arguments: [
        ("plain", "plain"),
        ("ローソン 中野店", "ローソン 中野店"),
        ("a,b", "\"a,b\""),
        ("say \"hi\"", "\"say \"\"hi\"\"\""),
        ("line1\nline2", "\"line1\nline2\""),
        ("line1\r\nline2", "\"line1\r\nline2\""),
        ("\"", "\"\"\"\""),
        ("", ""),
    ])
    func escapesPerRFC4180(value: String, expected: String) {
        #expect(CSVWriter.field(value) == expected)
    }

    @Test(arguments: [
        ("=HYPERLINK(\"x\")", "\"'=HYPERLINK(\"\"x\"\")\""),
        ("+81 3", "'+81 3"),
        ("-SUM(A1)", "'-SUM(A1)"),
        ("@cmd", "'@cmd"),
        ("\tx", "'\tx"),
        ("BBQ = fun", "BBQ = fun"),
    ])
    func textFieldsNeverStartAsFormulas(value: String, expected: String) {
        #expect(CSVWriter.textField(value) == expected)
    }

    @Test func documentHasBOMAndCRLF() {
        let data = CSVWriter.document(header: ["a", "b"], rows: [["1", "2"], ["3", "\"x\ny\""]])
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        #expect(text == "a,b\r\n1,2\r\n3,\"x\ny\"\r\n")
    }
}

@Suite struct ExpenseCSVTests {
    static let groceries = CSVExpense(
        dayKey: "2026-11-03", storeName: "まいばすけっと, 東神奈川店", category: .groceries, payment: .icCard,
        totalYen: 1_310, tax10Yen: 29, tax8Yen: 72, invoiceNumber: "T1234567890123",
        items: [LineItemDraft(name: "牛乳", priceYen: 248, isReducedRate: true),
                LineItemDraft(name: "値引", priceYen: -30, isReducedRate: true),
                LineItemDraft(name: "ゴミ袋", priceYen: 328)],
        note: "週末の\"BBQ\""
    )
    static let cafe = CSVExpense(
        dayKey: "2026-11-01", storeName: "喫茶ポエム", category: .dining, payment: .cash,
        totalYen: 1_050, tax10Yen: nil, tax8Yen: nil, invoiceNumber: nil, items: [], note: ""
    )

    private func lines(_ data: Data) -> [String] {
        String(decoding: data.dropFirst(3), as: UTF8.self).components(separatedBy: "\r\n")
    }

    @Test func headerColumns() {
        #expect(lines(ExpenseCSV.document([])).first ==
                "date,store,category,payment,total_yen,tax10_yen,tax8_yen,invoice_no,items,note")
    }

    @Test func rowsOldestFirstWithEscaping() {
        let rows = lines(ExpenseCSV.document([Self.groceries, Self.cafe]))
        #expect(rows.count == 4)   // header, two rows, empty after the last CRLF
        #expect(rows[1] == "2026-11-01,喫茶ポエム,外食,現金,1050,,,,,")
        #expect(rows[2] == "2026-11-03,\"まいばすけっと, 東神奈川店\",食料品,交通系IC・電子マネー,1310,29,72,T1234567890123,牛乳 248 ※; 値引 -30 ※; ゴミ袋 328,\"週末の\"\"BBQ\"\"\"")
        #expect(rows[3] == "")
    }

    @Test func sameDayKeepsGivenOrder() {
        var later = Self.cafe
        later.dayKey = "2026-11-01"
        later.storeName = "B"
        var earlier = Self.cafe
        earlier.storeName = "A"
        let rows = lines(ExpenseCSV.document([earlier, later]))
        #expect(rows[1].contains(",A,"))
        #expect(rows[2].contains(",B,"))
    }

    @Test func fileNames() {
        #expect(ExpenseCSV.fileName(month: LedgerMonth(year: 2026, month: 11)) == "kakeibo-2026-11.csv")
        #expect(ExpenseCSV.fileName(year: 2026) == "kakeibo-2026.csv")
    }
}
