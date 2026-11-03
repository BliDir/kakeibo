import Foundation

/// How a receipt was paid. Raw values are stored on disk, so never rename them.
public enum PaymentMethod: String, CaseIterable, Sendable, Codable, Equatable {
    case cash
    /// Credit or debit card.
    case credit
    /// Transit IC card or e-money (Suica, PASMO, nanaco, WAON, ...).
    case icCard
    /// QR code payment (PayPay, d払い, 楽天ペイ, ...).
    case qrPay
    case other
}
