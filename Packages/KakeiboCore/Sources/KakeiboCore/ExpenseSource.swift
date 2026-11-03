import Foundation

/// Where an expense came from. Raw values are stored on disk, so never rename them.
public enum ExpenseSource: String, CaseIterable, Sendable, Codable, Equatable {
    /// Read from a receipt photo.
    case scan
    /// Typed in by the user.
    case manual
}
