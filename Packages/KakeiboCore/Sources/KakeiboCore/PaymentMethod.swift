import Foundation

/// How a receipt was paid. Raw values are stored on disk, so never rename them.
///
/// Names live here, like `ExpenseCategory`'s, because screens pair both languages
/// ("Cash · 現金") and CSV exports need fixed Japanese names whatever the UI language is.
public enum PaymentMethod: String, CaseIterable, Sendable, Codable, Equatable {
    case cash
    /// Credit or debit card.
    case credit
    /// Transit IC card or e-money (Suica, PASMO, nanaco, WAON, ...).
    case icCard
    /// QR code payment (PayPay, d払い, 楽天ペイ, ...).
    case qrPay
    case other

    /// Full Japanese name, as used in CSV exports: `交通系IC・電子マネー`.
    public var japaneseName: String {
        switch self {
        case .cash: "現金"
        case .credit: "クレジット"
        case .icCard: "交通系IC・電子マネー"
        case .qrPay: "QR決済"
        case .other: "その他"
        }
    }

    /// Japanese name short enough for a ledger row: `交通系IC`.
    public var shortJapaneseName: String {
        self == .icCard ? "交通系IC" : japaneseName
    }

    public var englishName: String {
        switch self {
        case .cash: "Cash"
        case .credit: "Credit card"
        case .icCard: "IC card"
        case .qrPay: "QR pay"
        case .other: "Other"
        }
    }

    /// Short name in the UI language, for ledger rows: `交通系IC` / `IC card`.
    public func displayName(for language: AppLanguage) -> String {
        switch language {
        case .ja: shortJapaneseName
        case .en: englishName
        }
    }

    /// Both languages, UI language first, for pickers: `現金 · Cash` / `Cash · 現金`.
    public func pairedName(for language: AppLanguage) -> String {
        switch language {
        case .ja: "\(japaneseName) · \(englishName)"
        case .en: "\(englishName) · \(shortJapaneseName)"
        }
    }
}
