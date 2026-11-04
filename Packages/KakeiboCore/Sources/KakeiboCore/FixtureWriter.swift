import Foundation

/// Turns a reviewed scan into parser fixture files (debug tool, T-24).
///
/// - `<name>.txt`: the rebuilt OCR lines, with personal details masked.
/// - `<name>.expected.json`: the review form's values, in the format `ReceiptAccuracyTests` reads.
///   Fields the form has no value for are written as `null` (scored as "nothing to find").
public enum FixtureWriter {
    /// `real-20261104-103012`, in Asia/Tokyo.
    public static func name(at date: Date) -> String {
        "real-" + nameFormatter.string(from: date)
    }

    private static let nameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = KakeiboCore.timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    /// The `.txt` file: one receipt row per line, personal details masked, ending with a newline.
    public static func text(lines: [String]) -> String {
        redact(lines).joined(separator: "\n") + "\n"
    }

    /// The `.expected.json` file, pretty-printed with sorted keys.
    public static func expectedJSON(from draft: ReceiptDraft, scannedOn: Date) throws -> Data {
        func value(_ v: Any?) -> Any { v ?? NSNull() }
        let object: [String: Any] = [
            "scannedOn": DayKey.make(from: scannedOn),
            "storeName": value(draft.storeName),
            "dayKey": value(draft.dayKey),
            "time": value(draft.time),
            "totalYen": value(draft.totalYen),
            "tax10Yen": value(draft.tax10Yen),
            "tax8Yen": value(draft.tax8Yen),
            "payment": value(draft.payment?.rawValue),
            "category": value(draft.category?.rawValue),
            "invoiceNumber": value(draft.invoiceNumber),
            "items": draft.items.map {
                ["name": $0.name, "priceYen": $0.priceYen, "isReducedRate": $0.isReducedRate] as [String: Any]
            },
        ]
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(Data("\n".utf8))
        return data
    }

    // MARK: - Personal details

    /// Lines that carry a personal number: card, member, approval, slip, terminal, customer.
    private static let personalWords = [
        "会員", "カード", "CARD", "承認", "伝票", "端末", "お客様", "顧客", "口座", "取引",
    ]

    /// The store's own phone and fax numbers are public; keep them.
    private static let storeContactWords = ["TEL", "FAX", "電話"]

    /// Masks digits that could identify the shopper, so captured receipts are safe to commit.
    ///
    /// - On lines about cards, members, approvals and similar, every digit becomes `0`.
    /// - Anywhere else, a run of 8 or more digits (ignoring spaces, hyphens and `*`) becomes
    ///   `0`s, except the store's invoice number (`T` + 13 digits), its phone and fax numbers,
    ///   and amounts with commas.
    /// The line layout is kept so the parser sees the same shape.
    public static func redact(_ lines: [String]) -> [String] {
        lines.map { line in
            let upper = line.uppercased()
            if personalWords.contains(where: upper.contains), !line.contains("登録番号") {
                return String(line.map { $0.isASCII && $0.isNumber ? "0" : $0 })
            }
            // The store's phone and invoice registration number are public, and the parser
            // reads the latter. OCR often drops the T (登録番号 1234567890123), so keep the line.
            if storeContactWords.contains(where: upper.contains) || line.contains("登録番号") { return line }
            return maskLongNumbers(line)
        }
    }

    private static let longNumber = try! NSRegularExpression(
        pattern: #"(?<![T\d])(?:[\d*Xx][\s\-]?){7,}[\d*Xx](?!\d)"#
    )

    private static func maskLongNumbers(_ line: String) -> String {
        var result = line
        let matches = longNumber.matches(in: line, range: NSRange(line.startIndex..., in: line))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let digits = result[range].filter(\.isNumber).count
            guard digits >= 4 else { continue }   // a mask like ****-**** with few digits is already safe
            result.replaceSubrange(range, with: String(result[range].map { $0.isNumber ? "0" : $0 }))
        }
        return result
    }
}
