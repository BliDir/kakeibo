import KakeiboCore
import SwiftUI

/// One color and one SF Symbol per category.
extension ExpenseCategory {
    var color: Color {
        switch self {
        case .groceries: Color(.categoryGroceries)
        case .dining: Color(.categoryDining)
        case .household: Color(.categoryHousehold)
        case .transport: Color(.categoryTransport)
        case .kids: Color(.categoryKids)
        case .health: Color(.categoryHealth)
        case .shopping: Color(.categoryShopping)
        case .utilities: Color(.categoryUtilities)
        case .other: Color(.categoryOther)
        }
    }

    /// A soft fill for category badges, readable in both modes.
    var tint: Color { color.opacity(0.16) }

    var symbolName: String {
        switch self {
        case .groceries: "cart"
        case .dining: "fork.knife"
        case .household: "house"
        case .transport: "tram"
        case .kids: "figure.and.child.holdinghands"
        case .health: "cross.case"
        case .shopping: "bag"
        case .utilities: "bolt"
        case .other: "ellipsis.circle"
        }
    }
}

/// A category's symbol on its tinted square, for list rows and summaries.
struct CategoryBadge: View {
    let category: ExpenseCategory
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(category.color)
            .frame(width: size, height: size)
            .background(category.tint, in: RoundedRectangle(cornerRadius: size * 0.26))
            .accessibilityHidden(true)
    }
}
