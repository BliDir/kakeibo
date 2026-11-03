import Foundation

/// Expense category. v1.0 has a fixed set of 9.
///
/// Named `ExpenseCategory`, not `Category`, because Objective-C's `Category`
/// type makes the short name ambiguous in any file that imports SwiftUI or UIKit.
///
/// Raw values are stored on disk and in CSV exports, so never rename them.
/// Names live here rather than in the String Catalog because screens show
/// both names side by side (食料品 Groceries) and exports need fixed names
/// whatever the UI language is.
public enum ExpenseCategory: String, CaseIterable, Sendable, Codable, Equatable {
    case groceries
    case dining
    case transport
    case household
    case kids
    case health
    case shopping
    case utilities
    case other

    public var japaneseName: String {
        switch self {
        case .groceries: "食料品"
        case .dining: "外食"
        case .transport: "交通"
        case .household: "日用品"
        case .kids: "子ども"
        case .health: "医療"
        case .shopping: "買い物"
        case .utilities: "光熱・通信"
        case .other: "その他"
        }
    }

    public var englishName: String {
        switch self {
        case .groceries: "Groceries"
        case .dining: "Dining out"
        case .transport: "Transport"
        case .household: "Household"
        case .kids: "Kids"
        case .health: "Health"
        case .shopping: "Shopping"
        case .utilities: "Utilities"
        case .other: "Other"
        }
    }

    public func displayName(for language: AppLanguage) -> String {
        switch language {
        case .ja: japaneseName
        case .en: englishName
        }
    }
}
