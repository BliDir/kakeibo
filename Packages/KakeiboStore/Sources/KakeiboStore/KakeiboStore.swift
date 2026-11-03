import Foundation
import KakeiboCore

/// Namespace for persistence: SwiftData models (`VersionedSchema`),
/// `ExpenseRepository` and `PhotoStore` (later tickets).
public enum KakeiboStore {
    /// Folder name for receipt photos inside Application Support.
    public static let photosDirectoryName = "Receipts"
}
