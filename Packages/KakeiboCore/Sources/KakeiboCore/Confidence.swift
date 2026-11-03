import Foundation

/// How sure the reader is about a field. Ordered `low < medium < high`.
/// Raw values are stored on disk, so never rename them.
public enum Confidence: String, CaseIterable, Sendable, Codable, Equatable, Comparable {
    case low
    case medium
    case high

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }
}
